/// Datos de tu proyecto de Supabase (la base de datos y las cuentas).
/// La clave "anon" es pública por diseño: la seguridad está en la base de datos.
class SupabaseConfig {
  static const String url = 'https://zagkwwrbfxdbcnevqovr.supabase.co';

  /// Ruta alternativa para lugares donde supabase.co está bloqueado (Cuba):
  /// un sitio de Netlify que reenvía las peticiones al mismo Supabase.
  /// Si está vacío o no responde, se usa la dirección normal.
  static const String proxyUrl = 'https://gamingsocial-gs.netlify.app';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InphZ2t3d3JiZnhkYmNuZXZxb3ZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUxMjE1ODMsImV4cCI6MjExMDY5NzU4M30.pHSNrtbIgjE_L3XFB4x9VoUrd26PUrgDp_XsUQI1v5E';
}

/// Dirección de la versión web (los enlaces compartidos apuntan aquí).
const String kWebUrl = 'https://hernandezcampbelllaura-code.github.io/GameEarth/';

/// Datos de Cloudinary: el almacén gratuito donde se guardan las fotos y los
/// videos que la gente sube desde su galería. Ninguno de los dos es secreto.
class MediaConfig {
  static const String cloudName = 'hagnq5mv';
  static const String uploadPreset = 'gamingsocial';

  static bool get ready =>
      !cloudName.startsWith('PEGA_AQUI') &&
      !uploadPreset.startsWith('PEGA_AQUI');
}

/// Opiniones (estrellas): siempre se guardan en la base de datos y las ves en
/// el panel de Admin. Si pegas aquí el enlace de un formulario de Formspree
/// (https://formspree.io/f/xxxxxxxx), cada opinión además llega a tu Gmail.
class FeedbackConfig {
  static const String emailFormUrl = '';
}
