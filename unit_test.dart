import 'package:flutter_test/flutter_test.dart';
import 'package:gamingsocial/safety.dart';
import 'package:gamingsocial/util.dart';
import 'package:gamingsocial/config.dart';
import 'package:gamingsocial/services/db.dart';
import 'package:gamingsocial/widgets/reactions.dart';
import 'package:gamingsocial/screens/settings_screen.dart';

void main() {
  group('Safety.isBad (filtro de palabras)', () {
    test('acepta texto normal', () {
      expect(Safety.isBad('hola, ¿alguien juega Minecraft?'), isFalse);
      expect(Safety.isBad('mi computadora es nueva'), isFalse);
    });
    test('bloquea insultos', () {
      expect(Safety.isBad('hijo de puta'), isTrue);
    });
    test('bloquea con números y mayúsculas', () {
      expect(Safety.isBad('P0RN'), isTrue);
    });
  });

  group('RateLimit', () {
    test('la primera vez deja pasar y la segunda espera', () {
      final k = 'k${DateTime.now().microsecondsSinceEpoch}';
      expect(RateLimit.wait(k, 5), 0);
      expect(RateLimit.wait(k, 5), greaterThan(0));
    });
    test('claves distintas no se afectan', () {
      expect(RateLimit.wait('x1${DateTime.now().microsecond}', 5), 0);
      expect(RateLimit.wait('x2${DateTime.now().microsecond}', 5), 0);
    });
  });

  group('HumanCheck', () {
    test('acepta la suma correcta y rechaza otra', () {
      final h = HumanCheck();
      expect(h.ok('${h.a + h.b}'), isTrue);
      expect(h.ok(' ${h.a + h.b} '), isTrue);
      expect(h.ok('${h.a + h.b + 1}'), isFalse);
      expect(h.ok('abc'), isFalse);
    });
  });

  group('util', () {
    test('formatDate', () {
      expect(formatDate(null), 'ahora');
      expect(formatDate(DateTime.now()), 'ahora');
      expect(formatDate(DateTime.now().subtract(const Duration(minutes: 5))),
          'hace 5 min');
      expect(formatDate(DateTime.now().subtract(const Duration(hours: 3))),
          'hace 3 h');
    });
    test('cleanUrl', () {
      expect(cleanUrl(''), '');
      expect(cleanUrl('google.com'), 'https://google.com');
      expect(cleanUrl('http://a.com/x'), 'http://a.com/x');
      expect(cleanUrl('no es un enlace'), '');
      expect(cleanUrl('javascript:alert(1)'), '');
    });
    test('videoDownloadUrl fuerza la descarga solo en Cloudinary', () {
      expect(
        videoDownloadUrl('https://res.cloudinary.com/hagnq5mv/video/upload/v1/a.mp4'),
        'https://res.cloudinary.com/hagnq5mv/video/upload/fl_attachment/v1/a.mp4',
      );
      expect(videoDownloadUrl('https://otro.com/a.mp4'), 'https://otro.com/a.mp4');
    });
    test('postLink apunta a la web con el id', () {
      expect(postLink('abc-123'), '${kWebUrl}?post=abc-123');
      expect(postLink('abc-123').contains('abc-123'), isTrue);
    });
  });

  group('db: conversión de filas', () {
    test('snake_case pasa a camelCase', () {
      final d = docFromRow({'id': '1', 'author_name': 'Ana', 'likes_count': 3});
      expect(d.id, '1');
      expect(d.data()['authorName'], 'Ana');
      expect(d.data()['likesCount'], 3);
    });
    test('claves terminadas en At pasan a fecha', () {
      final d = docFromRow({'id': '1', 'created_at': '2026-01-02T03:04:05Z'});
      expect(d.data()['createdAt'], isA<DateTime>());
    });
    test('los chats reciben la lista de miembros', () {
      final d = docFromRow({'id': 'a_b', 'user_a': 'a', 'user_b': 'b'});
      expect(d.data()['members'], ['a', 'b']);
    });
  });

  group('comentarios con respuestas', () {
    Doc c(String id, [String? parent]) =>
        docFromRow({'id': id, 'parent_id': parent ?? ''});
    test('las respuestas van debajo de su comentario', () {
      final rows = threadComments([c('1'), c('2'), c('3', '1'), c('4', '1')]);
      expect(rows.map((e) => e.key.id).toList(), ['1', '3', '4', '2']);
      expect(rows.map((e) => e.value).toList(), [false, true, true, false]);
    });
    test('una respuesta huérfana se muestra como principal', () {
      final rows = threadComments([c('5', 'borrado')]);
      expect(rows.length, 1);
      expect(rows.first.value, isFalse);
    });
  });

  group('contador de reacciones', () {
    test('ordena de mayor a menor y omite ceros', () {
      final r = sortedReactions({'love': 2, 'like': 5, 'sad': 0, 'wow': 1});
      expect(r.map((e) => e.key).toList(), ['like', 'love', 'wow']);
      expect(r.first.value, 5);
    });
    test('entradas inválidas dan lista vacía', () {
      expect(sortedReactions(null), isEmpty);
      expect(sortedReactions('x'), isEmpty);
      expect(sortedReactions({}), isEmpty);
    });
  });

  group('estadísticas', () {
    test('suma vistas, reacciones y comentarios', () {
      final t = statsTotals([
        docFromRow({'id': '1', 'views': 10, 'likes_count': 2, 'comments_count': 1}),
        docFromRow({'id': '2', 'views': 5, 'likes_count': 3, 'comments_count': 0}),
      ]);
      expect(t['posts'], 2);
      expect(t['views'], 15);
      expect(t['likes'], 5);
      expect(t['comments'], 1);
    });
    test('sin publicaciones todo es cero', () {
      expect(statsTotals([])['views'], 0);
    });
  });
}
