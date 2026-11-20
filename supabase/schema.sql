-- GamingSocial en Supabase: tablas, seguridad (RLS), contadores y freno anti-bots.

-- ===== Funciones base =====
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;
create policy admins_self on public.admins for select to authenticated
  using (user_id = auth.uid());

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.admins where user_id = auth.uid())
$$;

-- ===== Perfiles =====
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  username_lower text not null,
  bio text not null default '' check (char_length(bio) <= 160),
  photo_url text not null default ''
    check (photo_url = '' or photo_url ~ '^https://res\.cloudinary\.com/hagnq5mv/'),
  favorite_games text[] not null default '{}' check (cardinality(favorite_games) <= 10),
  banned boolean not null default false,
  deleted boolean not null default false,
  accepted_terms boolean not null,
  terms_version int not null,
  accepted_terms_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  last_action_at timestamptz
);
create unique index profiles_username_lower_key on public.profiles(username_lower) where not deleted;
alter table public.profiles enable row level security;

create function public.can_write() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and banned = false)
$$;

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_insert on public.profiles for insert to authenticated
  with check (
    id = auth.uid() and accepted_terms = true and banned = false and deleted = false
    and username ~ '^[A-Za-z0-9_]{3,20}$' and username_lower = lower(username)
    and bio = '' and photo_url = '' and favorite_games = '{}' and last_action_at is null
  );
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() and public.can_write())
  with check (id = auth.uid());

-- Correo privado (solo el dueño y el admin lo ven)
create table public.user_private (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  created_at timestamptz not null default now()
);
alter table public.user_private enable row level security;
create policy private_read on public.user_private for select to authenticated
  using (id = auth.uid() or public.is_admin());

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_private(id, email) values (new.id, coalesce(new.email, ''))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ¿Existe una cuenta con ese correo? (para el aviso al iniciar sesión)
create function public.email_exists(p_email text) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists(select 1 from auth.users where lower(email) = lower(p_email))
$$;

-- Freno anti-bots: una acción (publicar/comentar) cada 6 segundos como mínimo.
create function public.touch_action() returns void
language plpgsql security definer set search_path = public as $$
declare last_at timestamptz;
begin
  select last_action_at into last_at from public.profiles where id = auth.uid() for update;
  if last_at is not null and last_at > clock_timestamp() - interval '6 seconds' then
    raise exception 'Espera unos segundos antes de la siguiente acción';
  end if;
  update public.profiles set last_action_at = clock_timestamp() where id = auth.uid();
end $$;

-- ===== Seguir / bloquear =====
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);
alter table public.follows enable row level security;
create policy follows_read on public.follows for select to authenticated using (true);
create policy follows_insert on public.follows for insert to authenticated
  with check (follower_id = auth.uid() and public.can_write());
create policy follows_delete on public.follows for delete to authenticated
  using (follower_id = auth.uid() and public.can_write());

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  username text not null default '',
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
alter table public.blocks enable row level security;
create policy blocks_read on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy blocks_insert on public.blocks for insert to authenticated
  with check (blocker_id = auth.uid() and public.can_write());
create policy blocks_delete on public.blocks for delete to authenticated
  using (blocker_id = auth.uid() and public.can_write());

-- ===== Grupos =====
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 40),
  description text not null default '' check (char_length(description) <= 200),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  owner_name text not null default '',
  members_count int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.groups enable row level security;

create table public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
alter table public.group_members enable row level security;

create function public.ok_group(g text) returns boolean
language sql stable security definer set search_path = public as $$
  select g = '' or exists(
    select 1 from public.group_members where group_id::text = g and user_id = auth.uid())
$$;

create policy groups_read on public.groups for select to authenticated using (true);
create policy groups_insert on public.groups for insert to authenticated
  with check (owner_id = auth.uid() and public.can_write());
create policy groups_delete on public.groups for delete to authenticated
  using (public.is_admin() or (owner_id = auth.uid() and public.can_write()));
