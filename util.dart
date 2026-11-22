import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';

String formatDate(dynamic ts) {
  if (ts is! DateTime) return 'ahora';
  final d = ts;
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return '${d.day}/${d.month}/${d.year}';
}

Future<bool> confirmDialog(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  return r == true;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Fecha completa dd/mm/aaaa (para el panel de admin).
String formatFullDate(dynamic ts) {
  if (ts is! DateTime) return '-';
  final d = ts;
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

/// Ejecuta una acción y muestra el error en pantalla si falla.
Future<void> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) toast(context, 'Error: $e');
  }
}

/// Devuelve un enlace http(s) válido, o '' si no lo es. Si la persona escribe
/// "ejemplo.com" le agrega https:// automáticamente.
String cleanUrl(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return '';
  if (!t.startsWith('http://') && !t.startsWith('https://')) t = 'https://$t';
  final u = Uri.tryParse(t);
  if (u == null || !u.hasAuthority || !u.host.contains('.')) return '';
  if (u.scheme != 'http' && u.scheme != 'https') return '';
  return t.length > 300 ? '' : t;
}

/// Abre un enlace en el navegador. Solo http/https (nunca otros esquemas).
Future<void> openLink(BuildContext context, String url) async {
  final ok = cleanUrl(url);
  if (ok.isEmpty) {
    toast(context, 'Enlace no válido');
    return;
  }
  final confirm = await confirmDialog(
    context,
    'Vas a salir de la app para abrir:\n$ok\n\nAbre solo enlaces en los que confíes.',
  );
  if (!confirm) return;
  try {
    final done = await launchUrl(
      Uri.parse(ok),
      mode: LaunchMode.externalApplication,
    );
    if (!done && context.mounted) toast(context, 'No se pudo abrir el enlace');
  } catch (_) {
    if (context.mounted) toast(context, 'No se pudo abrir el enlace');
  }
}

/// Abre el menú de compartir del teléfono (WhatsApp, etc.).
/// Dirección que obliga al navegador a descargar el video (Cloudinary).
String videoDownloadUrl(String url) {
  const marker = '/upload/';
  final i = url.indexOf(marker);
  if (i < 0 || !url.startsWith('https://res.cloudinary.com/')) return url;
  return '${url.substring(0, i + marker.length)}fl_attachment/${url.substring(i + marker.length)}';
}

/// Descarga el video: se abre el enlace de descarga y el teléfono lo guarda.
Future<void> downloadVideo(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(videoDownloadUrl(url)),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) toast(context, 'No se pudo descargar el video.');
    if (ok && context.mounted) {
      toast(context, 'Descargando… revisa tus descargas.');
    }
  } catch (_) {
    if (context.mounted) toast(context, 'No se pudo descargar el video.');
  }
}

/// Enlace que abre una publicación en la versión web.
String postLink(String postId) => '$kWebUrl?post=$postId';

/// Comparte el enlace de la publicación (no su texto).
Future<void> sharePost({required String postId}) async {
  await Share.share(postLink(postId));
}

/// Correo de contacto: lo ve cualquier persona que use la app.
const String kContactEmail = 'hernandezcampbelllaura@gmail.com';

/// Ventana "¿No estás de acuerdo con algo?" con el correo para escribir.
Future<void> showContactDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Contacto'),
      content: const Text(
        '¿No estás de acuerdo con una decisión, una suspensión o algo de la '
        'app? Escríbenos y lo revisamos.\n\n$kContactEmail',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: kContactEmail));
            if (ctx.mounted) {
              Navigator.pop(ctx);
              toast(context, 'Correo copiado');
            }
          },
          child: const Text('Copiar correo'),
        ),
        FilledButton(
          onPressed: () async {
            final uri = Uri(
              scheme: 'mailto',
              path: kContactEmail,
              queryParameters: {'subject': 'GamingSocial - Contacto'},
            );
            try {
              final ok =
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && ctx.mounted) toast(ctx, 'No se pudo abrir el correo');
            } catch (_) {
              if (ctx.mounted) toast(ctx, 'No se pudo abrir el correo');
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Escribir correo'),
        ),
      ],
    ),
  );
}
