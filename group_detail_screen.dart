import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../services/db.dart';
import '../util.dart';
import '../widgets/post_card.dart';
import 'create_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late final Stream<Doc> _group = Db.watchGroup(widget.groupId);
  late final Stream<Doc> _member = Db.watchMembership(widget.groupId);
  late final Stream<Snap> _posts = Db.watchPosts(groupId: widget.groupId);

  int _millis(dynamic ts) => ts is DateTime
      ? ts.millisecondsSinceEpoch
      : DateTime.now().millisecondsSinceEpoch;

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      '¿Eliminar el grupo y todas sus publicaciones?',
    );
    if (!ok || !mounted) return;
    await guard(context, () async {
      await Db.deleteGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Doc>(
      stream: _group,
      builder: (context, gs) {
        if (gs.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: ${gs.error}')),
          );
        }
        if (!gs.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final g = gs.data!.data();
        if (g == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Este grupo ya no existe.')),
          );
        }
        final name = (g['name'] ?? '') as String;
        final desc = (g['description'] ?? '') as String;
        final ownerId = (g['ownerId'] ?? '') as String;
        final ownerName = (g['ownerName'] ?? '') as String;
        final n = ((g['membersCount'] ?? 0) as num).toInt();
        final isOwner = ownerId == myUid;
        final canDelete = isOwner || Session.i.isAdmin.value;

        return StreamBuilder<Doc>(
          stream: _member,
          builder: (context, ms) {
            final joined = ms.data?.exists ?? false;
            return Scaffold(
              appBar: AppBar(
                title: Text(name),
                actions: [
                  if (canDelete)
                    IconButton(
                      tooltip: tr('Eliminar grupo'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _delete,
                    ),
                ],
              ),
              floatingActionButton: joined
                  ? FloatingActionButton.extended(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => CreateScreen(
                            groupId: widget.groupId,
                            onDone: (_, __) => Navigator.pop(ctx),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text('Publicar'),
                    )
                  : null,
              body: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (desc.isNotEmpty) Text(desc),
                        const SizedBox(height: 8),
                        Text(
                          '$n ${n == 1 ? 'miembro' : 'miembros'} · creado por @$ownerName',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        const SizedBox(height: 12),
                        if (!isOwner)
                          joined
                              ? OutlinedButton(
                                  onPressed: () => guard(
                                    context,
                                    () => Db.leaveGroup(widget.groupId),
                                  ),
                                  child: const Text('Salir del grupo'),
                                )
                              : FilledButton(
                                  onPressed: () => guard(
                                    context,
                                    () => Db.joinGroup(widget.groupId),
                                  ),
                                  child: const Text('Unirme'),
                                ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  StreamBuilder<Snap>(
                    stream: _posts,
                    builder: (context, ps) {
                      if (ps.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error: ${ps.error}'),
                        );
                      }
                      if (!ps.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return ValueListenableBuilder<Set<String>>(
                        valueListenable: Session.i.blocked,
                        builder: (context, blocked, _) {
                          final docs = ps.data!.docs
                              .where((d) => !blocked.contains(d.data()['authorId']))
                              .toList()
                            ..sort(
                              (a, b) => _millis(b.data()['createdAt'])
                                  .compareTo(_millis(a.data()['createdAt'])),
                            );
                          if (docs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                child: Text('Aún no hay publicaciones en este grupo.'),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              const SizedBox(height: 6),
                              for (final d in docs)
                                PostCard(key: ValueKey(d.id), doc: d),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
