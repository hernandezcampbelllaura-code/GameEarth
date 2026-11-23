import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'l10n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import 'notify_stub.dart' if (dart.library.js_interop) 'notify_web.dart';
import 'services/db.dart';

/// Versión de esta copia de la app (la pone la compilación automática).
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

const String _repo = 'hernandezcampbelllaura-code/GameEarth';

/// Avisos (notificaciones) mientras la app está abierta o en segundo plano.
class Notifier {
  Notifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static RealtimeChannel? _ch;
  static int _id = 0;

  static Future<void> _init() async {
    if (_ready || kIsWeb) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  static Future<bool> _request() async {
    if (kIsWeb) return webRequestPermission();
    await _init();
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return (await a?.requestNotificationsPermission()) ?? false;
  }

  static void _show(String title, String body) {
    if (kIsWeb) {
      webShow(title, body);
      return;
    }
    _plugin.show(
      _id++,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gs_main',
          'Avisos de GamingSocial',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Pregunta una sola vez si quiere activar los avisos y, si dijo que sí,
  /// empieza a escuchar mensajes, comentarios y nuevos seguidores.
  static Future<void> start(BuildContext context, String uid) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    var answer = prefs?.getString('notif');
    if (answer == null) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!context.mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.notifications_active, size: 32),
          title: const Text('¿Activar notificaciones?'),
          content: const Text(
            'Te avisaremos cuando recibas un mensaje, un comentario, una '
            'respuesta o un nuevo seguidor. Puedes cambiarlo cuando quieras '
            'en los ajustes de tu teléfono o navegador.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Activar'),
            ),
          ],
        ),
      );
      if (yes == true) {
        final ok = await _request();
        answer = ok ? 'yes' : 'no';
      } else {
        answer = 'no';
      }
      await prefs?.setString('notif', answer);
    }
    if (answer != 'yes') return;
    if (!kIsWeb) await _init();
    _listen(uid);
  }

  static void stop() {
    final c = _ch;
    _ch = null;
    if (c != null) {
      try {
        sb.removeChannel(c);
      } catch (_) {}
    }
  }

  static void _listen(String uid) {
    stop();
    try {
      _ch = sb
          .channel('notif_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (p) async {
              final r = p.newRecord;
              if (r['sender_id'] == uid) return;
              final from = await Db.profileOf('${r['sender_id']}');
              _show('Mensaje de @${from?['username'] ?? 'alguien'}',
                  '${r['text'] ?? ''}');
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'comments',
            callback: (p) async {
              final r = p.newRecord;
              if (r['author_id'] == uid) return;
              final who = '@${r['author_name'] ?? 'alguien'}';
              if (r['reply_to_name'] == Session.i.username &&
                  Session.i.username.isNotEmpty) {
                _show('$who respondió tu comentario', '${r['text'] ?? ''}');
                return;
              }
              try {
                final post = await sb
                    .from('posts')
                    .select('author_id')
                    .eq('id', r['post_id'])
                    .maybeSingle();
                if (post?['author_id'] == uid) {
                  _show('$who comentó tu publicación', '${r['text'] ?? ''}');
                }
              } catch (_) {}
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'follows',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'following_id',
              value: uid,
            ),
            callback: (p) async {
              final from = await Db.profileOf('${p.newRecord['follower_id']}');
              _show('Nuevo seguidor',
                  '@${from?['username'] ?? 'alguien'} empezó a seguirte');
            },
          )
          .subscribe();
    } catch (_) {}
  }
}

/// Revisa cada pocos minutos si hay una versión nueva de la app.
/// En la web se recarga sola; en Android avisa y abre la descarga.
class Updater {
  Updater._();
  static Timer? _timer;
  static String? _prompted;

  static void start(BuildContext Function() ctx) {
    if (kAppVersion == 'dev') return;
    _timer?.cancel();
    Future<void>.delayed(const Duration(seconds: 6), () => _check(ctx));
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _check(ctx));
  }

  static void stop() => _timer?.cancel();

  static Future<void> _check(BuildContext Function() ctx) async {
    try {
      if (kIsWeb) {
        final r = await http
            .get(Uri.base.resolve('version.json?t=${DateTime.now().millisecondsSinceEpoch}'))
            .timeout(const Duration(seconds: 10));
        final v = (jsonDecode(r.body) as Map)['v']?.toString();
        if (v == null || v == kAppVersion) return;
        final c = ctx();
        if (!c.mounted) return;
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(
          content: Text('Hay una versión nueva. Actualizando…'),
        ));
        await Future<void>.delayed(const Duration(seconds: 2));
        reloadPage();
      } else {
        final r = await http
            .get(Uri.parse('https://api.github.com/repos/$_repo/releases/tags/apk-latest'))
            .timeout(const Duration(seconds: 10));
        final body = (jsonDecode(r.body) as Map)['body']?.toString() ?? '';
        final m = RegExp(r'version:([0-9a-f]{40})').firstMatch(body);
        final v = m?.group(1);
        if (v == null || v == kAppVersion || v == _prompted) return;
        _prompted = v;
        final c = ctx();
        if (!c.mounted) return;
        final yes = await showDialog<bool>(
          context: c,
          builder: (d) => AlertDialog(
            icon: const Icon(Icons.system_update, size: 32),
            title: const Text('Hay una versión nueva'),
            content: const Text(
              'Se descargará la app actualizada. Al terminar, ábrela para '
              'instalarla (se conservan tu cuenta y tus datos).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Después'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Actualizar'),
              ),
            ],
          ),
        );
        if (yes == true) {
          await launchUrl(
            Uri.parse('https://github.com/$_repo/releases/download/apk-latest/GamingSocial.apk'),
            mode: LaunchMode.externalApplication,
          );
        }
      }
    } catch (_) {
      // Sin internet o sin acceso a GitHub: se intenta otra vez más tarde.
    }
  }
}
