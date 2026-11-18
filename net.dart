import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Estado de la conexión a internet (conectado / sin conexión / recuperada).
class Net {
  Net._();
  static final Net i = Net._();

  final ValueNotifier<bool> online = ValueNotifier<bool>(true);
  final ValueNotifier<bool> justRecovered = ValueNotifier<bool>(false);
  bool _wasOffline = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    if (_sub != null) return;
    try {
      final c = Connectivity();
      _apply(await c.checkConnectivity());
      _sub = c.onConnectivityChanged.listen(_apply);
    } catch (_) {
      // Si no se puede saber, se asume que hay conexión.
    }
  }

  void _apply(List<ConnectivityResult> r) {
    final on = r.any((e) => e != ConnectivityResult.none);
    if (on == online.value) return;
    online.value = on;
    _timer?.cancel();
    if (!on) {
      _wasOffline = true;
      justRecovered.value = false;
    } else if (_wasOffline) {
      _wasOffline = false;
      justRecovered.value = true;
      _timer = Timer(const Duration(seconds: 4), () {
        justRecovered.value = false;
      });
    }
  }
}

/// Franja de aviso arriba de toda la app: "Sin conexión" o "Conexión recuperada".
class ConnectionBanner extends StatelessWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: Net.i.online,
          builder: (context, online, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: Net.i.justRecovered,
              builder: (context, recovered, _) {
                if (online && !recovered) return const SizedBox.shrink();
                final color =
                    online ? const Color(0xFF1B8A4B) : const Color(0xFFB3261E);
                return Material(
                  color: color,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            online ? Icons.wifi : Icons.wifi_off,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              online
                                  ? 'Conexión recuperada'
                                  : 'Sin conexión a internet',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Puntito + texto pequeño: "Conectado" o "Sin conexión".
class ConnectionDot extends StatelessWidget {
  const ConnectionDot({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Net.i.online,
      builder: (context, online, _) {
        final color = online ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              online ? 'Conectado' : 'Sin conexión',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        );
      },
    );
  }
}

/// Si no hay internet muestra un cartel y devuelve false.
Future<bool> requireOnline(BuildContext context, String action) async {
  if (Net.i.online.value) return true;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.wifi_off, size: 32),
      title: const Text('No estás conectado'),
      content: Text(
        'No puedes $action sin internet. Cuando vuelva la conexión te '
        'avisaremos y podrás intentarlo de nuevo.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
  return false;
}
