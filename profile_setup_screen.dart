import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';

/// Se muestra una sola vez, cuando la cuenta nueva aún no tiene perfil.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,20}$').hasMatch(name)) {
      setState(() => _error = '3 a 20 caracteres: letras, números o _');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lower = name.toLowerCase();
      final nameRef = fs.collection('usernames').doc(lower);
      final userRef = Db.users.doc(myUid);
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      // Transacción: garantiza que el nombre de usuario sea único.
      await fs.runTransaction((tx) async {
        final existing = await tx.get(nameRef);
        if (existing.exists) throw Exception('taken');
        tx.set(nameRef, {'uid': myUid});
        tx.set(userRef, {
          'username': name,
          'usernameLower': lower,
          'email': email,
          'bio': '',
          'photoUrl': '',
          'favoriteGames': <String>[],
          'banned': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      setState(() => _error = e.toString().contains('taken')
          ? 'Ese nombre ya está en uso.'
          : 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea tu perfil'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Salir'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Elige tu nombre de usuario de jugador'),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: 'Usuario',
                    prefixText: '@',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Continuar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
