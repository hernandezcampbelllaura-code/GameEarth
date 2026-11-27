import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

typedef Json = Map<String, dynamic>;

SupabaseClient get sb => Supabase.instance.client;

/// UID del usuario con sesión iniciada.
String get myUid => sb.auth.currentUser!.id;

/// Un registro de la base de datos (con las claves en camelCase).
class Doc {
  final String id;
  final Json _data;
  final bool exists;
  const Doc(this.id, this._data, {this.exists = true});
  Json data() => _data;
}

/// Lista de registros.
class Snap {
  final List<Doc> docs;
  const Snap(this.docs);
}

String _camelKey(String k) {
  final p = k.split('_');
  final b = StringBuffer(p.first);
  for (final s in p.skip(1)) {
    if (s.isEmpty) continue;
    b.write(s[0].toUpperCase());
    b.write(s.substring(1));
  }
  return b.toString();
}

Doc _toDoc(Json row, String Function(Json)? idOf) {
  final out = <String, dynamic>{};
  row.forEach((k, v) {
    final key = _camelKey(k);
    if (v is String && key.endsWith('At')) {
      out[key] = DateTime.tryParse(v)?.toLocal() ?? v;
    } else {
      out[key] = v;
    }
  });
  if (row.containsKey('user_a') && row.containsKey('user_b')) {
    out['members'] = [row['user_a'], row['user_b']];
  }
  if (row.containsKey('option_index')) out['option'] = row['option_index'];
  final id = idOf != null ? idOf(row) : (row['id'] ?? '').toString();
  return Doc(id, out);
}

/// Convierte una fila de la base de datos en un [Doc] (usado también en pruebas).
Doc docFromRow(Json row, {String Function(Json)? idOf}) => _toDoc(row, idOf);

/// Ordena comentarios: cada principal seguido de sus respuestas. Una respuesta
/// cuyo comentario original ya no existe se muestra como principal.
List<MapEntry<Doc, bool>> threadComments(List<Doc> all) {
  String parentOf(Doc d) => (d.data()['parentId'] ?? '').toString();
  final ids = {for (final d in all) d.id};
  final rows = <MapEntry<Doc, bool>>[];
  for (final r in all) {
    final p = parentOf(r);
    if (p.isNotEmpty && ids.contains(p)) continue;
    rows.add(MapEntry(r, false));
    for (final x in all) {
      if (parentOf(x) == r.id) rows.add(MapEntry(x, true));
    }
  }
  return rows;
}

int _watchCounter = 0;

/// Convierte una consulta en un flujo que se actualiza solo: escucha los
/// cambios en tiempo real y además revisa cada 45 segundos por si la conexión
/// en tiempo real está bloqueada.
/// Falso cuando la app está en segundo plano: así no se consulta el servidor
/// sin necesidad (ahorra datos y carga cuando hay muchas personas conectadas).
bool appActive = true;

Stream<Snap> watchQuery(
  String table,
  Future<List<dynamic>> Function() load, {
  String Function(Json)? id,
  String? filterColumn,
  Object? filterValue,
}) {
  late final StreamController<Snap> c;
  RealtimeChannel? ch;
  Timer? deb;
  Timer? poll;
  var closed = true;

  Future<void> run() async {
    try {
      final rows = await load();
      if (closed) return;
      c.add(Snap([
        for (final r in rows) _toDoc(Map<String, dynamic>.from(r as Map), id),
      ]));
    } catch (e) {
      if (!closed) c.addError(e);
    }
  }

  c = StreamController<Snap>.broadcast(
    onListen: () {
      closed = false;
      run();
      try {
        ch = sb
            .channel('w${_watchCounter++}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: table,
              filter: filterColumn == null
                  ? null
                  : PostgresChangeFilter(
                      type: PostgresChangeFilterType.eq,
                      column: filterColumn,
                      value: filterValue!,
                    ),
              callback: (_) {
                deb?.cancel();
                deb = Timer(const Duration(milliseconds: 250), run);
              },
            )
            .subscribe();
      } catch (_) {}
      poll = Timer.periodic(const Duration(seconds: 45), (_) {
        if (appActive) run();
      });
    },
    onCancel: () {
      closed = true;
      deb?.cancel();
      poll?.cancel();
      final x = ch;
      ch = null;
      if (x != null) {
        try {
          sb.removeChannel(x);
        } catch (_) {}
      }
    },
  );
  return c.stream;
}

