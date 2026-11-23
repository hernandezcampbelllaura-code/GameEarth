import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import 'auth_screen.dart';

/// Se muestra una sola vez, cuando la cuenta nueva aún no tiene perfil.
class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const ProfileSetupScreen({super.key, this.onSaved});
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
    final u = sb.auth.currentUser;
    var base = (u?.userMetadata?['full_name'] ?? u?.userMetadata?['name'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
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
      await sb.from('profiles').insert({
        'id': myUid,
        'username': name,
        'username_lower': name.toLowerCase(),
        'accepted_terms': true,
        'terms_version': kTermsVersion,
      });
      Db.forgetProfile(myUid);
      widget.onSaved?.call();
    } catch (e) {
      setState(() => _error = (e.toString().contains('23505') || e.toString().contains('duplicate'))
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
            onPressed: () => sb.auth.signOut(),
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
                    labelText: tr('Usuario'),
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
