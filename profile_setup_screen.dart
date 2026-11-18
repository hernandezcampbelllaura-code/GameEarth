import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import 'auth_screen.dart';

/// Se muestra una sola vez, cuando la cuenta nueva aún no tiene perfil.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  bool _accepted = TermsState.accepted;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Si entró con Google, se rellena el nombre de usuario con su nombre.
    final u = FirebaseAuth.instance.currentUser;
    var base = (u?.displayName ?? '').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (base.isEmpty) {
      base = (u?.email ?? '').split('@').first.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    }
    if (base.length > 20) base = base.substring(0, 20);
    if (base.length >= 3) _name.text = base;
  }

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
    if (!_accepted) {
      setState(() => _error = 'Debes aceptar los Términos y Condiciones.');
      return;
    }
    if (Safety.isBad(name)) {
      setState(() => _error = 'Ese nombre no está permitido.');
      return;
    }
    if (!await requireOnline(context, 'guardar tu perfil')) return;
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
        tx.set(fs.collection('userPrivate').doc(myUid), {
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(userRef, {
          'username': name,
          'usernameLower': lower,
          'bio': '',
          'photoUrl': '',
          'favoriteGames': <String>[],
          'banned': false,
          'acceptedTerms': true,
          'termsVersion': kTermsVersion,
          'acceptedTermsAt': FieldValue.serverTimestamp(),
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
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _accepted,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _accepted = v ?? false),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          children: [
                            const Text('Acepto los '),
                            GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ),
                              child: Text(
                                'Términos y Condiciones',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const Text(' y tengo 18 años o más.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy || !_accepted ? null : _save,
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