/// Acceso a la base de datos y todas las acciones de la app.
class Db {
  Db._();

  // ---------- Lecturas en vivo ----------

  static Stream<Snap> watchPosts({
    String? authorId,
    String? groupId,
    int limit = 100,
    bool includeCollab = false,
  }) {
    return watchQuery('posts', () {
      var q = sb.from('posts').select();
      if (authorId != null && includeCollab) {
        q = q.or('author_id.eq.$authorId,collab_id.eq.$authorId');
      } else if (authorId != null) {
        q = q.eq('author_id', authorId);
      }
      if (groupId != null) q = q.eq('group_id', groupId);
      return q.order('created_at', ascending: false).limit(limit);
    });
  }

  static Stream<Doc> watchProfile(String uid) {
    return watchQuery(
      'profiles',
      () => sb.from('profiles').select().eq('id', uid),
      filterColumn: 'id',
      filterValue: uid,
    ).map((s) => s.docs.isEmpty ? Doc(uid, const {}, exists: false) : s.docs.first);
  }

  static Stream<Snap> watchUsers() => watchQuery('profiles',
      () => sb.from('profiles').select().order('created_at', ascending: false).limit(200));

  static Stream<Snap> watchFeedback() => watchQuery('feedback',
      () => sb.from('feedback').select().order('created_at', ascending: false).limit(100));

  static Stream<Snap> watchReports() => watchQuery('reports',
      () => sb.from('reports').select().order('created_at', ascending: false).limit(100));

  static Stream<Snap> watchGroups() => watchQuery('groups',
      () => sb.from('groups').select().order('created_at', ascending: false).limit(100));

  static Stream<Doc> watchGroup(String id) {
    return watchQuery(
      'groups',
      () => sb.from('groups').select().eq('id', id),
      filterColumn: 'id',
      filterValue: id,
    ).map((s) => s.docs.isEmpty ? Doc(id, const {}, exists: false) : s.docs.first);
  }

  static Stream<Doc> watchMembership(String groupId) {
    return watchQuery(
      'group_members',
      () => sb.from('group_members').select().eq('group_id', groupId).eq('user_id', myUid),
      filterColumn: 'group_id',
      filterValue: groupId,
      id: (r) => r['user_id'].toString(),
    ).map((s) => s.docs.isEmpty ? Doc(myUid, const {}, exists: false) : s.docs.first);
  }

  static Stream<Snap> watchComments(String postId) => watchQuery(
        'comments',
        () => sb.from('comments').select().eq('post_id', postId).order('created_at'),
        filterColumn: 'post_id',
        filterValue: postId,
      );

  static Stream<Snap> watchChats() => watchQuery('chats', () {
        final me = myUid;
        return sb
            .from('chats')
            .select()
            .or('user_a.eq.$me,user_b.eq.$me')
            .order('last_at', ascending: false);
      });

  static Stream<Snap> watchMessages(String chatId) => watchQuery(
        'messages',
        () => sb
            .from('messages')
            .select()
            .eq('chat_id', chatId)
            .order('created_at', ascending: false)
            .limit(100),
        filterColumn: 'chat_id',
        filterValue: chatId,
      );

  static Stream<int> watchFollowCount(String uid, {required bool followers}) {
    final col = followers ? 'following_id' : 'follower_id';
    return watchQuery(
      'follows',
      () => sb.from('follows').select().eq(col, uid),
      id: (r) => '${r['follower_id']}_${r['following_id']}',
    ).map((s) => s.docs.length);
  }

  static Future<List<Doc>> searchUsers(String q) async {
    final safe = q.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final rows = await sb
        .from('profiles')
        .select()
        .ilike('username_lower', '$safe%')
        .eq('deleted', false)
        .limit(25);
    return [for (final r in rows) _toDoc(Map<String, dynamic>.from(r), null)];
  }

  // Perfiles en memoria (para las fotos de perfil sin abrir mil conexiones).
  static final Map<String, Future<Json?>> _profiles = {};

