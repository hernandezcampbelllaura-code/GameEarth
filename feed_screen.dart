import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../widgets/post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final Stream<QuerySnapshot<Json>> _stream =
      Db.posts.orderBy('createdAt', descending: true).limit(100).snapshots();

  Widget _list(List<QueryDocumentSnapshot<Json>> docs, String empty) {
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
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'GamingSocial',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            tabs: [Tab(text: 'Para ti'), Tab(text: 'Siguiendo')],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Json>>(
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
                        .where((d) => !blocked.contains(d.data()['authorId']))
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
