import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
    final video = (d['videoUrl'] ?? '') as String;
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
          if (video.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _VideoBox(url: video),
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

/// Video dentro de la publicación. No descarga nada hasta que se toca play,
/// así no se gastan datos al hacer scroll por el feed.
class _VideoBox extends StatefulWidget {
  final String url;
  const _VideoBox({required this.url});

  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  VideoPlayerController? _c;
  bool _loading = false;

  // Cloudinary genera la miniatura del primer cuadro cambiando la dirección.
  String get _poster => widget.url
      .replaceFirst('/upload/', '/upload/so_0,w_900,c_limit/')
      .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.jpg');

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (_) {
      if (mounted) toast(context, 'No se pudo reproducir el video');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c != null && c.value.isInitialized) {
      return GestureDetector(
        onTap: () => setState(() {
          if (c.value.isPlaying) {
            c.pause();
          } else {
            c.play();
          }
        }),
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              if (!c.value.isPlaying)
                const Icon(
                  Icons.play_circle_fill,
                  size: 64,
                  color: Colors.white70,
                ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _loading ? null : _start,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _poster,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(color: Colors.black),
            ),
            Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Icon(
                      Icons.play_circle_fill,
                      size: 64,
                      color: Colors.white70,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
