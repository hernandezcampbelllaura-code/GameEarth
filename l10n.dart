import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n_data.dart';

/// Idiomas disponibles: código, nombre en su propio idioma.
const List<List<String>> kLanguages = [
  ['es', 'Español'],
  ['es_ES', 'Español (España)'],
  ['en', 'English'],
  ['en_GB', 'English (UK)'],
  ['fr', 'Français'],
  ['pt', 'Português'],
  ['de', 'Deutsch'],
  ['ru', 'Русский'],
];

const List<Locale> kSupportedLocales = [
  Locale('es'),
  Locale('es', 'ES'),
  Locale('en'),
  Locale('en', 'GB'),
  Locale('fr'),
  Locale('pt'),
  Locale('de'),
  Locale('ru'),
];

class L {
  static final ValueNotifier<String> code = ValueNotifier<String>('es');

  static Locale get locale {
    final c = code.value;
    return c.contains('_')
        ? Locale(c.split('_')[0], c.split('_')[1])
        : Locale(c);
  }

  /// Código a partir del idioma del teléfono.
  static String detect(Locale l) {
    final lc = l.languageCode.toLowerCase();
    final cc = (l.countryCode ?? '').toUpperCase();
    if (lc == 'es') return cc == 'ES' ? 'es_ES' : 'es';
    if (lc == 'en') {
      return const ['GB', 'IE', 'AU', 'NZ', 'ZA', 'IN'].contains(cc)
          ? 'en_GB'
          : 'en';
    }
    if (const ['fr', 'pt', 'de', 'ru'].contains(lc)) return lc;
    return 'en';
  }

  static bool valid(String c) => kLanguages.any((e) => e[0] == c);

  /// Carga el idioma guardado o el del teléfono.
  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString('lang');
      if (saved != null && valid(saved)) {
        code.value = saved;
        return;
      }
    } catch (_) {}
    code.value = detect(PlatformDispatcher.instance.locale);
  }

  static Future<void> set(String c) async {
    if (!valid(c)) return;
    code.value = c;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('lang', c);
    } catch (_) {}
  }

  /// Idioma base (es, en, fr, pt, de, ru).
  static String get base => code.value.split('_')[0];
}

const Map<String, int> _idx = {'en': 0, 'fr': 1, 'pt': 2, 'de': 3, 'ru': 4};

final List<List<Object>> _ukRules = [
  [RegExp(r'\bfavorite'), 'favourite'],
  [RegExp(r'\bFavorite'), 'Favourite'],
  [RegExp(r'\bcolor'), 'colour'],
  [RegExp(r'\bCenter\b'), 'Centre'],
  [RegExp(r'\bgray\b'), 'grey'],
];

final List<List<Object>> _esRules = [
  [RegExp(r'\bToca\b'), 'Pulsa'],
  [RegExp(r'\btoca\b'), 'pulsa'],
  [RegExp(r'\bCalifica\b'), 'Valora'],
  [RegExp(r'\bcalifica\b'), 'valora'],
  [RegExp(r'\bcalificación\b'), 'valoración'],
  [RegExp(r'\bestoy enojada\b', caseSensitive: false), 'estoy enfadada'],
  [RegExp(r'\bEstoy enojada\b'), 'Estoy enfadada'],
  [RegExp(r'\bVideo\b'), 'Vídeo'],
  [RegExp(r'\bvideo\b'), 'vídeo'],
  [RegExp(r'\bvideos\b'), 'vídeos'],
  [RegExp(r'\bcelular\b'), 'móvil'],
  [RegExp(r'\bcomputadora\b'), 'ordenador'],
];

String _apply(String s, List<List<Object>> rules) {
  for (final r in rules) {
    s = s.replaceAll(r[0] as RegExp, r[1] as String);
  }
  return s;
}

/// Traduce un texto escrito en español al idioma elegido.
/// Si no hay traducción, devuelve el original.
String tr(String es) {
  final c = L.code.value;
  if (c == 'es') return es;
  if (c == 'es_ES') return _apply(es, _esRules);
  final row = kTr[es];
  if (row == null) return es;
  final i = _idx[L.base]!;
  final s = row[i];
  return c == 'en_GB' ? _apply(s, _ukRules) : s;
}

/// Traduce una plantilla con marcadores {a}, {n}… y los rellena.
String trf(String template, Map<String, Object?> args) {
  var s = tr(template);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

InlineSpan _span(InlineSpan s) {
  if (s is TextSpan) {
    return TextSpan(
      text: s.text == null ? null : tr(s.text!),
      children: s.children?.map(_span).toList(),
      style: s.style,
      recognizer: s.recognizer,
      semanticsLabel: s.semanticsLabel,
    );
  }
  return s;
}

/// Reemplaza al Text de Flutter: traduce el texto al construirse.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
    this.textScaler,
    this.strutStyle,
  }) : textSpan = null;

  const Text.rich(
    this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
    this.textScaler,
    this.strutStyle,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;
  final TextScaler? textScaler;
  final StrutStyle? strutStyle;

  @override
  Widget build(BuildContext context) {
    if (textSpan != null) {
      return m.Text.rich(
        _span(textSpan!),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        semanticsLabel: semanticsLabel,
        textScaler: textScaler,
        strutStyle: strutStyle,
      );
    }
    return m.Text(
      tr(data ?? ''),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      semanticsLabel: semanticsLabel,
      textScaler: textScaler,
      strutStyle: strutStyle,
    );
  }
}

/// Selector de idioma (hoja inferior).
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: m.Text(tr('Elige tu idioma'), style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final e in kLanguages)
            ListTile(
              title: m.Text(e[1]),
              trailing: L.code.value == e[0] ? const Icon(Icons.check) : null,
              onTap: () {
                L.set(e[0]);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}

String languageName(String code) =>
    kLanguages.firstWhere((e) => e[0] == code, orElse: () => kLanguages[0])[1];
