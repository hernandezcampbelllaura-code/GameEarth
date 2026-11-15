import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

String formatDate(dynamic ts) {
  if (ts is! Timestamp) return 'ahora';
  final d = ts.toDate();
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
  if (ts is! Timestamp) return '-';
  final d = ts.toDate();
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
Future<void> sharePost({
  required String author,
  required String text,
  String imageUrl = '',
  String videoUrl = '',
  String linkUrl = '',
}) async {
  final parts = <String>[
    '@$author en GamingSocial:',
    if (text.isNotEmpty) text,
    if (videoUrl.isNotEmpty) videoUrl,
    if (imageUrl.isNotEmpty) imageUrl,
    if (linkUrl.isNotEmpty) linkUrl,
  ];
  await Share.share(parts.join('\n'));
}
