import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';

class UserAvatar extends StatelessWidget {
  final String uid;
  final double radius;
  const UserAvatar({super.key, required this.uid, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.users.doc(uid).snapshots(),
      builder: (context, s) {
        final data = s.data?.data();
        final url = (data?['photoUrl'] as String?) ?? '';
        final name = (data?['username'] as String?) ?? '?';
        return CircleAvatar(
          radius: radius,
          backgroundImage: url.isEmpty ? null : CachedNetworkImageProvider(url),
          child: url.isEmpty
              ? Text(name.isEmpty ? '?' : name[0].toUpperCase())
              : null,
        );
      },
    );
  }
}
