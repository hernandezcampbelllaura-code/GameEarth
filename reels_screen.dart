import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/db.dart';
import '../util.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

/// Reels: los videos de la comunidad, uno por pantalla. Desliza hacia arriba.
class ReelsScreen extends StatefulWidget {
  /// Solo reproduce cuando esta pestaña está a la vista.
  final bool active;
  const ReelsScreen({super.key, required this.active});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late final Stream<QuerySnapshot<Json>> _stream =
      Db.posts.orderBy('createdAt', descending: true).limit(100).snapshots();
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<QuerySnapshot<Json>>(
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
              final reels = snap.data!.docs.where((d) {
                final m = d.data();
                return ((m['videoUrl'] ?? '') as String).isNotEmpty &&
                    ((m['groupId'] ?? '') as String).isEmpty &&
                    !blocked.contains(m['authorId']);
              }).toList();
              if (reels.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aún no hay reels.\nSube un video desde "Crear" y aparecerá aquí.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: reels.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _ReelPage(
                  key: ValueKey(reels[i].id),
                  doc: reels[i],
                  active: widget.active && i == _page,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final DocumentSnapshot<Json> doc;
  final bool active;
  const _ReelPage({super.key, required this.doc, required this.active});

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      if (_c == null) {
        _start();
      } else {
        _c!.play();
      }
    } else {
      _c?.pause();
      _c?.seekTo(Duration.zero);
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    final url = (widget.doc.data()?['videoUrl'] ?? '') as String;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      if (widget.active) await c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _starting = false;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() ?? <String, dynamic>{};
    final authorId = (d['authorId'] ?? '') as String;
    final author = (d['authorName'] ?? 'usuario') as String;
    final text = (d['text'] ?? '') as String;
    final video = (d['videoUrl'] ?? '') as String;
    final link = (d['linkUrl'] ?? '') as String;
    final likes = ((d['likesCount'] ?? 0) as num).toInt();
    final comments = ((d['commentsCount'] ?? 0) as num).toInt();
    final c = _c;
    final rc = (c != null && c.value.isInitialized) ? c : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            if (rc == null) return;
            if (rc.value.isPlaying) {
              rc.pause();
            } else {
              rc.play();
            }
            setState(() {});
          },
          child: ColoredBox(
            color: Colors.black,
            child: rc != null
                ? Center(
                    child: AspectRatio(
                      aspectRatio: rc.value.aspectRatio,
                      child: VideoPlayer(rc),
                    ),
                  )
                : Center(
                    child: _failed
                        ? const Text('No se pudo reproducir el video')
                        : const CircularProgressIndicator(),
                  ),
          ),
        ),
        if (rc != null && !rc.value.isPlaying)
          const IgnorePointer(
            child: Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 72,
                color: Colors.white70,
              ),
            ),
          ),
        // Texto abajo a la izquierda
        Positioned(
          left: 14,
          right: 80,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      uid: authorId,
                      isMe: authorId == myUid,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UserAvatar(uid: authorId, radius: 16),
                    const SizedBox(width: 8),
                    Text(
                      '@$author',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                    ),
                  ],
                ),
              ),
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(shadows: [Shadow(blurRadius: 6)]),
                  ),
                ),
              if (link.isNotEmpty)
                TextButton.icon(
                  onPressed: () => openLink(context, link),
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        // Botones a la derecha
        Positioned(
          right: 6,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<DocumentSnapshot<Json>>(
                stream: widget.doc.reference
                    .collection('likes')
                    .doc(myUid)
                    .snapshots(),
                builder: (context, s) {
                  final liked = s.data?.exists ?? false;
                  return _Action(
                    icon: liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Colors.pinkAccent : Colors.white,
                    label: '$likes',
                    onTap: () => guard(
                      context,
                      () => Db.setLike(widget.doc.id, !liked),
                    ),
                  );
                },
              ),
              _Action(
                icon: Icons.mode_comment_outlined,
                label: '$comments',
                onTap: () => showCommentsSheet(context, widget.doc.id),
              ),
              _Action(
                icon: Icons.share_outlined,
                label: 'Compartir',
                onTap: () => sharePost(
                  author: author,
                  text: text,
                  videoUrl: video,
                  linkUrl: link,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
