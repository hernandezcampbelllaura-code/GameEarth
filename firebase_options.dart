import 'package:firebase_core/firebase_core.dart';

/// Datos de tu proyecto de Firebase (gamingsocial-f47ba).
class AppFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBjAyiQ_1R3_p0mNW3MZviyuve6tk3XdGo',
    appId: '1:779220140558:android:212b7ed94eccd19b07f25f',
    messagingSenderId: '779220140558',
    projectId: 'gamingsocial-f47ba',
    storageBucket: 'gamingsocial-f47ba.firebasestorage.app',
  );
}

/// Datos de Cloudinary: el almacén gratuito donde se guardan las fotos y los
/// videos que la gente sube desde su galería. Ninguno de los dos es secreto.
class MediaConfig {
  static const String cloudName = 'hagnq5mv';
  static const String uploadPreset = 'gamingsocial';

  static bool get ready =>
      !cloudName.startsWith('PEGA_AQUI') &&
      !uploadPreset.startsWith('PEGA_AQUI');
}