create policy gm_read on public.group_members for select to authenticated using (true);
create policy gm_insert on public.group_members for insert to authenticated
  with check (user_id = auth.uid() and public.can_write());
create policy gm_delete on public.group_members for delete to authenticated
  using (user_id = auth.uid() and public.can_write());

create function public.groups_bi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.owner_id := auth.uid();
  new.owner_name := (select username from public.profiles where id = auth.uid());
  new.members_count := 0;
  return new;
end $$;
create trigger groups_bi before insert on public.groups
  for each row execute function public.groups_bi();

create function public.groups_ai() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.group_members(group_id, user_id) values (new.id, new.owner_id);
  return new;
end $$;
create trigger groups_ai after insert on public.groups
  for each row execute function public.groups_ai();

create function public.gm_count() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.groups set members_count = members_count + 1 where id = new.group_id;
  else
    update public.groups set members_count = greatest(members_count - 1, 0) where id = old.group_id;
  end if;
  return null;
end $$;
create trigger gm_count after insert or delete on public.group_members
  for each row execute function public.gm_count();

-- ===== Publicaciones =====
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  author_name text not null default '',
  text text not null check (char_length(text) between 1 and 500),
  image_url text not null default ''
    check (image_url = '' or image_url ~ '^https://res\.cloudinary\.com/hagnq5mv/'),
  video_url text not null default ''
    check (video_url = '' or video_url ~ '^https://res\.cloudinary\.com/hagnq5mv/'),
  link_url text not null default ''
    check (char_length(link_url) <= 300 and (link_url = '' or link_url ~ '^https?://[^ ]+$')),
  group_id text not null default '',
  description text not null default '' check (char_length(description) <= 500),
  views int not null default 0,
  poll_options text[] not null default '{}'
    check (cardinality(poll_options) = 0 or cardinality(poll_options) between 2 and 4),
  poll_counts jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  likes_count int not null default 0,
  comments_count int not null default 0
);
create index posts_created_idx on public.posts(created_at desc);
create index posts_author_idx on public.posts(author_id);
create index posts_group_idx on public.posts(group_id);
alter table public.posts enable row level security;
create policy posts_read on public.posts for select to authenticated using (true);
create policy posts_insert on public.posts for insert to authenticated
  with check (
    author_id = auth.uid() and public.can_write() and public.ok_group(group_id)
    and likes_count = 0 and comments_count = 0 and views = 0
  );
create policy posts_delete on public.posts for delete to authenticated
  using (public.is_admin() or (author_id = auth.uid() and public.can_write()));

create function public.posts_bi() returns trigger
language plpgsql security definer set search_path = public as $$
declare uname text;
begin
  select username into uname from public.profiles where id = auth.uid() and banned = false;
  if uname is null then raise exception 'Cuenta no permitida'; end if;
  perform public.touch_action();
  new.author_id := auth.uid();
  new.author_name := uname;
  new.likes_count := 0; new.comments_count := 0; new.views := 0;
  new.poll_counts := coalesce(
    (select jsonb_object_agg((i - 1)::text, 0)
       from generate_series(1, coalesce(cardinality(new.poll_options), 0)) i),
    '{}'::jsonb);
  return new;
end $$;
create trigger posts_bi before insert on public.posts
  for each row execute function public.posts_bi();

-- Reacciones
create table public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  type text not null default 'love' check (type in ('love','like','sad','angry','wow','confused')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.likes enable row level security;
create policy likes_read on public.likes for select to authenticated using (true);
create policy likes_insert on public.likes for insert to authenticated
  with check (user_id = auth.uid() and public.can_write());
create policy likes_update on public.likes for update to authenticated
  using (user_id = auth.uid() and public.can_write()) with check (user_id = auth.uid());
create policy likes_delete on public.likes for delete to authenticated
  using (user_id = auth.uid() and public.can_write());

create function public.likes_count_fn() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  else
    update public.posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end $$;
create trigger likes_count after insert or delete on public.likes
  for each row execute function public.likes_count_fn();

-- Comentarios y respuestas
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  author_name text not null default '',
  text text not null check (char_length(text) between 1 and 300),
  parent_id text not null default '' check (char_length(parent_id) <= 40),
  reply_to_name text not null default '' check (char_length(reply_to_name) <= 30),
  created_at timestamptz not null default now()
);
create index comments_post_idx on public.comments(post_id, created_at);
alter table public.comments enable row level security;
create policy comments_read on public.comments for select to authenticated using (true);
create policy comments_insert on public.comments for insert to authenticated
  with check (author_id = auth.uid() and public.can_write());
