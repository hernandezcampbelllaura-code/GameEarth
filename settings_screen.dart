import 'package:flutter/material.dart';

import '../net.dart';
import '../services/db.dart';
import '../util.dart';
import 'help_screen.dart';

/// Engranaje: cuenta, cumpleaños, estadísticas, verificación y ayuda.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = sb.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(Session.i.username.isEmpty ? 'Mi cuenta' : '@${Session.i.username}'),
            subtitle: Text(email),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Estadísticas'),
            subtitle: const Text('De cada publicación y en total'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cake_outlined),
            title: const Text('Mi cumpleaños'),
            subtitle: const Text('Solo mayores de 18; tú decides si se ve'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BirthdayScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Cuenta verificada'),
            subtitle: const Text('Pide la insignia azul'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerificationScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Cambiar contraseña'),
            subtitle: const Text('Te enviamos un enlace a tu correo'),
            onTap: () async {
              if (!await requireOnline(context, 'cambiar la contraseña')) return;
              if (!context.mounted) return;
              await guard(context, () async {
                await sb.auth.resetPasswordForEmail(email);
                if (context.mounted) {
                  toast(context, 'Te enviamos un enlace a $email');
                }
              });
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Ayuda y preguntas'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Contacto'),
            onTap: () => showContactDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: () async {
              final ok = await confirmDialog(context, '¿Cerrar sesión?');
              if (!ok) return;
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              await sb.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Estadísticas

/// Suma de vistas, reacciones y comentarios de una lista de publicaciones.
Map<String, int> statsTotals(List<Doc> posts) {
  var views = 0, likes = 0, comments = 0;
  for (final p in posts) {
    final d = p.data();
    views += ((d['views'] ?? 0) as num).toInt();
    likes += ((d['likesCount'] ?? 0) as num).toInt();
    comments += ((d['commentsCount'] ?? 0) as num).toInt();
  }
  return {
    'posts': posts.length,
    'views': views,
    'likes': likes,
    'comments': comments,
  };
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<List<Doc>> _future = Db.myPosts();

  Widget _box(String label, int v) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Text('$v',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = Db.myPosts()),
          ),
        ],
      ),
      body: FutureBuilder<List<Doc>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final posts = snap.data!;
          if (posts.isEmpty) {
            return const Center(child: Text('Aún no has publicado nada.'));
          }
          final t = statsTotals(posts);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('En total', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                _box('Publicaciones', t['posts']!),
                _box('Vistas', t['views']!),
              ]),
              Row(children: [
                _box('Reacciones', t['likes']!),
                _box('Comentarios', t['comments']!),
              ]),
              const SizedBox(height: 8),
              const Text('Por publicación',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final p in posts)
                Card(
                  child: ListTile(
                    title: Text(
                      (p.data()['text'] ?? '') as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '👁 ${p.data()['views'] ?? 0}   '
                      '❤️ ${p.data()['likesCount'] ?? 0}   '
                      '💬 ${p.data()['commentsCount'] ?? 0}   ·   '
                      '${formatDate(p.data()['createdAt'])}',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Cumpleaños

class BirthdayScreen extends StatefulWidget {
  const BirthdayScreen({super.key});

  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

class _BirthdayScreenState extends State<BirthdayScreen> {
  DateTime? _date;
  bool _show = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Db.myBirthday().then((d) {
      if (mounted) {
        setState(() {
          _date = d;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Tu fecha de nacimiento',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!await requireOnline(context, 'guardar')) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await guard(context, () async {
      await Db.setBirthday(_date, _show);
      if (mounted) toast(context, 'Guardado');
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _date;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cumpleaños')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cake_outlined),
                  title: Text(d == null
                      ? 'Elegir fecha'
                      : '${d.day}/${d.month}/${d.year}'),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: _pick,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar en mi perfil'),
                  subtitle: const Text('Solo se ve el día y el mes, nunca el año'),
                  value: _show,
                  onChanged: (v) => setState(() => _show = v),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy || d == null ? null : _save,
                  child: const Text('Guardar'),
                ),
                if (d != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _date = null);
                            await guard(context, () => Db.setBirthday(null, false));
                            if (mounted) toast(context, 'Cumpleaños borrado');
                          },
                    child: const Text('Borrar mi cumpleaños'),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- Verificación

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _note = TextEditingController();
  late final Future<List<Doc>> _posts = Db.myPosts();
  late final Stream<Snap> _mine = Db.watchMyVerification();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!await requireOnline(context, 'enviar la solicitud')) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await guard(context, () async {
      await Db.requestVerification(_note.text.trim());
      if (mounted) toast(context, 'Solicitud enviada');
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta verificada')),
      body: FutureBuilder<List<Doc>>(
        future: _posts,
        builder: (context, ps) {
          if (!ps.hasData) {
            return ps.hasError
                ? Center(child: Text('Error: ${ps.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          final t = statsTotals(ps.data!);
          final okViews = t['views']! > 1000;
          final okLikes = t['likes']! > 100;
          return StreamBuilder<Snap>(
            stream: _mine,
            builder: (context, ms) {
              final last = (ms.data?.docs.isEmpty ?? true)
                  ? null
                  : ms.data!.docs.first.data();
              final status = last?['status'] as String?;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'La insignia azul ✔ aparece junto a tu nombre. Puedes pedirla '
                    'cuando tu contenido tenga más de 1000 vistas y más de 100 '
                    'reacciones en total.',
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(okViews ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: okViews ? Colors.green : null),
                    title: Text('Vistas: ${t['views']} / 1000'),
                  ),
                  ListTile(
                    leading: Icon(okLikes ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: okLikes ? Colors.green : null),
                    title: Text('Reacciones: ${t['likes']} / 100'),
                  ),
                  const SizedBox(height: 8),
                  if (status == 'approved')
                    const ListTile(
                      leading: Icon(Icons.verified, color: Colors.lightBlueAccent),
                      title: Text('¡Tu cuenta está verificada!'),
                    )
                  else if (status == 'pending')
                    const ListTile(
                      leading: Icon(Icons.hourglass_top),
                      title: Text('Solicitud enviada, en revisión.'),
                    )
                  else ...[
                    if (status == 'rejected')
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Tu última solicitud no fue aprobada.'),
                      ),
                    TextField(
                      controller: _note,
                      maxLength: 300,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje (opcional)',
                        hintText: 'Cuéntanos quién eres o qué contenido haces',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || !(okViews && okLikes) ? null : _send,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Pedir verificación'),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
