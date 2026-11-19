import 'package:flutter/material.dart';

import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../util.dart';

/// Sube este número cuando cambies los términos.
const int kTermsVersion = 1;

/// Recuerda, mientras la app está abierta, que la persona marcó la casilla
/// al registrarse (se guarda en la base de datos al crear el perfil).
class TermsState {
  static bool accepted = false;
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _accepted = false;
  String? _error;
  final _human = TextEditingController();
  HumanCheck _check = HumanCheck();
  int _fails = 0;
  DateTime? _lockUntil;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _human.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lock = _lockUntil;
    if (lock != null && DateTime.now().isBefore(lock)) {
      final s = lock.difference(DateTime.now()).inSeconds + 1;
      setState(() => _error = 'Demasiados intentos. Espera $s segundos.');
      return;
    }
    if (!await requireOnline(context, _register ? 'crear tu cuenta' : 'iniciar sesión')) {
      return;
    }
    if (_register) {
      if (!_accepted) {
        setState(() => _error =
            'Debes aceptar los Términos y Condiciones para crear tu cuenta.');
        return;
      }
      if (_pass.text.length < 8) {
        setState(() => _error = 'La contraseña debe tener al menos 8 caracteres.');
        return;
      }
      if (!_check.ok(_human.text)) {
        setState(() {
          _error = 'La respuesta de la suma no es correcta.';
          _check = HumanCheck();
          _human.clear();
        });
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        TermsState.accepted = true;
        final r = await sb.auth.signUp(
          email: _email.text.trim(),
          password: _pass.text,
        );
        if (r.session == null && mounted) {
          TermsState.accepted = false;
          setState(() => _error =
              'Te enviamos un correo para confirmar tu cuenta. Ábrelo y vuelve a entrar.');
        }
      } else {
        await sb.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
      }
    } on AuthException catch (e) {
      TermsState.accepted = false;
      final code = (e.code ?? e.message).toString();
      var msg = _message(code, e.message);
      if (!_register && code.contains('invalid')) {
        msg = await _loginFailMessage(msg);
        _fails++;
        if (_fails >= 5) {
          _fails = 0;
          _lockUntil = DateTime.now().add(const Duration(seconds: 30));
          msg = 'Demasiados intentos fallidos. Espera 30 segundos.';
        }
      }
      if (mounted) setState(() => _error = msg);
    } catch (e) {
      TermsState.accepted = false;
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Distingue "no existe la cuenta" de "contraseña incorrecta".
  Future<String> _loginFailMessage(String fallback) async {
    try {
      final exists = await sb.rpc(
        'email_exists',
        params: {'p_email': _email.text.trim()},
      );
      if (exists == false) {
        return 'No existe ninguna cuenta con ese correo en la app. '
            'Toca "Regístrate" para crear una.';
      }
      return 'Contraseña incorrecta.';
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Escribe tu correo para recuperar la contraseña.');
      return;
    }
    try {
      await sb.auth.resetPasswordForEmail(_email.text.trim());
      setState(() => _error = 'Te enviamos un correo para restablecerla.');
    } on AuthException catch (e) {
      setState(() => _error = _message((e.code ?? e.message).toString(), e.message));
    }
  }

  String _message(String code, [String? detail]) {
    final c = code.toLowerCase();
    if (c.contains('invalid_credentials') || c.contains('invalid login')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (c.contains('invalid') && c.contains('email')) return 'Correo no válido.';
    if (c.contains('already') || c.contains('exists')) {
      return 'Ese correo ya está registrado.';
    }
    if (c.contains('weak') || c.contains('password')) {
      return 'Contraseña muy débil. Usa al menos 8 caracteres.';
    }
    if (c.contains('not_confirmed') || c.contains('not confirmed')) {
      return 'Debes confirmar tu correo. Revisa tu bandeja.';
    }
    if (c.contains('rate') || c.contains('too_many')) {
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }
    if (c.contains('network') || c.contains('socket') || c.contains('failed host')) {
      return 'Sin conexión a internet.';
    }
    return 'No se pudo continuar'
        '${detail == null || detail.isEmpty ? '' : ': $detail'}';
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_busy && (!_register || _accepted);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Icon(Icons.sports_esports, size: 72),
                  const SizedBox(height: 8),
                  Text(
                    'GamingSocial',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      helperText: _register ? 'Mínimo 8 caracteres' : null,
                    ),
                    onSubmitted: (_) => canSubmit ? _submit() : null,
                  ),
                  if (_register) ...[
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
                                  onTap: _openTerms,
                                  child: Text(
                                    'Términos y Condiciones',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ' y confirmo que tengo 18 años o más.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _human,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'No soy un robot: ${_check.question}',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canSubmit ? _submit : null,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Crear cuenta' : 'Iniciar sesión'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
                    child: Text(
                      _register
                          ? 'Ya tengo cuenta'
                          : '¿No tienes cuenta? Regístrate',
                    ),
                  ),
                  if (!_register)
                    TextButton(
                      onPressed: _reset,
                      child: const Text('Olvidé mi contraseña'),
                    ),
                  TextButton(
                    onPressed: () => showContactDialog(context),
                    child: const Text('¿No estás de acuerdo con algo? Escríbenos'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla con el texto de los Términos y Condiciones.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const List<List<String>> _sections = [
    [
      '1. Edad mínima',
      'GamingSocial es solo para personas de 18 años o más. Al crear una cuenta '
          'confirmas que cumples este requisito.',
    ],
    [
      '2. Contenido prohibido',
      'Está prohibido publicar, comentar o enviar:\n'
          '• Contenido sexual, pornográfico o para mayores de 18 años.\n'
          '• Desnudos o imágenes sexualizadas.\n'
          '• Violencia gráfica, gore o contenido que muestre daño real a personas o animales.\n'
          '• Cualquier contenido que involucre a menores de forma inapropiada.\n'
          '• Contenido que promueva autolesiones, drogas ilegales o actividades ilegales.',
    ],
    [
      '3. Respeto hacia los demás',
      'No se permiten insultos, ofensas, acoso, amenazas, discriminación ni '
          'discursos de odio por motivos de raza, origen, religión, género, '
          'orientación sexual, discapacidad u otra condición.',
    ],
    [
      '4. Contenido que no es tuyo',
      'Sube solo fotos, videos y textos que sean tuyos o para los que tengas '
          'permiso. No publiques datos personales de otras personas (teléfono, '
          'dirección, documentos) ni te hagas pasar por alguien más.',
    ],
    [
      '5. Spam, fraudes y seguridad',
      'No se permite el spam, las estafas, los enlaces engañosos, los virus o '
          'programas maliciosos, ni intentar acceder sin permiso a cuentas o '
          'sistemas de la aplicación.',
    ],
    [
      '6. Denuncias y sanciones',
      'Puedes denunciar o bloquear a cualquier usuario. El administrador puede '
          'eliminar publicaciones o comentarios y suspender o eliminar cuentas '
          'que incumplan estas reglas, sin aviso previo.',
    ],
    [
      '7. Tu contenido y tu cuenta',
      'Eres responsable de lo que publicas y de mantener segura tu contraseña. '
          'Al publicar permites que GamingSocial muestre tu contenido a otros '
          'usuarios dentro de la aplicación.',
    ],
    [
      '8. Cambios',
      'Estos términos pueden actualizarse. Si sigues usando la aplicación '
          'después de un cambio, se entiende que lo aceptas.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y Condiciones')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final s in _sections) ...[
            Text(
              s[0],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(s[1], style: const TextStyle(height: 1.4)),
            const SizedBox(height: 18),
          ],
          Center(
            child: TextButton(
              onPressed: () => showContactDialog(context),
              child: const Text('¿No estás de acuerdo? Escríbenos'),
            ),
          ),
          Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    );
  }
}
