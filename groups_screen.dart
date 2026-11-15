import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';
import 'group_detail_screen.dart';

/// Lista de grupos. Cualquiera puede crear uno y unirse a los demás.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final Stream<QuerySnapshot<Json>> _stream =
      Db.groups.orderBy('createdAt', descending: true).limit(100).snapshots();

  Future<void> _create() async {
    final name = TextEditingController();
    final desc = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Crear grupo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Nombre del grupo'),
                ),
                TextField(
                  controller: desc,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
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
              onPressed: () {
                if (name.text.trim().length < 3) {
                  setD(() => error = 'El nombre necesita al menos 3 letras.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(
      context,
      () => Db.createGroup(name.text.trim(), desc.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Grupos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.group_add),
        label: const Text('Crear grupo'),
      ),
      body: StreamBuilder<QuerySnapshot<Json>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no hay grupos.\n¡Crea el primero!',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final g = docs[i].data();
              final n = ((g['membersCount'] ?? 0) as num).toInt();
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups)),
                title: Text((g['name'] ?? '') as String),
                subtitle: Text(
                  '$n ${n == 1 ? 'miembro' : 'miembros'}'
                  '${((g['description'] ?? '') as String).isEmpty ? '' : ' · ${g['description']}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailScreen(groupId: docs[i].id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
