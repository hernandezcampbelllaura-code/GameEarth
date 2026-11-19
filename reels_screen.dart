import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/db.dart';
import '../util.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/reactions.dart';
import '../widgets/report_dialog.dart';
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
  late final Stream<Snap> _stream =
      Db.watchPosts();
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<Snap>(
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
  final Doc doc;
  final bool active;
  const _ReelPage({super.key, required this.doc, required this.active});

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _starting = false;
  Timer? _viewTimer;

  /// Cuenta una visita si el reel se queda en pantalla un par de segundos.
  void _watchForView() {
    _viewTimer?.cancel();
    final id = widget.doc.id;
    final author = (widget.doc.data()?['authorId'] ?? '') as String;
    _viewTimer = Timer(
      const Duration(seconds: 2),
      () => Db.registerView(id, author),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _watchForView();
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _watchForView();
      if (_c == null) {
        _start();
      } else {
        _c!.play();
      }
    } else {
      _viewTimer?.cancel();
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
    _viewTimer?.cancel();
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
        // Tres puntitos arriba a la derecha
        Positioned(
          top: MediaQuery.of(context).padding.top + 6,
          right: 6,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) {
                if (v == 'info') {
                  _showInfo(context, widget.doc);
                } else if (v == 'report') {
                  showReportDialog(
                    context,
                    type: 'post',
                    targetId: widget.doc.id,
                    ownerId: authorId,
                    preview: text,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'info', child: Text('Ver información')),
                PopupMenuItem(value: 'report', child: Text('Denunciar')),
              ],
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
              ReactionBuilder(
                postId: widget.doc.id,
                builder: (context, mine, onTap, onLongPress) => _Action(
                  icon: Icons.favorite_border,
                  emoji: mine == null ? null : reactionEmoji(mine),
                  label: '$likes',
                  onTap: onTap,
                  onLongPress: onLongPress,
                ),
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
  final String? emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emoji,
    this.onLongPress,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              emoji != null
                  ? Text(emoji!, style: const TextStyle(fontSize: 30))
                  : Icon(icon, size: 32, color: color),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateTime(dynamic ts) {
  if (ts is! DateTime) return '-';
  final d = ts;
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '${formatFullDate(ts)}  $hh:$mi';
}

/// Información del reel: descripción, fecha, visitas, me gusta y reacciones.
Future<void> _showInfo(BuildContext context, Doc doc) {
  final d = doc.data() ?? <String, dynamic>{};
  final desc = ((d['description'] ?? '') as String).trim();
  final text = ((d['text'] ?? '') as String).trim();
  final views = ((d['views'] ?? 0) as num).toInt();
  final likes = ((d['likesCount'] ?? 0) as num).toInt();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Información del reel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            const Text('Descripción', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 4),
            Text(desc.isNotEmpty ? desc : (text.isNotEmpty ? text : 'Sin descripción')),
            const SizedBox(height: 16),
            _InfoRow(Icons.event, 'Fecha', _dateTime(d['createdAt'])),
            _InfoRow(Icons.visibility_outlined, 'Visitas', '$views'),
            _InfoRow(Icons.favorite_border, 'Me gusta y reacciones', '$likes'),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, int>>(
              future: Db.reactionCounts(doc.id),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  );
                }
                final m = snap.data!;
                if (m.isEmpty) {
                  return const Text(
                    'Aún no hay reacciones.',
                    style: TextStyle(color: Colors.white60),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in kReactions)
                      if ((m[r[0]] ?? 0) > 0)
                        Chip(label: Text('${r[1]}  ${m[r[0]]}')),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
