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
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: Session.i.myLikes,
      builder: (context, likes, _) {
        final String? mine = likes[postId];
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

/// Reacciones con al menos una persona, de la más usada a la menos usada.
List<MapEntry<String, int>> sortedReactions(dynamic counts) {
  if (counts is! Map) return [];
  final out = <MapEntry<String, int>>[];
  for (final r in kReactions) {
    final n = counts[r[0]];
    if (n is num && n > 0) out.add(MapEntry(r[0], n.toInt()));
  }
  out.sort((a, b) => b.value.compareTo(a.value));
  return out;
}

/// Fila con la cantidad de cada reacción: ❤️ 3  👍 2  😮 1
class ReactionSummary extends StatelessWidget {
  final dynamic counts;

  /// Si se indica, al tocar se ve quién reaccionó con cada reacción.
  final String? postId;
  const ReactionSummary({super.key, required this.counts, this.postId});

  @override
  Widget build(BuildContext context) {
    final list = sortedReactions(counts);
    if (list.isEmpty) return const SizedBox.shrink();
    final w = Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (final e in list)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reactionEmoji(e.key), style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 3),
              Text(
                '${e.value}',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
      ],
    );
    final id = postId;
    if (id == null) return w;
    return InkWell(
      onTap: () => showReactionsSheet(context, id),
      child: w,
    );
  }
}

/// Lista de personas que reaccionaron, con una pestaña por reacción.
Future<void> showReactionsSheet(BuildContext context, String postId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.6,
      child: FutureBuilder<List<Map<String, String>>>(
        future: Db.reactionUsers(postId),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(child: Text('No se pudo cargar: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          if (all.isEmpty) {
            return const Center(child: Text('Aún no hay reacciones.'));
          }
          final types = [
            for (final r in kReactions)
              if (all.any((e) => e['type'] == r[0])) r[0],
          ];
          return DefaultTabController(
            length: types.length + 1,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Todas ${all.length}'),
                    for (final t in types)
                      Tab(
                        text:
                            '${reactionEmoji(t)} ${all.where((e) => e['type'] == t).length}',
                      ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final t in [null, ...types])
                        ListView(
                          children: [
                            for (final e in all.where((e) => t == null || e['type'] == t))
                              ListTile(
                                dense: true,
                                leading: Text(
                                  reactionEmoji(e['type']!),
                                  style: const TextStyle(fontSize: 22),
                                ),
                                title: Text('@${e['name']}'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
