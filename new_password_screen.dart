import 'package:flutter/material.dart' hide Text;

import '../l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;
import '../services/db.dart';

/// Pantalla para elegir una contraseña nueva (llega desde el enlace del correo).
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (_pass.text.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sb.auth.updateUser(UserAttributes(password: _pass.text));
      widget.onDone();
    } catch (e) {
      setState(() => _error = 'No se pudo cambiar la contraseña. Pide otro enlace.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Escribe tu nueva contraseña'),
                const SizedBox(height: 16),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr('Contraseña'), helperText: tr('Mínimo 8 caracteres')),
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
