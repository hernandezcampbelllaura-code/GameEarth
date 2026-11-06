import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

/// Panel de administración. Solo se muestra si existe el documento
/// admins/<tu uid>, y además las reglas de Firestore lo exigen en el servidor.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final Stream<QuerySnapshot<Json>> _users =
      Db.users.orderBy('createdAt', descending: true).limit(200).snapshots();
  late final Stream<QuerySnapshot<Json>> _posts =
      Db.posts.orderBy('createdAt', descending: true).limit(100).snapshots();
  late final Stream<QuerySnapshot<Json>> _reports =
      Db.reports.orderBy('createdAt', descending: true).limit(100).snapshots();

  void _openProfile(String uid) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(uid: uid, isMe: uid == myUid),
      ),
    );
  }

  Future<void> _ban(String uid, bool banned, String name) async {
    if (uid == myUid) {
      toast(context, 'No puedes banearte a ti mismo.');
      return;
    }
    final ok = await confirmDialog(
      context,
      banned
          ? '¿Banear a @$name? No podrá publicar y verá una pantalla de cuenta suspendida.'
          : '¿Reactivar la cuenta de @$name?',
    );
    if (ok && mounted) await guard(context, () => Db.setBanned(uid, banned));
  }

  Widget _chip(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _states(AsyncSnapshot<QuerySnapshot<Json>> snap) {
    if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
    return const Center(child: CircularProgressIndicator());
  }

  // ---------------- Usuarios ----------------

  Future<void> _userAction(String v, QueryDocumentSnapshot<Json> d) async {
    final u = d.data();
    final name = (u['username'] ?? '') as String;
    final banned = u['banned'] == true;
    switch (v) {
      case 'view':
        _openProfile(d.id);
        break;
      case 'ban':
        await _ban(d.id, !banned, name);
        break;
      case 'delete':
        final ok = await confirmDialog(
          context,
          '¿Eliminar a @$name? Se borrarán todas sus publicaciones y no podrá volver a usar la app.',
        );
        if (ok && mounted) {
          await guard(
            context,
            () => Db.adminDeleteUser(d.id, (u['usernameLower'] ?? '') as String),
          );
        }
        break;
    }
  }

  Widget _usersTab() {
    return StreamBuilder<QuerySnapshot<Json>>(
      stream: _users,
      builder: (context, snap) {
        if (!snap.hasData) return _states(snap);
        final docs = snap.data!.docs;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${docs.length} usuarios registrados',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final u = d.data();
                  final name = (u['username'] ?? '') as String;
                  final banned = u['banned'] == true;
                  final deleted = u['deleted'] == true;
                  final self = d.id == myUid;
                  return ListTile(
                    isThreeLine: true,
                    leading: UserAvatar(uid: d.id),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text('@$name', overflow: TextOverflow.ellipsis),
                        ),
                        if (self) _chip('TÚ', Colors.tealAccent),
                        if (banned && !deleted) _chip('BANEADO', Colors.orange),
                        if (deleted) _chip('ELIMINADO', Colors.redAccent),
                      ],
                    ),
                    subtitle: Text(
                      '${u['email'] ?? ''}\nRegistro: ${formatFullDate(u['createdAt'])}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _userAction(v, d),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('Ver perfil'),
                        ),
                        if (!self && !deleted)
                          PopupMenuItem(
                            value: 'ban',
                            child: Text(
                              banned ? 'Reactivar cuenta' : 'Banear cuenta',
                            ),
                          ),
                        if (!self && !deleted)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar cuenta y publicaciones'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- Publicaciones ----------------

  Future<void> _postAction(String v, QueryDocumentSnapshot<Json> d) async {
    final p = d.data();
    final authorId = (p['authorId'] ?? '') as String;
    final author = (p['authorName'] ?? '') as String;
    if (v == 'delete') {
      final ok = await confirmDialog(context, '¿Eliminar esta publicación?');
      if (ok && mounted) await guard(context, () => Db.adminDeletePost(d.id));
    } else if (v == 'ban') {
      await _ban(authorId, true, author);
    } else if (v == 'view') {
      _openProfile(authorId);
    }
  }

  Widget _postsTab() {
    return StreamBuilder<QuerySnapshot<Json>>(
      stream: _posts,
      builder: (context, snap) {
        if (!snap.hasData) return _states(snap);
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No hay publicaciones.'));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i];
            final p = d.data();
            return ListTile(
              isThreeLine: true,
              title: Text(
                '@${p['authorName'] ?? ''} · ${formatDate(p['createdAt'])}',
              ),
              subtitle: Text(
                (p['text'] ?? '') as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _postAction(v, d),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'view', child: Text('Ver perfil del autor')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar publicación')),
                  PopupMenuItem(value: 'ban', child: Text('Banear al autor')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------- Reportes ----------------

  Future<void> _reportAction(String v, QueryDocumentSnapshot<Json> d) async {
    final r = d.data();
    final type = (r['type'] ?? '') as String;
    final target = (r['targetId'] ?? '') as String;
    final owner = (r['ownerId'] ?? '') as String;
    final postId = (r['postId'] ?? '') as String;
    switch (v) {
      case 'view':
        _openProfile(owner);
        break;
      case 'content':
        final ok = await confirmDialog(
          context,
          '¿Eliminar el contenido denunciado?',
        );
        if (ok && mounted) {
          await guard(context, () async {
            if (type == 'post') {
              await Db.adminDeletePost(target);
            } else if (type == 'comment') {
              await Db.deleteComment(postId, target);
            }
            await Db.dismissReport(d.id);
          });
        }
        break;
      case 'ban':
        await _ban(owner, true, (r['preview'] ?? 'usuario') as String);
        break;
      case 'dismiss':
        await guard(context, () => Db.dismissReport(d.id));
        break;
    }
  }

  Widget _reportsTab() {
    return StreamBuilder<QuerySnapshot<Json>>(
      stream: _reports,
      builder: (context, snap) {
        if (!snap.hasData) return _states(snap);
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No hay denuncias pendientes. 🎉'));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i];
            final r = d.data();
            final type = (r['type'] ?? '') as String;
            final preview = (r['preview'] ?? '') as String;
            final label = type == 'post'
                ? 'Publicación'
                : type == 'comment'
                    ? 'Comentario'
                    : 'Usuario';
            return ListTile(
              isThreeLine: true,
              leading: Icon(
                type == 'user' ? Icons.person_off : Icons.flag,
                color: Colors.orangeAccent,
              ),
              title: Text('$label · ${r['reason'] ?? ''}'),
              subtitle: Text(
                'Por @${r['reporterName'] ?? ''} · ${formatDate(r['createdAt'])}'
                '${preview.isEmpty ? '' : '\n"$preview"'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _reportAction(v, d),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'view', child: Text('Ver perfil')),
                  if (type != 'user')
                    const PopupMenuItem(
                      value: 'content',
                      child: Text('Eliminar contenido'),
                    ),
                  const PopupMenuItem(value: 'ban', child: Text('Banear usuario')),
                  const PopupMenuItem(value: 'dismiss', child: Text('Descartar')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.shield, size: 20),
              SizedBox(width: 8),
              Text('Panel de admin'),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Usuarios'),
              Tab(text: 'Publicaciones'),
              Tab(text: 'Denuncias'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_usersTab(), _postsTab(), _reportsTab()],
        ),
      ),
    );
  }
}
