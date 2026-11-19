import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 72, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                'Tu cuenta fue suspendida',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Infringiste las normas de la comunidad.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => showContactDialog(context),
                icon: const Icon(Icons.mail_outline),
                label: const Text('¿No estás de acuerdo? Escríbenos'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => sb.auth.signOut(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
