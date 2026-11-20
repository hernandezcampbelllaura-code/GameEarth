// Versión para el teléfono (Android): no hace nada en la parte web.
Future<bool> webRequestPermission() async => false;
bool webPermissionGranted() => false;
void webShow(String title, String body) {}
bool reloadPage() => false;
