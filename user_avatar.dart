import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';

class UserAvatar extends StatelessWidget {
  final String uid;
  final double radius;
  const UserAvatar({super.key, required this.uid, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Json?>(
      future: Db.profileOf(uid),
      builder: (context, s) {
        final data = s.data;
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

/// Botón pequeño "Seguir" / "Siguiendo" junto al nombre de quien publicó.
class FollowChip extends StatelessWidget {
  final String uid;
  const FollowChip({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty || uid == myUid) return const SizedBox.shrink();
    return ValueListenableBuilder<Set<String>>(
      valueListenable: Session.i.following,
      builder: (context, following, _) {
        final on = following.contains(uid);
        Future<void> toggle() => guard(context, () async {
              if (on) {
                await Db.unfollow(uid);
                Session.i.following.value = {...following}..remove(uid);
              } else {
                await Db.follow(uid);
                Session.i.following.value = {...following, uid};
              }
            });
        const pad = EdgeInsets.symmetric(horizontal: 12);
        const size = Size(0, 28);
        return Padding(
          padding: const EdgeInsets.only(left: 10),
          child: on
              ? OutlinedButton(
                  onPressed: toggle,
                  style: OutlinedButton.styleFrom(
                    padding: pad,
                    minimumSize: size,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Siguiendo', style: TextStyle(fontSize: 12)),
                )
              : FilledButton(
                  onPressed: toggle,
                  style: FilledButton.styleFrom(
                    padding: pad,
                    minimumSize: size,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Seguir', style: TextStyle(fontSize: 12)),
                ),
        );
      },
    );
  }
}