create policy comments_delete on public.comments for delete to authenticated
  using (public.is_admin() or (author_id = auth.uid() and public.can_write()));

create function public.comments_bi() returns trigger
language plpgsql security definer set search_path = public as $$
declare uname text;
begin
  select username into uname from public.profiles where id = auth.uid() and banned = false;
  if uname is null then raise exception 'Cuenta no permitida'; end if;
  perform public.touch_action();
  new.author_id := auth.uid();
  new.author_name := uname;
  return new;
end $$;
create trigger comments_bi before insert on public.comments
  for each row execute function public.comments_bi();

create function public.comments_count_fn() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  else
    update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end $$;
create trigger comments_count after insert or delete on public.comments
  for each row execute function public.comments_count_fn();

-- Votos de encuestas
create table public.votes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  option_index int not null check (option_index >= 0 and option_index < 4),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.votes enable row level security;

create function public.ok_option(p uuid, idx int) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(idx < cardinality((select poll_options from public.posts where id = p)), false)
$$;
create policy votes_read on public.votes for select to authenticated using (user_id = auth.uid());
create policy votes_insert on public.votes for insert to authenticated
  with check (user_id = auth.uid() and public.can_write() and public.ok_option(post_id, option_index));

create function public.votes_ai() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.posts
     set poll_counts = jsonb_set(poll_counts, array[new.option_index::text],
           to_jsonb(coalesce((poll_counts ->> new.option_index::text)::int, 0) + 1))
   where id = new.post_id;
  return null;
end $$;
create trigger votes_ai after insert on public.votes
  for each row execute function public.votes_ai();

-- Visitas (una por persona)
create table public.views (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.views enable row level security;
create policy views_read on public.views for select to authenticated using (true);
create policy views_insert on public.views for insert to authenticated
  with check (user_id = auth.uid() and public.can_write());

create function public.views_ai() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.posts set views = views + 1 where id = new.post_id;
  return null;
end $$;
create trigger views_ai after insert on public.views
  for each row execute function public.views_ai();

-- ===== Denuncias y opiniones =====
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('post','comment','user')),
  target_id text not null default '',
  post_id text not null default '',
  owner_id text not null default '',
  reason text not null default '' check (char_length(reason) <= 300),
  reporter_id uuid not null default auth.uid(),
  reporter_name text not null default '',
  preview text not null default '' check (char_length(preview) <= 140),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
create policy reports_insert on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and public.can_write());
create policy reports_read on public.reports for select to authenticated using (public.is_admin());
create policy reports_delete on public.reports for delete to authenticated using (public.is_admin());

create function public.reports_bi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.reporter_id := auth.uid();
  new.reporter_name := coalesce((select username from public.profiles where id = auth.uid()), '');
  return new;
end $$;
create trigger reports_bi before insert on public.reports
  for each row execute function public.reports_bi();

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  username text not null default '',
  stars int not null check (stars between 1 and 5),
  reason text not null check (char_length(reason) between 1 and 500),
  platform text not null check (platform in ('android','web')),
  created_at timestamptz not null default now()
);
alter table public.feedback enable row level security;
create policy feedback_insert on public.feedback for insert to authenticated
  with check (user_id = auth.uid() and public.can_write());
create policy feedback_read on public.feedback for select to authenticated using (public.is_admin());
create policy feedback_delete on public.feedback for delete to authenticated using (public.is_admin());

create function public.feedback_bi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  new.username := coalesce((select username from public.profiles where id = auth.uid()), '');
  return new;
