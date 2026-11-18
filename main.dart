import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'net.dart';
import 'screens/auth_screen.dart';
import 'screens/banned_screen.dart';
import 'screens/home_shell.dart';
import 'screens/profile_setup_screen.dart';
import 'theme.dart';

/// La app se dibuja al instante (pantalla de inicio) y Firebase se prepara
/// por detrás, para que nunca se vea una pantalla en blanco.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GamingSocialApp());
}

Future<void> _init() async {
  await Firebase.initializeApp(
    options: kIsWeb ? AppFirebaseOptions.web : AppFirebaseOptions.android,
  );
  try {
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);
  } catch (_) {}
  await Net.i.start();
}

class GamingSocialApp extends StatefulWidget {
  const GamingSocialApp({super.key});

  @override
  State<GamingSocialApp> createState() => _GamingSocialAppState();
}

class _GamingSocialAppState extends State<GamingSocialApp> {
  late Future<void> _ready = _init();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GamingSocial',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) =>
          ConnectionBanner(child: child ?? const SizedBox.shrink()),
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No se pudo iniciar: ${snap.error}'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => setState(() => _ready = _init()),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const _Loader();
          }
          return const AuthGate();
        },
      ),
    );
  }
}

class _Loader extends StatefulWidget {
  const _Loader();
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  bool _slow = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_esports, size: 64),
            const SizedBox(height: 8),
            const Text(
              'GamingSocial',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            if (_slow) ...[
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Tu conexión está lenta. Sigue intentando…',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Decide qué pantalla mostrar: login, crear perfil, baneado o la app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }
        final user = snap.data;
        if (user == null) return const AuthScreen();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, ps) {
            if (ps.hasError) {
              return Scaffold(
                body: Center(child: Text('Error: ${ps.error}')),
              );
            }
            if (!ps.hasData) return const _Loader();
            final doc = ps.data!;
            if (!doc.exists) return const ProfileSetupScreen();
            if (doc.data()?['banned'] == true) return const BannedScreen();
            return HomeShell(uid: user.uid);
          },
        );
      },
    );
  }
}
