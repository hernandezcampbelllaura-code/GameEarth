import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../net.dart';
import '../safety.dart';
import '../services/db.dart';
import '../widgets/photo_editor.dart';
import 'search_screen.dart';
import '../util.dart';

class CreateScreen extends StatefulWidget {
  /// Se llama al publicar, con el id de la publicación y si es un video.
  final void Function(String postId, bool isVideo) onDone;
  final String groupId; // '' = publicación normal
  const CreateScreen({super.key, required this.onDone, this.groupId = ''});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _text = TextEditingController();
  final _link = TextEditingController();
  final _desc = TextEditingController();
  bool _poll = false;
  final List<TextEditingController> _opts = [
    TextEditingController(),
    TextEditingController(),
  ];
  PickedMedia? _media;
  String _collabId = '';
  String _collabName = '';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    _desc.dispose();
    for (final o in _opts) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool video) async {
    try {
      PickedMedia? m;
      if (video) {
        final src = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.videocam),
                  title: const Text('Grabar video con la cámara'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.video_library),
                  title: const Text('Elegir de la galería'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        if (src == null) return;
        m = await Media.pickVideo(source: src);
      } else {
        m = await pickPhotoWithEditor(context);
      }
      if (m != null && mounted) setState(() => _media = m);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _publish() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      toast(context, 'Escribe una descripción para publicar.');
      return;
    }
    final rawLink = _link.text.trim();
    final link = cleanUrl(rawLink);
    if (rawLink.isNotEmpty && link.isEmpty) {
      toast(context, 'El enlace no es válido. Ejemplo: https://youtube.com');
      return;
    }
    final options = _poll
        ? _opts.map((o) => o.text.trim()).where((o) => o.isNotEmpty).toList()
        : <String>[];
    if (_poll && options.length < 2) {
      toast(context, 'La votación necesita al menos 2 opciones.');
      return;
    }
    if (!await requireOnline(context, 'publicar')) return;
    if (!mounted) return;
    if (!Safety.check(context, [text, _desc.text, ...options, _link.text])) {
      return;
    }
    final w = RateLimit.wait('post', 15);
    if (w > 0) {
      toast(context, 'Espera $w s antes de publicar otra vez.');
      return;
    }
    setState(() => _busy = true);
    try {
      var image = '';
      var video = '';
      final m = _media;
      if (m != null) {
        final url = await Media.upload(m);
        if (m.isVideo) {
          video = url;
        } else {
          image = url;
        }
      }
      final newId = await Db.createPost(
        text,
        image,
        videoUrl: video,
        linkUrl: link,
        groupId: widget.groupId,
        description: _desc.text.trim(),
        pollOptions: options,
        collabId: _collabId,
      );
      _text.clear();
      _link.clear();
      _desc.clear();
      for (final o in _opts) {
        o.clear();
      }
      _poll = false;
      _collabId = '';
      _collabName = '';
      if (mounted) {
        setState(() => _media = null);
        toast(context, 'Publicado');
        widget.onDone(newId, m != null && m.isVideo);
      }
    } catch (e) {
      if (mounted) toast(context, 'No se pudo publicar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(PickedMedia m) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: m.isVideo
              ? Container(
                  height: 140,
                  width: double.infinity,
                  color: const Color(0xFF141A2B),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam, size: 44),
                      SizedBox(height: 8),
                      Text('Video listo para subir'),
                    ],
                  ),
                )
              : FutureBuilder<Uint8List>(
                  future: m.bytes,
                  builder: (context, snap) => snap.hasData
                      ? Image.memory(
                          snap.data!,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : const SizedBox(
                          height: 220,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton.filled(
            onPressed: _busy ? null : () => setState(() => _media = null),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _media;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupId.isEmpty ? 'Nueva publicación' : 'Publicar en el grupo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            maxLength: 500,
            maxLines: 6,
            minLines: 4,
            decoration: InputDecoration(
              hintText: tr('¿Qué está pasando en tu partida?'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _desc,
            maxLength: 500,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              labelText: tr('Descripción (opcional, se ve en Reels)'),
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: tr('Enlace (opcional)'),
              hintText: tr('https://…'),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.group_add_outlined),
            title: Text(
              _collabId.isEmpty
                  ? 'Colaboración (opcional)'
                  : 'En colaboración con @$_collabName',
            ),
            subtitle: const Text(
              'Aparecerá también en el perfil de la otra persona',
            ),
            trailing: _collabId.isEmpty
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _collabId = '';
                      _collabName = '';
                    }),
                  ),
            onTap: _busy
                ? null
                : () async {
                    final r = await Navigator.push<List<String>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SearchScreen(pick: true),
                      ),
                    );
                    if (r != null && mounted) {
                      setState(() {
                        _collabId = r[0];
                        _collabName = r[1];
                      });
                    }
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Agregar votación'),
            subtitle: const Text('La gente vota y ve el porcentaje de cada opción'),
            value: _poll,
            onChanged: _busy ? null : (v) => setState(() => _poll = v),
          ),
          if (_poll) ...[
            for (var i = 0; i < _opts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _opts[i],
                        maxLength: 60,
                        decoration: InputDecoration(
                          labelText: 'Opción ${i + 1}',
                          counterText: '',
                        ),
                      ),
                    ),
                    if (_opts.length > 2)
                      IconButton(
                        tooltip: tr('Quitar opción'),
                        icon: const Icon(Icons.close),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _opts.removeAt(i).dispose()),
                      ),
                  ],
                ),
              ),
            if (_opts.length < 4)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(
                            () => _opts.add(TextEditingController()),
                          ),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar opción'),
                ),
              ),
          ],
          const SizedBox(height: 12),
          if (m != null) ...[
            _preview(m),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Foto'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(true),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('Video'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _publish,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_busy ? 'Publicando…' : 'Publicar'),
          ),
          if (_busy && m != null && m.isVideo)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Subiendo el video, puede tardar un poco. No cierres la app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
            ),
        ],
      ),
    );
  }
}
