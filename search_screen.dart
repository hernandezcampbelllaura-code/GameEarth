import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../services/db.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  /// Si es true, al tocar a alguien se devuelve [uid, nombre] (para chats).
  final bool pick;
  const SearchScreen({super.key, this.pick = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _token = 0;
  bool _loading = false;
  String _query = '';
  List<Doc> _results = [];
  String? _error;
  List<Doc> _following = [];

  @override
  void initState() {
    super.initState();
    _loadFollowing();
    Session.i.following.addListener(_loadFollowing);
  }

  Future<void> _loadFollowing() async {
    try {
      final l = await Db.firstFollowing();
      if (mounted) setState(() => _following = l);
    } catch (_) {}
  }

  @override
  void dispose() {
    Session.i.following.removeListener(_loadFollowing);
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
      final docs = await Db.searchUsers(q);
      if (!mounted || token != _token) return;
      setState(() => _results = docs);
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _error = 'No se pudo buscar: $e');
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  Widget _tile(Doc d) {
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
      onTap: () {
        if (widget.pick) {
          if (d.id == myUid) return;
          Navigator.pop(
            context,
            <String>[d.id, (u['username'] ?? '') as String],
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(uid: d.id, isMe: d.id == myUid),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pick ? 'Elige con quién chatear' : 'Buscar jugadores'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: tr('Buscar por nombre de usuario'),
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
                final list = _query.isEmpty
                    ? <Doc>[]
                    : _results.where((d) {
                        final u = d.data();
                        return u['deleted'] != true && !blocked.contains(d.id);
                      }).toList();
                final follows = _following.where((d) {
                  final u = d.data();
                  return u['deleted'] != true && !blocked.contains(d.id);
                }).toList();
                final Widget? note = _query.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Escribe un nombre para encontrar gente.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : (list.isEmpty && !_loading
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Sin resultados.',
                                textAlign: TextAlign.center),
                          )
                        : null);
                return ListView(
                  children: [
                    for (final d in list) _tile(d),
                    if (note != null) note,
                    if (follows.isNotEmpty) ...[
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          'Personas que sigues',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final d in follows) _tile(d),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
