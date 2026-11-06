import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _token = 0;
  bool _loading = false;
  String _query = '';
  List<QueryDocumentSnapshot<Json>> _results = [];
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final q = raw.trim().toLowerCase().replaceAll('@', '');
    final token = ++_token;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _query = q;
      _error = null;
    });
    try {
      final snap = await Db.users
          .where('usernameLower', isGreaterThanOrEqualTo: q)
          .where('usernameLower', isLessThan: '$q')
          .limit(25)
          .get();
      if (!mounted || token != _token) return;
      setState(() => _results = snap.docs);
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _error = 'No se pudo buscar: $e');
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar jugadores')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre de usuario',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: Session.i.blocked,
              builder: (context, blocked, _) {
                if (_error != null) return Center(child: Text(_error!));
                if (_query.isEmpty) {
                  return const Center(
                    child: Text('Escribe un nombre para encontrar gente.'),
                  );
                }
                final list = _results.where((d) {
                  final u = d.data();
                  return u['deleted'] != true && !blocked.contains(d.id);
                }).toList();
                if (list.isEmpty && !_loading) {
                  return const Center(child: Text('Sin resultados.'));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final d = list[i];
                    final u = d.data();
                    return ListTile(
                      leading: UserAvatar(uid: d.id),
                      title: Text('@${u['username'] ?? ''}'),
                      subtitle: (u['bio'] ?? '').toString().isEmpty
                          ? null
                          : Text(
                              u['bio'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            uid: d.id,
                            isMe: d.id == myUid,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
