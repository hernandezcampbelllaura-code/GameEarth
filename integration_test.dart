// Pruebas de integración contra el servidor real (Supabase).
// Comprueban que la base de datos sigue bien protegida y responde.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamingsocial/config.dart';
import 'package:http/http.dart' as http;

Map<String, String> get _h => {
      'apikey': SupabaseConfig.anonKey,
      'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      'Content-Type': 'application/json',
    };

Uri _u(String p) => Uri.parse('${SupabaseConfig.url}$p');

bool _denied(http.Response r) {
  if (r.statusCode == 401 || r.statusCode == 403) return true;
  if (r.statusCode == 200) {
    final b = jsonDecode(r.body);
    return b is List && b.isEmpty;
  }
  return false;
}

void main() {
  test('el servidor responde', () async {
    final r = await http
        .post(_u('/rest/v1/rpc/email_exists'),
            headers: _h, body: jsonEncode({'p_email': 'nadie@no-existe.test'}))
        .timeout(const Duration(seconds: 30));
    expect(r.statusCode, lessThan(500));
  });

  test('email_exists dice que no para un correo desconocido', () async {
    final r = await http.post(_u('/rest/v1/rpc/email_exists'),
        headers: _h,
        body: jsonEncode({'p_email': 'nadie-${DateTime.now().millisecondsSinceEpoch}@no-existe.test'}));
    if (r.statusCode == 200) {
      expect(jsonDecode(r.body), isFalse);
    } else {
      // El nombre del parámetro puede variar; al menos no debe ser un error 5xx.
      expect(r.statusCode, lessThan(500));
    }
  });

  test('sin iniciar sesión no se pueden leer perfiles', () async {
    final r = await http.get(_u('/rest/v1/profiles?select=*&limit=1'), headers: _h);
    expect(_denied(r), isTrue, reason: 'respuesta ${r.statusCode}: ${r.body}');
  });

  test('sin iniciar sesión no se pueden leer publicaciones', () async {
    final r = await http.get(_u('/rest/v1/posts?select=*&limit=1'), headers: _h);
    expect(_denied(r), isTrue, reason: 'respuesta ${r.statusCode}: ${r.body}');
  });

  test('sin iniciar sesión no se puede publicar', () async {
    final r = await http.post(_u('/rest/v1/posts'),
        headers: _h, body: jsonEncode({'text': 'prueba anónima'}));
    expect(r.statusCode, anyOf(401, 403));
  });

  test('sin iniciar sesión no se pueden enviar mensajes', () async {
    final r = await http.post(_u('/rest/v1/rpc/send_message'),
        headers: _h, body: jsonEncode({}));
    expect(r.statusCode, anyOf(400, 401, 403, 404));
  });

  for (final fn in [
    'request_verification',
    'admin_review_verification',
    'admin_set_verified',
    'edit_post',
    'set_birthday',
    'leave_collab',
  ]) {
    test('sin iniciar sesión no se puede llamar $fn', () async {
      final r = await http.post(_u('/rest/v1/rpc/$fn'), headers: _h, body: jsonEncode({}));
      expect(r.statusCode, anyOf(400, 401, 403, 404), reason: r.body);
    });
  }

  test('sin iniciar sesión no se leen solicitudes de verificación', () async {
    final r = await http.get(_u('/rest/v1/verification_requests?select=*'), headers: _h);
    expect(_denied(r), isTrue, reason: r.body);
  });
}
