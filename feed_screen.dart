import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../net.dart';
import '../services/db.dart';
import '../widgets/post_card.dart';
import 'chats_screen.dart';
import 'help_screen.dart';
import 'search_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final Stream<Snap> _stream =
      Db.watchPosts();

  Widget _list(List<Doc> docs, String empty) {
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(empty, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: docs.length,
      itemBuilder: (_, i) => PostCard(key: ValueKey(docs[i].id), doc: docs[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GamingSocial',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ConnectionDot(),
            ],
          ),
          actions: [
            IconButton(
              tooltip: tr('Ayuda y preguntas'),
              icon: const Icon(Icons.help_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              ),
            ),
            IconButton(
              tooltip: tr('Buscar jugadores'),
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [Tab(text: tr('Para ti')), Tab(text: tr('Siguiendo')), Tab(text: tr('Chats'))],
          ),
        ),
        body: StreamBuilder<Snap>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!.docs;
            return ValueListenableBuilder<Set<String>>(
              valueListenable: Session.i.blocked,
              builder: (context, blocked, _) {
                return ValueListenableBuilder<Set<String>>(
                  valueListenable: Session.i.following,
                  builder: (context, following, _) {
                    final visible = all
                        .where((d) =>
                            !blocked.contains(d.data()['authorId']) &&
                            ((d.data()['groupId'] ?? '') as String).isEmpty)
                        .toList();
                    final fromFollowed = visible.where((d) {
                      final a = d.data()['authorId'];
                      return following.contains(a) || a == myUid;
                    }).toList();
                    return TabBarView(
                      children: [
                        _list(visible, 'Aún no hay publicaciones.\n¡Sé el primero en publicar!'),
                        _list(
                          fromFollowed,
                          'Aquí verás lo que publiquen las personas que sigues.\nUsa Buscar para encontrar jugadores.',
                        ),
                        const ChatsTab(),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
