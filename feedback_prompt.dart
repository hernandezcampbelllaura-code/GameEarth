import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';

import '../services/db.dart';
import '../util.dart';

/// Ventana para calificar la app de 1 a 5 estrellas y decir por qué.
/// Devuelve true si la persona envió su opinión.
Future<bool> showRatingDialog(BuildContext context) async {
  var stars = 0;
  final reason = TextEditingController();
  String? error;
  var sending = false;

  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('¿Qué te parece GamersLore?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Califica la app de 1 a 5 estrellas y cuéntanos por qué.'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 36,
                      onPressed: sending ? null : () => setD(() => stars = i),
                      icon: Icon(
                        i <= stars ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: reason,
                maxLength: 500,
                maxLines: 4,
                minLines: 3,
                enabled: !sending,
                decoration: InputDecoration(
                  labelText: tr('¿Por qué esa calificación?'),
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: sending ? null : () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: sending
                ? null
                : () async {
                    if (stars == 0) {
                      setD(() => error = 'Elige de 1 a 5 estrellas.');
                      return;
                    }
                    if (reason.text.trim().length < 3) {
                      setD(() => error = 'Cuéntanos brevemente por qué.');
                      return;
                    }
                    setD(() {
                      sending = true;
                      error = null;
                    });
                    try {
                      await Db.sendFeedback(stars, reason.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setD(() {
                        sending = false;
                        error = 'No se pudo enviar: $e';
                      });
                    }
                  },
            child: Text(sending ? 'Enviando…' : 'Enviar'),
          ),
        ],
      ),
    ),
  );
  reason.dispose();
  if (sent == true && context.mounted) toast(context, '¡Gracias por tu opinión!');
  return sent == true;
}