  /// Las primeras [limit] personas que sigues (las más antiguas primero).
  static Future<List<Doc>> firstFollowing({int limit = 10}) async {
    final rows = await sb
        .from('follows')
        .select('following_id')
        .eq('follower_id', myUid)
        .order('created_at', ascending: true)
        .limit(limit);
    final ids = [for (final r in rows) r['following_id'].toString()];
    if (ids.isEmpty) return [];
    final ps = await sb.from('profiles').select().inFilter('id', ids);
    final byId = {
      for (final p in ps)
        p['id'].toString(): _toDoc(Map<String, dynamic>.from(p), null),
    };
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  static Future<Json?> profileOf(String uid) {
    return _profiles.putIfAbsent(uid, () async {
      try {
        final r = await sb.from('profiles').select().eq('id', uid).maybeSingle();
        return r == null ? null : _toDoc(Map<String, dynamic>.from(r), null).data();
      } catch (_) {
        _profiles.remove(uid);
        return null;
      }
    });
  }

  static void forgetProfile(String uid) => _profiles.remove(uid);

  static Future<Doc?> postById(String id) async {
    final r = await sb.from('posts').select().eq('id', id).maybeSingle();
    return r == null ? null : _toDoc(Map<String, dynamic>.from(r), null);
  }

  static Future<String> userEmail(String uid) async {
    final r = await sb.from('user_private').select('email').eq('id', uid).maybeSingle();
    return (r?['email'] ?? '') as String;
  }

  // ---------- Publicaciones ----------

  /// Publica y devuelve el id de la nueva publicación.
  static Future<String> createPost(
    String text,
    String imageUrl, {
    String videoUrl = '',
    String linkUrl = '',
    String groupId = '',
    String description = '',
    List<String> pollOptions = const [],
    String collabId = '',
  }) async {
    final row = await sb.from('posts').insert({
      'text': text,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'link_url': linkUrl,
      'group_id': groupId,
      'description': description,
      'poll_options': pollOptions,
      if (collabId.isNotEmpty) 'collab_id': collabId,
    }).select('id').single();
    return row['id'].toString();
  }

  /// Reacciona a una publicación. Si ya tenías esa misma reacción, la quita;
  /// si tenías otra, la cambia.
  static final Set<String> _reacting = {};

  static Future<void> react(String postId, String type) async {
    // Evita toques dobles: mientras una reacción se guarda, se ignora la siguiente.
    if (!_reacting.add(postId)) return;
    final mine = Session.i.myLikes;
    final before = mine.value;
    try {
      final cur = before[postId];
      if (cur == type) {
        mine.value = {...before}..remove(postId);
        await sb
            .from('likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', myUid);
        Taste.bump(postId, -3);
      } else {
        mine.value = {...before, postId: type};
        await sb.from('likes').upsert(
          {'post_id': postId, 'user_id': myUid, 'type': type},
          onConflict: 'post_id,user_id',
        );
        if (cur == null) Taste.bump(postId, 3);
      }
    } catch (e) {
      mine.value = before;
      final msg = '$e';
      if (msg.contains('23505') || msg.contains('duplicate key')) return;
      rethrow;
    } finally {
      _reacting.remove(postId);
    }
  }

  /// Quién reaccionó y con qué (para ver los nombres por reacción).
  static Future<List<Map<String, String>>> reactionUsers(String postId) async {
    final rows = await sb
        .from('likes')
        .select('user_id,type,created_at')
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(500);
    final ids = {for (final r in rows) r['user_id'].toString()}.toList();
    if (ids.isEmpty) return [];
    final ps = await sb.from('profiles').select('id,username').inFilter('id', ids);
    final names = {for (final p in ps) p['id'].toString(): (p['username'] ?? '').toString()};
    return [
      for (final r in rows)
        {
          'uid': r['user_id'].toString(),
          'name': names[r['user_id'].toString()] ?? '',
          'type': (r['type'] ?? 'love').toString(),
        },
    ];
  }

  /// Cuenta cuántas reacciones hay de cada tipo.
  static Future<Map<String, int>> reactionCounts(String postId) async {
    final rows = await sb.from('likes').select('type').eq('post_id', postId).limit(1000);
    final out = <String, int>{};
    for (final d in rows) {
      final t = (d['type'] ?? 'love') as String;
      out[t] = (out[t] ?? 0) + 1;
    }
    return out;
  }

  /// Vota en la encuesta de una publicación (un voto por persona).
  static Future<void> vote(String postId, int option) async {
    await sb.from('votes').insert({'post_id': postId, 'option_index': option});
    Session.i.myVotes.value = {...Session.i.myVotes.value, postId: option};
  }

  /// Guarda la opinión (estrellas + motivo) y, si está configurado, la manda
  /// también al correo por medio de Formspree.
  static Future<void> editPost(
    String id,
    String text,
    String description,
    String link,
  ) =>
      sb.rpc('edit_post', params: {
        'p_post': id,
        'p_text': text,
        'p_description': description,
        'p_link': link,
      });

  static Future<void> leaveCollab(String id) =>
      sb.rpc('leave_collab', params: {'p_post': id});

  /// Todas mis publicaciones (para estadísticas).
  static Future<List<Doc>> myPosts() async {
    final rows = await sb
        .from('posts')
        .select()
        .eq('author_id', myUid)
        .order('created_at', ascending: false)
        .limit(500);
    return [for (final r in rows) _toDoc(Map<String, dynamic>.from(r), null)];
  }

  static Future<DateTime?> myBirthday() async {
    final r = await sb.from('user_private').select('birthday').eq('id', myUid).maybeSingle();
    final b = r?['birthday'];
    return b is String ? DateTime.tryParse(b) : null;
  }

  static Future<void> setBirthday(DateTime? d, bool show) => sb.rpc(
        'set_birthday',
        params: {
          'p_date': d == null ? null : d.toIso8601String().substring(0, 10),
          'p_show': show,
        },
      );

  /// Solicitud de verificación. Si hay un formulario de correo configurado,
  /// también se envía un aviso al correo de la administradora.
  static Future<void> requestVerification(String note) async {
    await sb.rpc('request_verification', params: {'p_note': note});
    final url = FeedbackConfig.emailFormUrl;
    if (url.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'asunto': 'Solicitud de verificación en GamersLore',
              'usuario': Session.i.username,
              'nota': note,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  static Stream<Snap> watchMyVerification() => watchQuery(
        'verification_requests',
        () => sb
            .from('verification_requests')
            .select()
            .eq('user_id', myUid)
            .order('created_at', ascending: false)
            .limit(1),
      );

  static Stream<Snap> watchVerifications() => watchQuery(
        'verification_requests',
        () => sb
            .from('verification_requests')
            .select()
            .order('created_at', ascending: false)
            .limit(100),
      );

  static Future<void> reviewVerification(String id, bool approve) =>
      sb.rpc('admin_review_verification', params: {'p_request': id, 'p_approve': approve});

  static Future<void> setVerified(String uid, bool v) {
    forgetProfile(uid);
    return sb.rpc('admin_set_verified', params: {'p_user': uid, 'p_verified': v});
  }

  /// Pregunta de ayuda que llega al panel de administración.
  static Future<void> askQuestion(String text) async {
    await sb.from('feedback').insert({
      'stars': 0,
      'kind': 'question',
      'reason': text,
      'platform': kIsWeb ? 'web' : 'android',
    });
  }

  static Future<void> sendFeedback(int stars, String reason) async {
    final name = Session.i.username;
    await sb.from('feedback').insert({
      'stars': stars,
      'reason': reason,
      'platform': kIsWeb ? 'web' : 'android',
    });
    final url = FeedbackConfig.emailFormUrl;
    if (url.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              '_subject': 'GamersLore: $stars/5 de @$name',
              'estrellas': '$stars de 5',
              'usuario': '@$name',
              'motivo': reason,
              'plataforma': kIsWeb ? 'web' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Si el correo falla, la opinión ya quedó guardada.
    }
  }

  static final Set<String> _seenViews = {};

  /// Suma una visita (una sola por persona). No cuenta las del propio autor.
  static Future<void> registerView(String postId, String authorId) async {
    if (authorId == myUid || !_seenViews.add(postId)) return;
    Taste.bump(postId, 1);
    try {
      await sb.from('views').upsert({'post_id': postId, 'user_id': myUid},
          onConflict: 'post_id,user_id', ignoreDuplicates: true);
    } catch (_) {
      // Una visita que falla no debe molestar a nadie.
    }
  }

  static Future<void> addComment(
    String postId,
    String text, {
    String parentId = '',
    String replyToName = '',
  }) async {
    await sb.from('comments').insert({
      'post_id': postId,
      'text': text,
      'parent_id': parentId,
      'reply_to_name': replyToName,
    });
    Taste.bump(postId, 4);
  }

  static Future<void> deleteComment(String postId, String commentId) async {
    await sb.from('comments').delete().eq('id', commentId);
  }

  // ---------- Chats privados ----------

  static String chatId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  static Future<void> sendMessage(
    String otherUid,
    String otherName,
    String text,
  ) async {
    await sb.rpc('send_message', params: {'p_other': otherUid, 'p_body': text});
  }

  // ---------- Grupos ----------

  static Future<void> createGroup(String name, String description) async {
    await sb.from('groups').insert({'name': name, 'description': description});
  }

  static Future<void> joinGroup(String groupId) async {
    await sb.from('group_members').insert({'group_id': groupId});
  }

  static Future<void> leaveGroup(String groupId) async {
    await sb.from('group_members').delete().eq('group_id', groupId).eq('user_id', myUid);
  }

  /// Borra el grupo y sus publicaciones (dueño o admin).
  static Future<void> deleteGroup(String groupId) async {
    await sb.rpc('delete_group', params: {'p_group': groupId});
  }

  // ---------- Seguir / bloquear ----------

  static Future<void> follow(String other) async {
    await sb.from('follows').insert({'follower_id': myUid, 'following_id': other});
  }

  static Future<void> unfollow(String other) async {
    await sb.from('follows').delete().eq('follower_id', myUid).eq('following_id', other);
  }

  static Future<void> block(String other, String name) async {
    await sb.from('blocks').upsert({
      'blocker_id': myUid,
      'blocked_id': other,
      'username': name,
    });
    await unfollow(other);
  }

  static Future<void> unblock(String other) async {
    await sb.from('blocks').delete().eq('blocker_id', myUid).eq('blocked_id', other);
  }

  // ---------- Perfil ----------

  static Future<void> updateProfile({
    required String bio,
    required String photoUrl,
    required List<String> favoriteGames,
  }) async {
    await sb.from('profiles').update({
      'bio': bio,
      'photo_url': photoUrl,
      'favorite_games': favoriteGames,
    }).eq('id', myUid);
    forgetProfile(myUid);
  }

  // ---------- Reportes ----------

  static Future<void> report({
    required String type, // post | comment | user
    required String targetId,
    required String ownerId,
    required String reason,
    String? postId,
    String preview = '',
  }) async {
    await sb.from('reports').insert({
      'type': type,
      'target_id': targetId,
      'post_id': postId ?? '',
      'owner_id': ownerId,
      'reason': reason,
      'preview': preview.length > 140 ? preview.substring(0, 140) : preview,
    });
  }

  // ---------- Solo administrador ----------

  static Future<void> setBanned(String userId, bool banned) async {
    await sb.rpc('admin_set_banned', params: {'p_user': userId, 'p_banned': banned});
  }

  /// Borra las publicaciones del usuario y deja la cuenta bloqueada.
  static Future<void> adminDeleteUser(String userId, String usernameLower) async {
    await sb.rpc('admin_delete_user', params: {'p_user': userId});
  }

  static Future<void> adminDeletePost(String postId) async {
    await sb.from('posts').delete().eq('id', postId);
  }

  static Future<void> dismissReport(String reportId) async {
    await sb.from('reports').delete().eq('id', reportId);
  }
}

/// Datos de la sesión actual (bloqueados, seguidos, si es admin, mis votos).
class Session {
  Session._();
  static final Session i = Session._();

  final ValueNotifier<Set<String>> blocked = ValueNotifier<Set<String>>({});
  final ValueNotifier<Set<String>> following = ValueNotifier<Set<String>>({});
  final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);
  final ValueNotifier<Map<String, String>> myLikes =
      ValueNotifier<Map<String, String>>({});
  final ValueNotifier<Map<String, int>> myVotes = ValueNotifier<Map<String, int>>({});
  String username = '';
  /// Reel recién publicado: aparece de primero en la pestaña Reels.
  final ValueNotifier<String?> focusReel = ValueNotifier<String?>(null);

  final List<StreamSubscription<dynamic>> _subs = [];

  void start(String uid) {
    Taste.load();
    stop();
    _subs.add(Db.watchProfile(uid).listen(
      (d) => username = (d.data()['username'] as String?) ?? username,
      onError: (_) {},
    ));
    _subs.add(watchQuery(
      'blocks',
      () => sb.from('blocks').select().eq('blocker_id', uid),
      id: (r) => r['blocked_id'].toString(),
    ).listen(
      (s) => blocked.value = s.docs.map((d) => d.id).toSet(),
      onError: (_) {},
    ));
    _subs.add(watchQuery(
      'follows',
      () => sb.from('follows').select().eq('follower_id', uid),
      id: (r) => r['following_id'].toString(),
    ).listen(
      (s) => following.value = s.docs.map((d) => d.id).toSet(),
      onError: (_) {},
    ));
    _subs.add(watchQuery(
      'admins',
      () => sb.from('admins').select().eq('user_id', uid),
      id: (r) => r['user_id'].toString(),
    ).listen(
      (s) => isAdmin.value = s.docs.isNotEmpty,
      onError: (_) => isAdmin.value = false,
    ));
    _loadMine(uid);
  }

  Future<void> _loadMine(String uid) async {
    try {
      final likes = await sb.from('likes').select('post_id,type').eq('user_id', uid);
      myLikes.value = {
        for (final r in likes) r['post_id'].toString(): (r['type'] ?? 'love') as String,
      };
      final votes = await sb.from('votes').select('post_id,option_index').eq('user_id', uid);
      myVotes.value = {
        for (final r in votes) r['post_id'].toString(): (r['option_index'] as num).toInt(),
      };
    } catch (_) {}
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    blocked.value = {};
    following.value = {};
    isAdmin.value = false;
    myLikes.value = {};
    Taste.clear();
    myVotes.value = {};
  }
}

class MediaException implements Exception {
  final String message;
  const MediaException(this.message);
  @override
  String toString() => message;
}

/// Un archivo elegido de la galería, todavía sin subir.
class PickedMedia {
  final XFile file;
  final bool isVideo;
  PickedMedia(this.file, this.isVideo);

  /// Foto ya editada (por ejemplo recortada) que está en memoria.
  factory PickedMedia.fromBytes(Uint8List data, String name) =>
      PickedMedia(XFile.fromData(data, name: name, mimeType: 'image/png'), false);

  String get path => file.path;

  /// Bytes del archivo (sirve en Android, iPhone y web). Se leen una sola vez.
  late final Future<Uint8List> bytes = file.readAsBytes();
}

/// Elegir fotos y videos de la galería del teléfono y subirlos a Cloudinary.
/// El selector del sistema se abre solo y no pide permisos peligrosos: la app
/// únicamente recibe el archivo que la persona elige.
class Media {
  Media._();
  static final ImagePicker _picker = ImagePicker();

  static const int _maxVideoBytes = 90 * 1024 * 1024;

  static Future<PickedMedia?> pickImage({
    double maxWidth = 1600,
    ImageSource source = ImageSource.gallery,
  }) async {
    final f = await _picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      imageQuality: 80,
    );
    return f == null ? null : PickedMedia(f, false);
  }

  static Future<PickedMedia?> pickVideo({
    ImageSource source = ImageSource.gallery,
  }) async {
    final f = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 3),
    );
    if (f == null) return null;
    final size = await f.length();
    if (size > _maxVideoBytes) {
      throw const MediaException(
        'El video pesa más de 90 MB. Elige uno más corto.',
      );
    }
    return PickedMedia(f, true);
  }

  /// Sube el archivo y devuelve su dirección https.
  static Future<String> upload(PickedMedia m) async {
    if (!MediaConfig.ready) {
      throw const MediaException(
        'Falta configurar Cloudinary en firebase_options.dart',
      );
    }
    final type = m.isVideo ? 'video' : 'image';
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${MediaConfig.cloudName}/$type/upload',
    );
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = MediaConfig.uploadPreset
      ..files.add(
        http.MultipartFile(
          'file',
          m.file.openRead(),
          await m.file.length(),
          filename: m.file.name,
        ),
      );

    final streamed = await req.send().timeout(const Duration(minutes: 6));
    final res = await http.Response.fromStream(streamed);

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode != 200) {
      final err = body['error'];
      final msg = err is Map ? err['message'] : null;
      throw MediaException(
        'No se pudo subir el archivo: ${msg ?? 'código ${res.statusCode}'}',
      );
    }
    // Si Cloudinary tiene activada la moderación con IA, rechaza lo indebido.
    final mod = body['moderation'];
    if (mod is List &&
        mod.any((e) => e is Map && e['status'] == 'rejected')) {
      throw const MediaException(
        'Este archivo fue rechazado automáticamente por contener contenido '
        'no permitido (sexual o violento).',
      );
    }
    final url = body['secure_url'];
    if (url is! String || url.isEmpty) {
      throw const MediaException('Respuesta inesperada al subir el archivo.');
    }
    return url;
  }
}


