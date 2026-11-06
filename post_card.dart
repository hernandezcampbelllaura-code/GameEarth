import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';
import '../services/db.dart';
import '../util.dart';
import 'comments_sheet.dart';
import 'report_dialog.dart';
import 'user_avatar.dart';

class PostCard extends StatelessWidget {
  final DocumentSnapshot<Json> doc;
  const PostCard({super.key, required this.doc});

  Future<void> _menu(
    BuildContext context,
    String action,
    String authorId,
    String author,
    String text,
  ) async {
    switch (action) {
      case 'report':
        await showReportDialog(
          context,
          type: 'post',
          targetId: doc.id,
          ownerId: authorId,
          preview: text,
        );
        break;
      case 'block':
        {
          final ok = await confirmDialog(
            context,
            '¿Bloquear a @$author? No verás sus publicaciones ni comentarios.',
          );
          if (ok && context.mounted) {
            await guard(context, () async {
              await Db.block(authorId, author);
              if (context.mounted) toast(context, 'Bloqueaste a @$author');
            });
          }
          break;
        }
      case 'delete':
        {
          final ok = await confirmDialog(context, '¿Eliminar esta publicación?');
          if (ok && context.mounted) {
            await guard(context, () => Db.adminDeletePost(doc.id));
          }
          break;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() ?? <String, dynamic>{};
    final authorId = (d['authorId'] ?? '') as String;
    final author = (d['authorName'] ?? 'usuario') as String;
    final text = (d['text'] ?? '') as String;
    final img = (d['imageUrl'] ?? '') as String;
    final likes = ((d['likesCount'] ?? 0) as num).toInt();
    final comments = ((d['commentsCount'] ?? 0) as num).toInt();
    final mine = authorId == myUid;
    final canDelete = mine || Session.i.isAdmin.value;

    void openProfile() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(uid: authorId, isMe: mine),
          ),
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141A2B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: openProfile,
                borderRadius: BorderRadius.circular(24),
                child: Row(
                  children: [
                    UserAvatar(uid: authorId, radius: 18),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@$author',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatDate(d['createdAt']),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) => _menu(context, v, authorId, author, text),
                itemBuilder: (_) => [
                  if (!mine)
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Denunciar publicación'),
                    ),
                  if (!mine)
                    PopupMenuItem(
                      value: 'block',
                      child: Text('Bloquear a @$author'),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar'),
                    ),
                ],
              ),
            ],
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: Text(text, style: const TextStyle(fontSize: 15)),
            ),
          if (img.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  img,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (c, e, s) => const SizedBox.shrink(),
                ),
              ),
            ),
          Row(
            children: [
              StreamBuilder<DocumentSnapshot<Json>>(
                stream: doc.reference.collection('likes').doc(myUid).snapshots(),
                builder: (context, s) {
                  final liked = s.data?.exists ?? false;
                  return TextButton.icon(
                    onPressed: () => guard(
                      context,
                      () => Db.setLike(doc.id, !liked),
                    ),
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? Colors.pinkAccent : Colors.white70,
                    ),
                    label: Text(
                      '$likes',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                },
              ),
              TextButton.icon(
                onPressed: () => showCommentsSheet(context, doc.id),
                icon: const Icon(
                  Icons.mode_comment_outlined,
                  color: Colors.white70,
                ),
                label: Text(
                  '$comments',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
