import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../screens/profile_screen.dart';
import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import '../util.dart';
import 'comments_sheet.dart';
import 'poll_block.dart';
import 'reactions.dart';
import 'report_dialog.dart';
import 'user_avatar.dart';

class PostCard extends StatelessWidget {
  final Doc doc;
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
      case 'edit':
        await _editDialog(context);
        break;
      case 'leavecollab':
        await guard(context, () => Db.leaveCollab(doc.id));
        break;
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

  Future<void> _editDialog(BuildContext context) async {
    final d = doc.data() ?? <String, dynamic>{};
    final text = TextEditingController(text: (d['text'] ?? '') as String);
    final desc = TextEditingController(text: (d['description'] ?? '') as String);
    final link = TextEditingController(text: (d['linkUrl'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar publicación'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                maxLength: 500,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Texto'),
              ),
              TextField(
                controller: desc,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              TextField(
                controller: link,
                decoration: const InputDecoration(labelText: 'Enlace (opcional)'),
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
    if (ok != true || !context.mounted) return;
    final t = text.text.trim();
    if (t.isEmpty) {
      toast(context, 'El texto no puede quedar vacío.');
      return;
    }
    final rawLink = link.text.trim();
    final cl = cleanUrl(rawLink);
    if (rawLink.isNotEmpty && cl.isEmpty) {
      toast(context, 'El enlace no es válido.');
      return;
    }
    if (!await requireOnline(context, 'guardar los cambios')) return;
    if (!context.mounted || !Safety.check(context, [t, desc.text, rawLink])) {
      return;
    }
    await guard(context, () async {
      await Db.editPost(doc.id, t, desc.text.trim(), cl);
      if (context.mounted) toast(context, 'Cambios guardados');
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() ?? <String, dynamic>{};
    final authorId = (d['authorId'] ?? '') as String;
    final author = (d['authorName'] ?? 'usuario') as String;
    final text = (d['text'] ?? '') as String;
    final img = (d['imageUrl'] ?? '') as String;
    final video = (d['videoUrl'] ?? '') as String;
    final link = (d['linkUrl'] ?? '') as String;
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '@$author',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            VerifiedBadge(uid: authorId),
                            if (((d['collabName'] ?? '') as String).isNotEmpty)
                              Text(
                                '  con @${d['collabName']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.lightBlueAccent,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          d['editedAt'] != null
                              ? '${formatDate(d['createdAt'])} · editado'
                              : formatDate(d['createdAt']),
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
              FollowChip(uid: authorId),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) => _menu(context, v, authorId, author, text),
                itemBuilder: (_) => [
                  if (mine)
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  if (d['collabId'] == myUid)
                    const PopupMenuItem(
                      value: 'leavecollab',
                      child: Text('Quitarme como colaborador'),
                    ),
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
                  cacheWidth: 900,
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
          PollBlock(doc: doc),
          if (link.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: InkWell(
                onTap: () => openLink(context, link),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (likes > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: ReactionSummary(counts: d['reactionCounts']),
            ),
          Row(
            children: [
              ReactionBuilder(
                postId: doc.id,
                builder: (context, mine, onTap, onLongPress) => InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        mine == null
                            ? const Icon(
                                Icons.favorite_border,
                                color: Colors.white70,
                              )
                            : Text(
                                reactionEmoji(mine),
                                style: const TextStyle(fontSize: 20),
                              ),
                        const SizedBox(width: 6),
                        Text(
                          '$likes',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
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
              TextButton.icon(
                onPressed: () => sharePost(postId: doc.id),
                icon: const Icon(Icons.share_outlined, color: Colors.white70),
                label: const Text(
                  'Compartir',
                  style: TextStyle(color: Colors.white70),
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
