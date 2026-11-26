import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'net.dart';
import 'notifier.dart';
import 'services/db.dart';
import 'screens/auth_screen.dart';
import 'screens/new_password_screen.dart';
import 'screens/banned_screen.dart';
import 'screens/home_shell.dart';
import 'screens/profile_setup_screen.dart';
import 'theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, AuthState, AuthChangeEvent;

/// La app se dibuja al instante (pantalla de inicio) y la conexión se prepara
/// por detrás, para que nunca se vea una pantalla en blanco.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L.init();
  runApp(const GamingSocialApp());
}

/// Elige por dónde hablar con Supabase: la dirección normal o, si está
/// bloqueada, la ruta alternativa (proxy). Recuerda la última que funcionó.
Future<String> _pickSupabaseUrl() async {
  const direct = SupabaseConfig.url;
  const proxy = SupabaseConfig.proxyUrl;
  if (proxy.isEmpty) return direct;
  Future<bool> up(String base) async {
    try {
      final r = await http
          .get(Uri.parse('$base/auth/v1/health'),
              headers: {'apikey': SupabaseConfig.anonKey})
          .timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String? last;
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    last = prefs.getString('sburl');
  } catch (_) {}
  final dUp = up(direct);
  final pUp = up(proxy);
  String chosen;
  if (last == proxy) {
    chosen = await pUp ? proxy : (await dUp ? direct : proxy);
  } else {
    chosen = await dUp ? direct : (await pUp ? proxy : direct);
  }
  try {
    await prefs?.setString('sburl', chosen);
  } catch (_) {}
  return chosen;
}

Future<void> _init() async {
  await Supabase.initialize(
    url: await _pickSupabaseUrl(),
    anonKey: SupabaseConfig.anonKey,
  );
  await Net.i.start();
}

class GamingSocialApp extends StatefulWidget {
  const GamingSocialApp({super.key});

  @override
  State<GamingSocialApp> createState() => _GamingSocialAppState();
}

class _GamingSocialAppState extends State<GamingSocialApp>
    with WidgetsBindingObserver {
  late Future<void> _ready = _init();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // La búsqueda de versión nueva funciona aunque no hayas podido iniciar
    // sesión (por ejemplo, si no hay conexión con el servidor).
    Future.delayed(const Duration(seconds: 4), () {
      Updater.start(() => _navKey.currentState!.overlay!.context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Updater.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L.code,
      builder: (context, code, _) => _buildApp(code),
    );
  }

  Widget _buildApp(String code) {
    return MaterialApp(
      key: ValueKey(code),
      locale: L.locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorKey: _navKey,
      title: 'GamersLore',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) =>
          ConnectionBanner(child: child ?? const SizedBox.shrink()),
      home: FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No se pudo iniciar: ${snap.error}'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => setState(() => _ready = _init()),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const _Loader();
          }
          return const AuthGate();
        },
      ),
    );
  }
}

class _Loader extends StatefulWidget {
  const _Loader();
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  bool _slow = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_esports, size: 64),
            const SizedBox(height: 8),
            const Text(
              'GamersLore',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            if (_slow) ...[
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Tu conexión está lenta. Sigue intentando…',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Decide qué pantalla mostrar: login, crear perfil, baneado o la app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _recovery = false;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery && mounted) {
        setState(() => _recovery = true);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovery) {
      return NewPasswordScreen(onDone: () => setState(() => _recovery = false));
    }
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, snap) {
        final user = sb.auth.currentUser;
        if (user == null) return const AuthScreen();
        return _ProfileGate(key: ValueKey(user.id), uid: user.id);
      },
    );
  }
}

class _ProfileGate extends StatefulWidget {
  final String uid;
  const _ProfileGate({super.key, required this.uid});

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Stream<Doc> _stream = Db.watchProfile(widget.uid);

  void _reload() => setState(() => _stream = Db.watchProfile(widget.uid));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Doc>(
      stream: _stream,
      builder: (context, ps) {
        if (ps.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error: ${ps.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => sb.auth.signOut(),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!ps.hasData) return const _Loader();
        final doc = ps.data!;
        if (!doc.exists) return ProfileSetupScreen(onSaved: _reload);
        if (doc.data()['banned'] == true) return const BannedScreen();
        return HomeShell(uid: widget.uid);
      },
    );
  }
}
