import 'package:firebase_core/firebase_core.dart';

/// Rellena estos 4 valores con los de tu proyecto de Firebase.
/// Los sacas del archivo google-services.json que descarga Firebase
/// (ver README.md, paso 4).
///
///   apiKey            -> client[0].api_key[0].current_key
///   appId             -> client[0].client_info.mobilesdk_app_id
///   messagingSenderId -> project_info.project_number
///   projectId         -> project_info.project_id
class AppFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PEGA_AQUI_TU_API_KEY',
    appId: 'PEGA_AQUI_TU_APP_ID',
    messagingSenderId: 'PEGA_AQUI_TU_PROJECT_NUMBER',
    projectId: 'PEGA_AQUI_TU_PROJECT_ID',
  );
}
