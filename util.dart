import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart' hide Text;
import 'l10n.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'services/db.dart' show Doc;

String formatDate(dynamic ts) {
  if (ts is! DateTime) return tr('ahora');
  final d = ts;
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return tr('ahora');
  if (diff.inMinutes < 60) return trf('hace {n} min', {'n': diff.inMinutes});
  if (diff.inHours < 24) return trf('hace {n} h', {'n': diff.inHours});
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(msg))));
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

/// Descarga el video. En la web se abre el enlace de descarga; en Android se
/// baja dentro de la app y se abre el menú para guardarlo en el teléfono.
Future<void> downloadVideo(BuildContext context, String url) async {
  if (url.isEmpty) return;
  if (kIsWeb) {
    try {
      await launchUrl(Uri.parse(videoDownloadUrl(url)), webOnlyWindowName: '_blank');
    } catch (_) {
      if (context.mounted) toast(context, 'No se pudo descargar el video.');
    }
    return;
  }
  toast(context, 'Descargando video…');
  try {
    final r = await http
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 5));
    if (r.statusCode != 200) throw Exception('código ${r.statusCode}');
    await Share.shareXFiles([
      XFile.fromData(r.bodyBytes, mimeType: 'video/mp4', name: 'GamersLore.mp4'),
    ], text: 'Video de GamersLore');
  } catch (e) {
    if (context.mounted) toast(context, 'No se pudo descargar el video: $e');
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
              queryParameters: {'subject': 'GamersLore - Contacto'},
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


final Map<String, String> _trCache = {};

/// Idioma de destino para traducir publicaciones (es, en, fr, pt, de, ru).
String targetLang() => L.base;

/// Traduce un texto (cualquier idioma) al idioma elegido en la app.
/// Devuelve null si no se pudo. Usa servicios gratuitos, con respaldo.
Future<String?> translateText(String text, String target) async {
  final key = '$target|$text';
  final hit = _trCache[key];
  if (hit != null) return hit;
  final q = text.length > 1500 ? text.substring(0, 1500) : text;
  try {
    final r = await http
        .get(Uri.https('translate.googleapis.com', '/translate_a/single', {
          'client': 'gtx',
          'sl': 'auto',
          'tl': target,
          'dt': 't',
          'q': q,
        }))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      final out = (j[0] as List).map((e) => (e as List)[0] as String).join();
      if (out.trim().isNotEmpty) return _trCache[key] = out;
    }
  } catch (_) {}
  try {
    final r = await http
        .get(Uri.https('api.mymemory.translated.net', '/get', {
          'q': q.length > 450 ? q.substring(0, 450) : q,
          'langpair': 'autodetect|$target',
        }))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final out = (j['responseData']?['translatedText'] ?? '') as String;
      if (out.trim().isNotEmpty && j['responseStatus'].toString() == '200') {
        return _trCache[key] = out;
      }
    }
  } catch (_) {}
  return null;
}


/// Puntuación de una publicación para el feed "Para ti".
/// Premia interacción (vistas, reacciones, comentarios) y novedad, y baja con las horas.
double postScore(Map<String, dynamic> d, {required bool followed, DateTime? now}) {
  num n(String k) => (d[k] is num) ? d[k] as num : 0;
  final created = d['createdAt'];
  final t = created is DateTime ? created : DateTime.tryParse('$created');
  final age = t == null
      ? 24.0
      : ((now ?? DateTime.now()).difference(t).inMinutes / 60.0).clamp(0.0, 24 * 365);
  final engagement =
      1 + n('views') * 0.2 + n('likesCount') * 2 + n('commentsCount') * 3;
  var score = engagement / math.pow(age + 2, 1.3);
  if (followed) score *= 1.6; // quien sigues pesa más
  if (age < 1) score *= 1.5; // las nuevas tienen su oportunidad
  return score;
}

/// Ordena ids por puntuación evitando muchas seguidas del mismo autor.
List<String> rankPosts(
  List<Doc> docs,
  Set<String> following, {
  DateTime? now,
}) {
  final left = <_Scored>[
    for (final d in docs)
      _Scored(
        d.id,
        '${d.data()['authorId']}',
        postScore(d.data(),
            followed: following.contains(d.data()['authorId']), now: now),
      ),
  ];
  final out = <String>[];
  final used = <String, int>{};
  while (left.isNotEmpty) {
    left.sort((a, b) =>
        (b.score * math.pow(0.7, used[b.author] ?? 0))
            .compareTo(a.score * math.pow(0.7, used[a.author] ?? 0)));
    final x = left.removeAt(0);
    out.add(x.id);
    used[x.author] = (used[x.author] ?? 0) + 1;
  }
  return out;
}

class _Scored {
  _Scored(this.id, this.author, this.score);
  final String id;
  final String author;
  final double score;
}
