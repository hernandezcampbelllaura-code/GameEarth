import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';

/// Reacciones disponibles. 'love' es el corazón que se da con un toque.
const List<List<String>> kReactions = [
  ['love', '❤️', 'Me encanta'],
  ['like', '👍', 'Me gusta'],
  ['sad', '😢', 'Estoy triste'],
  ['angry', '😡', 'Estoy enojada'],
  ['wow', '😮', 'Estoy sorprendida'],
  ['confused', '😕', 'Confusión'],
];

String reactionEmoji(String type) {
  for (final r in kReactions) {
    if (r[0] == type) return r[1];
  }
  return '❤️';
}

String reactionName(String type) {
  for (final r in kReactions) {
    if (r[0] == type) return r[2];
  }
  return 'Me encanta';
}

/// Panel para elegir una reacción (se abre manteniendo apretado).
Future<String?> showReactionPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Reacciona',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 10,
              children: [
                for (final r in kReactions)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx, r[0]),
                    child: Container(
                      width: 92,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: current == r[0]
                            ? Theme.of(ctx).colorScheme.primary.withOpacity(0.25)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(r[1], style: const TextStyle(fontSize: 34)),
                          const SizedBox(height: 4),
                          Text(
                            r[2],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Escucha tu reacción a una publicación y da las acciones de toque
/// (corazón / quitar) y de mantener apretado (elegir otra reacción).
class ReactionBuilder extends StatelessWidget {
  final String postId;
  final Widget Function(
    BuildContext context,
    String? mine,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) builder;
  const ReactionBuilder({super.key, required this.postId, required this.builder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Db.posts.doc(postId).collection('likes').doc(myUid).snapshots(),
      builder: (context, snap) {
        final exists = snap.data?.exists ?? false;
        final String? mine =
            exists ? ((snap.data?.data()?['type'] ?? 'love') as String) : null;
        return builder(
          context,
          mine,
          // Un toque: corazón, o quitar la reacción que ya tenías.
          () => guard(context, () => Db.react(postId, mine ?? 'love')),
          () async {
            final t = await showReactionPicker(context, current: mine);
            if (t != null && context.mounted) {
              await guard(context, () => Db.react(postId, t));
            }
          },
        );
      },
    );
  }
}
