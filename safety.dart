import 'dart:math';

import 'package:flutter/material.dart';

/// Filtro de palabras ofensivas o sexuales (texto). Es una primera barrera
/// automática; lo que se escape lo atrapan las denuncias y el administrador.
class Safety {
  Safety._();

  static const List<String> _words = [
    // Español
    'puta', 'puto', 'putas', 'putos', 'mierda', 'cabron', 'cabrona',
    'pendejo', 'pendeja', 'gilipollas', 'maricon', 'hijueputa', 'hdp',
    'verga', 'pinga', 'singao', 'singar', 'mamabicho', 'follar',
    'porno', 'pornografia', 'desnudo', 'desnuda', 'desnudos', 'nudes',
    'violar', 'violacion', 'pedofilo', 'pedofilia', 'zorra',
    'hijo de puta', 'chupa pinga', 'la concha de tu madre',
    // Inglés
    'fuck', 'fucking', 'shit', 'bitch', 'asshole', 'cunt', 'nigger', 'nigga',
    'faggot', 'whore', 'slut', 'porn', 'xxx', 'blowjob', 'rape', 'pedophile',
  ];

  static String _norm(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ@\$0134578';
    const to = 'aaaaeeeeiiiioooouuuunasoieastb';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// true si el texto trae alguna palabra bloqueada.
  static bool isBad(String text) {
    final n = _norm(text);
    final tokens = n.split(RegExp(r'[^a-z]+')).where((t) => t.isNotEmpty);
    final joined = ' ${tokens.join(' ')} ';
    final set = tokens.toSet();
    for (final w in _words) {
      if (w.contains(' ')) {
        if (joined.contains(' $w ')) return true;
      } else if (set.contains(w)) {
        return true;
      }
    }
    return false;
  }

  /// Revisa varios textos; si alguno es ofensivo muestra aviso y devuelve false.
  static bool check(BuildContext context, List<String> texts) {
    if (texts.any(isBad)) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.block, size: 32),
          title: const Text('Contenido no permitido'),
          content: const Text(
            'Tu texto parece tener lenguaje ofensivo o sexual, que está '
            'prohibido en GamingSocial. Cámbialo e inténtalo de nuevo.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }
}

/// Límite de velocidad en el teléfono (frena bots simples y toques repetidos).
class RateLimit {
  RateLimit._();
  static final Map<String, DateTime> _last = {};

  /// Devuelve 0 si puede seguir, o los segundos que debe esperar.
  static int wait(String key, int seconds) {
    final now = DateTime.now();
    final prev = _last[key];
    if (prev != null) {
      final left = seconds - now.difference(prev).inSeconds;
      if (left > 0) return left;
    }
    _last[key] = now;
    return 0;
  }
}

/// Pregunta sencilla para comprobar que quien se registra es una persona.
class HumanCheck {
  final int a = Random().nextInt(8) + 2;
  final int b = Random().nextInt(8) + 2;
  String get question => '¿Cuánto es $a + $b?';
  bool ok(String answer) => int.tryParse(answer.trim()) == a + b;
}
