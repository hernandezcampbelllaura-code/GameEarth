import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../net.dart';
import '../safety.dart';
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
  String _replyParent = '';
  String _replyName = '';

  late final Stream<Snap> _stream = Db.watchComments(widget.postId);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (!await requireOnline(context, 'comentar')) return;
    if (!mounted || !Safety.check(context, [t])) return;
    final w = RateLimit.wait('comment', 6);
    if (w > 0) {
      toast(context, 'Espera $w s antes de comentar otra vez.');
      return;
    }
    setState(() => _sending = true);
    try {
      await Db.addComment(
        widget.postId,
        t,
        parentId: _replyParent,
        replyToName: _replyName,
      );
      _ctrl.clear();
      if (mounted) {
        setState(() {
          _replyParent = '';
          _replyName = '';
        });
      }
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
              child: StreamBuilder<Snap>(
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
                      final all = snap.data!.docs
                          .where((d) => !blocked.contains(d.data()['authorId']))
                          .toList();
                      if (all.isEmpty) {
                        return const Center(
                          child: Text('Sé el primero en comentar.'),
                        );
                      }
                      final docs = threadComments(all);
                      String parentOf(Doc d) =>
                          ((d.data()['parentId'] ?? '') as String);
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d = docs[i].key;
                          final isReply = docs[i].value;
                          final c = d.data();
                          final authorId = (c['authorId'] ?? '') as String;
                          final text = (c['text'] ?? '') as String;
                          final mine = authorId == myUid;
                          final canDelete = mine || Session.i.isAdmin.value;
                          final replyTo = (c['replyToName'] ?? '') as String;
                          return Padding(
                            padding: EdgeInsets.only(left: isReply ? 40 : 0),
                            child: ListTile(
                              leading: UserAvatar(
                                uid: authorId,
                                radius: isReply ? 13 : 16,
                              ),
                              title: Text(
                                '@${c['authorName'] ?? 'usuario'} · ${formatDate(c['createdAt'])}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        if (isReply && replyTo.isNotEmpty)
                                          TextSpan(
                                            text: '@$replyTo ',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        TextSpan(text: text),
                                      ],
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      _replyParent =
                                          isReply ? parentOf(d) : d.id;
                                      _replyName =
                                          (c['authorName'] ?? '') as String;
                                    }),
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Responder',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) =>
                                    _menu(v, d.id, authorId, text),
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
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            if (_replyName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Respondiendo a @$_replyName',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _replyParent = '';
                        _replyName = '';
                      }),
                    ),
                  ],
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
                        decoration: InputDecoration(
                          hintText: _replyName.isEmpty
                              ? 'Escribe un comentario…'
                              : 'Escribe tu respuesta…',
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
