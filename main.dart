import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/banned_screen.dart';
import 'screens/home_shell.dart';
import 'screens/profile_setup_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: AppFirebaseOptions.android);
  runApp(const GamingSocialApp());
}

class GamingSocialApp extends StatelessWidget {
  const GamingSocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GamingSocial',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
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