/// Gustos de cada persona: de qué autores y de qué temas reacciona, comenta o ve más.
/// Se guarda en la cuenta (tabla user_taste) para que valga en la web y en la app.
class Taste {
  static final Map<String, double> authors = {};
  static final Map<String, double> words = {};
  static final Map<String, List<String>> _seen = {};
  static Timer? _timer;

  static const _stop = {
    'este', 'esta', 'esto', 'esos', 'esas', 'para', 'pero', 'como', 'porque',
    'cuando', 'donde', 'todo', 'toda', 'todos', 'muy', 'mas', 'más', 'con',
    'sin', 'sobre', 'entre', 'desde', 'hasta', 'that', 'this', 'with', 'from',
    'have', 'what', 'your', 'they', 'will', 'about', 'ahora', 'hoy', 'jaja',
  };

  static List<String> _wordsOf(String text) {
    final out = <String>{};
    for (final w in text.toLowerCase().split(RegExp(r'[^a-záéíóúñü0-9]+'))) {
      if (w.length >= 4 && !_stop.contains(w)) out.add(w);
      if (out.length >= 8) break;
    }
    return out.toList();
  }

  static Future<void> load() async {
    authors.clear();
    words.clear();
    try {
      final row = await sb
          .from('user_taste')
          .select('data')
          .eq('user_id', myUid)
          .maybeSingle();
      final d = (row?['data'] ?? {}) as Map;
      ((d['a'] ?? {}) as Map).forEach((k, v) => authors['$k'] = (v as num).toDouble() * 0.95);
      ((d['w'] ?? {}) as Map).forEach((k, v) => words['$k'] = (v as num).toDouble() * 0.95);
    } catch (_) {}
  }

