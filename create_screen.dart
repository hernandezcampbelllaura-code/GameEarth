import 'dart:io';

import 'package:flutter/material.dart';

import '../services/db.dart';
import '../util.dart';

class CreateScreen extends StatefulWidget {
  final VoidCallback onDone;
  const CreateScreen({super.key, required this.onDone});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _text = TextEditingController();
  PickedMedia? _media;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(bool video) async {
    try {
      final m = video ? await Media.pickVideo() : await Media.pickImage();
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
      await Db.createPost(text, image, videoUrl: video);
      _text.clear();
      if (mounted) {
        setState(() => _media = null);
        toast(context, 'Publicado');
        widget.onDone();
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
              : Image.file(
                  File(m.path),
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
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
      appBar: AppBar(title: const Text('Nueva publicación')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            maxLength: 500,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: '¿Qué está pasando en tu partida?',
            ),
          ),
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
