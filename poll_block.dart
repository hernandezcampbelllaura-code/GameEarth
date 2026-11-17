import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';

/// Votación dentro de una publicación: botones para votar y, después de votar
/// (o si eres el autor), barras con el porcentaje de cada opción.
class PollBlock extends StatelessWidget {
  final DocumentSnapshot<Json> doc;
  const PollBlock({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() ?? <String, dynamic>{};
    final options =
        ((d['pollOptions'] as List?) ?? const []).map((e) => '$e').toList();
    if (options.isEmpty) return const SizedBox.shrink();

    final counts = (d['pollCounts'] as Map?) ?? const {};
    int count(int i) => ((counts['$i'] ?? 0) as num).toInt();
    final total = [for (var i = 0; i < options.length; i++) count(i)]
        .fold<int>(0, (a, b) => a + b);
    final isAuthor = d['authorId'] == myUid;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 6),
      child: StreamBuilder<DocumentSnapshot<Json>>(
        stream: doc.reference.collection('votes').doc(myUid).snapshots(),
        builder: (context, snap) {
          final voted = snap.data?.exists ?? false;
          final mine = voted ? (snap.data?.data()?['option'] as num?)?.toInt() : null;
          final showResults = voted || isAuthor;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: showResults
                      ? _ResultBar(
                          label: options[i],
                          percent: total == 0 ? 0 : count(i) * 100 / total,
                          mine: mine == i,
                          color: primary,
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => guard(
                              context,
                              () => Db.vote(doc.id, i),
                            ),
                            child: Text(options[i]),
                          ),
                        ),
                ),
              Text(
                '$total ${total == 1 ? 'voto' : 'votos'}'
                '${showResults || voted ? '' : ' · Vota para ver los resultados'}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  final String label;
  final double percent;
  final bool mine;
  final Color color;
  const _ResultBar({
    required this.label,
    required this.percent,
    required this.mine,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            height: 42,
            color: Colors.white10,
          ),
          FractionallySizedBox(
            widthFactor: (percent / 100).clamp(0.0, 1.0),
            child: Container(height: 42, color: color.withOpacity(0.45)),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (mine)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle, size: 18),
                    ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: mine ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    '${percent.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
