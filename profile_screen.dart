import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';
import '../widgets/post_card.dart';
import '../widgets/report_dialog.dart';
import '../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  final String uid;
  final bool isMe;
  const ProfileScreen({super.key, required this.uid, required this.isMe});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Stream<DocumentSnapshot<Json>> _user =
      Db.users.doc(widget.uid).snapshots();
  late final Stream<int> _followers = Db.users
      .doc(widget.uid)
      .collection('followers')
      .snapshots()
      .map((s) => s.size);
  late final Stream<int> _followingCount = Db.users
      .doc(widget.uid)
      .collection('following')
      .snapshots()
      .map((s) => s.size);
  late final Stream<QuerySnapshot<Json>> _posts =
      Db.posts.where('authorId', isEqualTo: widget.uid).snapshots();
  late final Stream<int> _postCount = Db.posts
      .where('authorId', isEqualTo: widget.uid)
      .snapshots()
      .map((s) => s.size);

  Future<void> _logout() async {
    final ok = await confirmDialog(context, '¿Cerrar sesión?');
    if (ok) await FirebaseAuth.instance.signOut();
  }

  Future<void> _edit(Json u) async {
    final bio = TextEditingController(text: (u['bio'] ?? '') as String);
    final photo = TextEditingController(text: (u['photoUrl'] ?? '') as String);
    final games = TextEditingController(
      text: ((u['favoriteGames'] as List?) ?? const []).join(', '),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar perfil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bio,
                maxLength: 160,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Bio'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: photo,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Enlace de foto de perfil',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: games,
                decoration: const InputDecoration(
                  labelText: 'Juegos favoritos (separados por coma)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final photoUrl = photo.text.trim();
    if (photoUrl.isNotEmpty && !photoUrl.startsWith('http')) {
      toast(context, 'El enlace de la foto debe empezar con http');
      return;
    }
    final list = games.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(10)
        .toList();
    await guard(
      context,
      () => Db.updateProfile(
        bio: bio.text.trim(),
        photoUrl: photoUrl,
        favoriteGames: list,
      ),
    );
  }

  Future<void> _other(String action, String name) async {
    if (action == 'report') {
      await showReportDialog(
        context,
        type: 'user',
        targetId: widget.uid,
        ownerId: widget.uid,
        preview: '@$name',
      );
    } else if (action == 'block') {
      final ok = await confirmDialog(
        context,
        '¿Bloquear a @$name? No verás sus publicaciones ni comentarios.',
      );
      if (ok && mounted) await guard(context, () => Db.block(widget.uid, name));
    } else if (action == 'unblock') {
      await guard(context, () => Db.unblock(widget.uid));
    }
  }

  Widget _stat(String label, Stream<int> stream) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, s) => Column(
        children: [
          Text(
            '${s.data ?? 0}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  int _millis(dynamic ts) => ts is Timestamp
      ? ts.millisecondsSinceEpoch
      : DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isMe ? 'Mi perfil' : 'Perfil'),
        actions: [
          if (widget.isMe)
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Json>>(
        stream: _user,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final u = snap.data!.data();
          if (u == null || u['deleted'] == true) {
            return const Center(child: Text('Este usuario no existe.'));
          }
          final name = (u['username'] ?? '') as String;
          final bio = (u['bio'] ?? '') as String;
          final games = ((u['favoriteGames'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();

          return ValueListenableBuilder<Set<String>>(
            valueListenable: Session.i.blocked,
            builder: (context, blocked, _) {
              final isBlocked = blocked.contains(widget.uid);
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        UserAvatar(uid: widget.uid, radius: 44),
                        const SizedBox(height: 10),
                        Text(
                          '@$name',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (bio.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(bio, textAlign: TextAlign.center),
                          ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _stat('Publicaciones', _postCount),
                            _stat('Seguidores', _followers),
                            _stat('Siguiendo', _followingCount),
                          ],
                        ),
                        if (games.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final g in games)
                                Chip(
                                  avatar: const Icon(
                                    Icons.sports_esports,
                                    size: 16,
                                  ),
                                  label: Text(g),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (widget.isMe)
                          OutlinedButton.icon(
                            onPressed: () => _edit(u),
                            icon: const Icon(Icons.edit),
                            label: const Text('Editar perfil'),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!isBlocked)
                                ValueListenableBuilder<Set<String>>(
                                  valueListenable: Session.i.following,
                                  builder: (context, following, _) {
                                    final f = following.contains(widget.uid);
                                    final label = Text(f ? 'Siguiendo' : 'Seguir');
                                    void onTap() => guard(
                                          context,
                                          () => f
                                              ? Db.unfollow(widget.uid)
                                              : Db.follow(widget.uid),
                                        );
                                    return f
                                        ? FilledButton.tonal(
                                            onPressed: onTap,
                                            child: label,
                                          )
                                        : FilledButton(
                                            onPressed: onTap,
                                            child: label,
                                          );
                                  },
                                ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_horiz),
                                onSelected: (v) => _other(v, name),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'report',
                                    child: Text('Denunciar usuario'),
                                  ),
                                  PopupMenuItem(
                                    value: isBlocked ? 'unblock' : 'block',
                                    child: Text(
                                      isBlocked ? 'Desbloquear' : 'Bloquear',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (isBlocked)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Bloqueaste a este usuario. Desbloquéalo para ver sus publicaciones.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    StreamBuilder<QuerySnapshot<Json>>(
                      stream: _posts,
                      builder: (context, ps) {
                        if (ps.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Error: ${ps.error}'),
                          );
                        }
                        if (!ps.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final docs = [...ps.data!.docs]..sort(
                            (a, b) => _millis(b.data()['createdAt'])
                                .compareTo(_millis(a.data()['createdAt'])),
                          );
                        if (docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('Sin publicaciones aún.')),
                          );
                        }
                        return Column(
                          children: [
                            const SizedBox(height: 6),
                            for (final d in docs)
                              PostCard(key: ValueKey(d.id), doc: d),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
