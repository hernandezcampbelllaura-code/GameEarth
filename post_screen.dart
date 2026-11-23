import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../services/db.dart';
import '../widgets/post_card.dart';

/// Abre una sola publicación (cuando alguien comparte su enlace).
class PostScreen extends StatelessWidget {
  final String postId;
  const PostScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publicación')),
      body: FutureBuilder<Doc?>(
        future: Db.postById(postId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = snap.data;
          if (snap.hasError || doc == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Esta publicación no existe o ya fue eliminada.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(children: [PostCard(doc: doc)]);
        },
      ),
    );
  }
}
