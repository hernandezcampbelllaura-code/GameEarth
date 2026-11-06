import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';
import 'report_dialog.dart';
import 'user_avatar.dart';

Future<void> showCommentsSheet(BuildContext context, String postId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CommentsSheet(postId: postId),
  );
}

class _CommentsSheet extends StatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  late final Stream<QuerySnapshot<Json>> _stream = Db.posts
      .doc(widget.postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Db.addComment(widget.postId, t);
      _ctrl.clear();
    } catch (e) {
      if (mounted) toast(context, 'No se pudo comentar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _menu(
    String action,
    String commentId,
    String authorId,
    String text,
  ) async {
    if (action == 'report') {
      await showReportDialog(
        context,
        type: 'comment',
        targetId: commentId,
        ownerId: authorId,
        postId: widget.postId,
        preview: text,
      );
    } else if (action == 'delete') {
      final ok = await confirmDialog(context, '¿Eliminar este comentario?');
      if (ok && mounted) {
        await guard(context, () => Db.deleteComment(widget.postId, commentId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const Text(
              'Comentarios',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Json>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ValueListenableBuilder<Set<String>>(
                    valueListenable: Session.i.blocked,
                    builder: (context, blocked, _) {
                      final docs = snap.data!.docs
                          .where((d) => !blocked.contains(d.data()['authorId']))
                          .toList();
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('Sé el primero en comentar.'),
                        );
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d = docs[i];
                          final c = d.data();
                          final authorId = (c['authorId'] ?? '') as String;
                          final text = (c['text'] ?? '') as String;
                          final mine = authorId == myUid;
                          final canDelete = mine || Session.i.isAdmin.value;
                          return ListTile(
                            leading: UserAvatar(uid: authorId, radius: 16),
                            title: Text(
                              '@${c['authorName'] ?? 'usuario'} · ${formatDate(c['createdAt'])}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                            subtitle: Text(
                              text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) => _menu(v, d.id, authorId, text),
                              itemBuilder: (_) => [
                                if (!mine)
                                  const PopupMenuItem(
                                    value: 'report',
                                    child: Text('Denunciar'),
                                  ),
                                if (canDelete)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Eliminar'),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        maxLength: 300,
                        maxLines: 1,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Escribe un comentario…',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
