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
  final _image = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _text.text.trim();
    final img = _image.text.trim();
    if (text.isEmpty) {
      toast(context, 'Escribe algo para publicar.');
      return;
    }
    if (img.isNotEmpty && !img.startsWith('http')) {
      toast(context, 'El enlace de la imagen debe empezar con http');
      return;
    }
    setState(() => _busy = true);
    try {
      await Db.createPost(text, img);
      _text.clear();
      _image.clear();
      if (mounted) {
        toast(context, 'Publicado');
        widget.onDone();
      }
    } catch (e) {
      if (mounted) toast(context, 'No se pudo publicar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          TextField(
            controller: _image,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Enlace de imagen (opcional)',
              prefixIcon: Icon(Icons.image_outlined),
            ),
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
            label: const Text('Publicar'),
          ),
        ],
      ),
    );
  }
}
