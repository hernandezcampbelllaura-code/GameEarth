import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Pide permiso de notificaciones al navegador (hay que llamarlo desde un toque).
Future<bool> webRequestPermission() async {
  try {
    final r = await web.Notification.requestPermission().toDart;
    return r.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

bool webPermissionGranted() {
  try {
    return web.Notification.permission == 'granted';
  } catch (_) {
    return false;
  }
}

void webShow(String title, String body) {
  try {
    web.Notification(title, web.NotificationOptions(body: body));
  } catch (_) {}
}

/// Recarga la página para tomar la versión nueva (máximo una vez cada 2 minutos).
bool reloadPage() {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = int.tryParse(web.window.sessionStorage.getItem('gs_reload') ?? '') ?? 0;
    if (now - last < 120000) return false;
    web.window.sessionStorage.setItem('gs_reload', '$now');
    web.window.location.reload();
    return true;
  } catch (_) {
    return false;
  }
}
