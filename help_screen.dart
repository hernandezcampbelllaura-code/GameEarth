import 'package:flutter/material.dart';

import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import '../util.dart';

/// Preguntas y respuestas: ayuda de la app (sirve antes de iniciar sesión).
const List<List<String>> kFaq = [
  [
    '¿Cómo inicio sesión?',
    'Escribe tu correo y tu contraseña y toca "Iniciar sesión". Si todavía no tienes cuenta, toca "Crear cuenta", acepta los términos (+18) y completa los datos.',
  ],
  [
    '¿Cómo creo mi cuenta?',
    'En la pantalla de inicio toca "Crear cuenta". Usa un correo real, una contraseña de al menos 8 caracteres, resuelve la suma de verificación y acepta los términos. Después elige tu nombre de usuario.',
  ],
  [
    'Dice que no existe ninguna cuenta con mi correo',
    'Revisa que el correo esté bien escrito. Si nunca te registraste en la app, toca "Crear cuenta".',
  ],
  [
    'Olvidé mi contraseña',
    'En la pantalla de inicio toca "Olvidé mi contraseña", escribe tu correo y te enviaremos un enlace para crear una nueva.',
  ],
  [
    'Se bloqueó el inicio de sesión',
    'Tras 5 intentos fallidos se bloquea 30 segundos por seguridad. Espera y vuelve a intentarlo.',
  ],
  [
    '¿Cómo publico una foto, video o enlace?',
    'Ve a la pestaña "Crear", escribe una descripción y elige Foto o Video. Puedes usar la cámara o la galería, y recortar la foto antes de subirla. Luego toca "Publicar".',
  ],
  [
    '¿Cómo subo un reel?',
    'En "Crear" elige Video. Al publicar, tu reel aparece primero en la pestaña Reels.',
  ],
  [
    '¿Cómo cambio mi foto de perfil?',
    'Ve a "Perfil", toca "Editar perfil" y luego "Cambiar foto". Puedes tomar una foto con la cámara o elegir una de la galería, y recortarla.',
  ],
  [
    '¿Cómo reacciono a una publicación?',
    'Toca el corazón para dar "Me encanta". Mantén presionado para elegir otra reacción: 👍 😢 😡 😮 😕. Arriba del botón ves cuántas hay de cada una.',
  ],
  [
    '¿Cómo comparto una publicación?',
    'Toca el botón de compartir: se envía el enlace de la publicación. Quien lo abra la verá directamente.',
  ],
  [
    '¿Cómo respondo un comentario?',
    'Toca "Responder" debajo del comentario, escribe tu respuesta y envíala.',
  ],
  [
    '¿Cómo sigo a alguien o le escribo?',
    'Toca "Seguir" junto a su nombre en una publicación o en su perfil. Para escribirle, entra a su perfil y toca "Mensaje". Tus chats están en Inicio → Chats.',
  ],
  [
    '¿Cómo reporto o bloqueo a alguien?',
    'En su publicación o perfil toca el menú (⋮) y elige "Reportar" o "Bloquear".',
  ],
  [
    '¿Cómo activo las notificaciones?',
    'La app te pregunta al entrar. Si dijiste que no, puedes activarlas en los permisos del navegador o del teléfono. Solo llegan mientras la app está abierta o en segundo plano.',
  ],
  [
    'La app va lenta o dice "sin conexión"',
    'Revisa tu internet. En la parte superior verás un punto que indica la conexión; cuando vuelve, se actualiza sola.',
  ],
  [
    '¿Cómo actualizo la app?',
    'La web se actualiza sola. En Android, cuando haya una versión nueva la app te avisará para instalarla.',
  ],
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    // Sin sesión no se puede enviar: se ofrece el correo de contacto.
    if (sb.auth.currentUser == null) {
      await showContactDialog(context);
      return;
    }
    final c = TextEditingController(text: _search.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Haz tu pregunta'),
        content: TextField(
          controller: c,
          maxLength: 300,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Escribe tu pregunta…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    if (!await requireOnline(context, 'enviar tu pregunta')) return;
    if (!mounted || !Safety.check(context, [text])) return;
    final w = RateLimit.wait('ask', 20);
    if (w > 0) {
      toast(context, 'Espera $w s para enviar otra pregunta.');
      return;
    }
    await guard(context, () async {
      await Db.askQuestion(text);
      if (mounted) {
        toast(context, 'Pregunta enviada. Te responderemos pronto.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = kFaq
        .where((e) =>
            q.isEmpty ||
            e[0].toLowerCase().contains(q) ||
            e[1].toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda y preguntas')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Busca tu duda: iniciar sesión, publicar…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No encontramos esa pregunta. Puedes hacerla abajo.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final e in items)
            Card(
              child: ExpansionTile(
                title: Text(e[0]),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(e[1])],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ask,
            icon: const Icon(Icons.help_outline),
            label: const Text('¿No encuentras tu respuesta? Pregunta aquí'),
          ),
        ],
      ),
    );
  }
}