  static void clear() {
    authors.clear();
    words.clear();
    _seen.clear();
    _timer?.cancel();
  }

  /// Recuerda de quién y de qué trata una publicación vista.
  static void remember(String postId, Map<String, dynamic> d) {
    if (_seen.containsKey(postId)) return;
    if (_seen.length > 300) _seen.clear();
    _seen[postId] = ['${d['authorId']}', ..._wordsOf('${d['text'] ?? ''}')];
  }

  /// Suma (o resta) interés por una publicación: reacción +3, comentario +4, visita +1.
  static void bump(String postId, double w) {
    final s = _seen[postId];
    if (s == null) return;
    final a = s.first;
    if (a.isNotEmpty && a != myUid) authors[a] = (authors[a] ?? 0) + w;
    for (final k in s.skip(1)) {
      words[k] = (words[k] ?? 0) + w * 0.5;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 8), _save);
  }

  /// Cuánto le debería gustar esta publicación (0 si no hay datos).
  static double affinity(Map<String, dynamic> d) {
    final a = ((authors['${d['authorId']}'] ?? 0) * 0.25).clamp(0.0, 1.5);
    final ws = _wordsOf('${d['text'] ?? ''}')
        .map((k) => words[k] ?? 0.0)
        .where((v) => v > 0)
        .toList()
      ..sort((x, y) => y.compareTo(x));
    final w = (ws.take(3).fold<double>(0, (p, v) => p + v) * 0.1).clamp(0.0, 1.0);
    return a + w;
  }

  static Map<String, double> _top(Map<String, double> m, int n) {
    final e = m.entries.where((e) => e.value >= 0.3).toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return {for (final x in e.take(n)) x.key: double.parse(x.value.toStringAsFixed(2))};
  }

  static Future<void> _save() async {
    try {
      await sb.from('user_taste').upsert({
        'user_id': myUid,
        'data': {'a': _top(authors, 40), 'w': _top(words, 60)},
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {}
  }
}
