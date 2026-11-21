import 'dart:async';

import 'package:flutter/material.dart';

import '../notifier.dart';
import '../services/db.dart';
import 'admin_screen.dart';
import 'create_screen.dart';
import 'feed_screen.dart';
import '../widgets/feedback_prompt.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';
import 'post_screen.dart';
import 'reels_screen.dart';

class _Dest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
  const _Dest(this.label, this.icon, this.selectedIcon, this.page);
}

/// Contenedor principal. En teléfonos usa barra inferior; en pantallas
/// anchas (tablet / ventana grande) usa un riel lateral y centra el contenido.
/// La pestaña "Admin" solo existe si hay un documento admins/<tu uid>.
class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  Timer? _ratingTimer;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    Session.i.start(widget.uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Lo no esencial arranca un momento después, para que la app abra rápido.
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        Notifier.start(context, widget.uid);
        Updater.start(() => context);
      });
      // Si entró por el enlace de una publicación compartida, se abre.
      final pid = Uri.base.queryParameters['post'];
      if (pid != null && pid.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostScreen(postId: pid)),
        );
      }
    });
    // Cada 30 minutos de uso se le pide a la persona calificar la app.
    _ratingTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
      if (!mounted || _asking) return;
      _asking = true;
      try {
        await showRatingDialog(context);
      } finally {
        _asking = false;
      }
    });
  }

  @override
  void dispose() {
    _ratingTimer?.cancel();
    Notifier.stop();
    Updater.stop();
    Session.i.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Session.i.isAdmin,
      builder: (context, admin, _) {
        final dests = <_Dest>[
          const _Dest('Inicio', Icons.home_outlined, Icons.home, FeedScreen()),
          _Dest(
            'Reels',
            Icons.play_circle_outline,
            Icons.play_circle,
            ReelsScreen(active: _index == 1),
          ),
          _Dest(
            'Crear',
            Icons.add_circle_outline,
            Icons.add_circle,
            CreateScreen(
              onDone: (id, isVideo) {
                if (isVideo) {
                  // Tu reel aparece de primero en Reels.
                  Session.i.focusReel.value = id;
                  setState(() => _index = 1);
                } else {
                  setState(() => _index = 0);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PostScreen(postId: id)),
                  );
                }
              },
            ),
          ),
          const _Dest('Grupos', Icons.groups_outlined, Icons.groups, GroupsScreen()),
          _Dest(
            'Perfil',
            Icons.person_outline,
            Icons.person,
            ProfileScreen(uid: widget.uid, isMe: true),
          ),
          if (admin)
            const _Dest(
              'Admin',
              Icons.shield_outlined,
              Icons.shield,
              AdminScreen(),
            ),
        ];
        final index = _index >= dests.length ? 0 : _index;
        final body = IndexedStack(
          index: index,
          children: [for (final d in dests) d.page],
        );

        return LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 720) {
              return Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: index,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: [
                        for (final d in dests)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Scaffold(
              body: body,
              bottomNavigationBar: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final d in dests)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
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