end $$;
create trigger feedback_bi before insert on public.feedback
  for each row execute function public.feedback_bi();

-- ===== Chats privados =====
create table public.chats (
  id text primary key,
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  names jsonb not null default '{}'::jsonb,
  last_message text not null default '',
  last_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table public.chats enable row level security;
create policy chats_read on public.chats for select to authenticated
  using (auth.uid() in (user_a, user_b));

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id text not null references public.chats(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check (char_length(text) between 1 and 500),
  created_at timestamptz not null default now()
);
create index messages_chat_idx on public.messages(chat_id, created_at desc);
alter table public.messages enable row level security;
create policy messages_read on public.messages for select to authenticated
  using (auth.uid()::text = any(string_to_array(chat_id, '_')));

create function public.send_message(p_other uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  cid text;
  a uuid; b uuid;
  me_name text; other_name text;
begin
  if me is null or not public.can_write() then raise exception 'Cuenta no permitida'; end if;
  if p_other = me then raise exception 'No puedes escribirte a ti mismo'; end if;
  if char_length(p_body) < 1 or char_length(p_body) > 500 then raise exception 'Mensaje no válido'; end if;
  select username into me_name from public.profiles where id = me;
  select username into other_name from public.profiles where id = p_other and deleted = false;
  if other_name is null then raise exception 'Esa persona no existe'; end if;
  if exists(select 1 from public.blocks where blocker_id = p_other and blocked_id = me) then
    raise exception 'No puedes enviar mensajes a esta persona';
  end if;
  if me::text < p_other::text then a := me; b := p_other; else a := p_other; b := me; end if;
  cid := a::text || '_' || b::text;
  insert into public.chats(id, user_a, user_b, names)
  values (cid, a, b, jsonb_build_object(me::text, me_name, p_other::text, other_name))
  on conflict (id) do update set names = excluded.names;
  insert into public.messages(chat_id, sender_id, text) values (cid, me, p_body);
  update public.chats set last_message = left(p_body, 100), last_at = now() where id = cid;
end $$;

-- ===== Funciones del administrador y grupos =====
create function public.admin_set_banned(p_user uuid, p_banned boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo el administrador'; end if;
  update public.profiles set banned = p_banned where id = p_user;
end $$;

create function public.admin_delete_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo el administrador'; end if;
  delete from public.posts where author_id = p_user;
  update public.profiles
     set banned = true, deleted = true, username = '[eliminado]',
         username_lower = '[eliminado]', bio = '', photo_url = ''
   where id = p_user;
end $$;

create function public.delete_group(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_admin() or exists(
      select 1 from public.groups where id = p_group and owner_id = auth.uid())) then
    raise exception 'No tienes permiso';
  end if;
  delete from public.posts where group_id = p_group::text;
  delete from public.groups where id = p_group;
end $$;

-- ===== Permisos =====
revoke all on all tables in schema public from anon;
revoke update on all tables in schema public from authenticated;
grant update (bio, photo_url, favorite_games) on public.profiles to authenticated;
grant update (type) on public.likes to authenticated;
revoke insert, update, delete on public.admins, public.chats, public.messages, public.user_private from authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant execute on function public.email_exists(text) to anon, authenticated;

-- ===== Tiempo real =====
alter publication supabase_realtime add table
  public.posts, public.comments, public.likes, public.votes, public.profiles,
  public.follows, public.blocks, public.groups, public.group_members,
  public.chats, public.messages, public.reports, public.feedback, public.admins;

-- Conteo por tipo de reacción (migración reaction_counts)
alter table public.posts add column if not exists reaction_counts jsonb not null default '{}';

-- Preguntas de ayuda (migración feedback_questions)
alter table public.feedback add column if not exists kind text not null default 'rating' check (kind in ('rating','question'));
alter table public.feedback drop constraint if exists feedback_stars_check;
alter table public.feedback add constraint feedback_stars_check check (stars between 0 and 5 and ((kind='rating' and stars>=1) or (kind='question' and stars=0)));
