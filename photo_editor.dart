import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n.dart';
import 'package:image_picker/image_picker.dart';

import '../services/db.dart';

/// Pregunta "Cámara o Galería", y luego deja recortar la foto antes de usarla.
/// Devuelve null si la persona cancela.
Future<PickedMedia?> pickPhotoWithEditor(
  BuildContext context, {
  bool circle = false,
  double? aspectRatio,
  double maxWidth = 1280,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Tomar foto con la cámara'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  final picked = await Media.pickImage(maxWidth: maxWidth, source: source);
  if (picked == null || !context.mounted) return null;
  final bytes = await picked.bytes;
  if (!context.mounted) return null;

  final cropped = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          PhotoCropScreen(bytes: bytes, circle: circle, aspectRatio: aspectRatio),
    ),
  );
  if (cropped == null) return null;
  return PickedMedia.fromBytes(cropped, 'foto.png');
}

/// Pantalla para recortar: mueve las esquinas, usa dos dedos para acercar.
class PhotoCropScreen extends StatefulWidget {
  final Uint8List bytes;
  final bool circle;
  final double? aspectRatio;
  const PhotoCropScreen({
    super.key,
    required this.bytes,
    this.circle = false,
    this.aspectRatio,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _controller = CropController();
  bool _busy = false;
  double? _ratio;

  @override
  void initState() {
    super.initState();
    _ratio = widget.circle ? 1 : widget.aspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Recortar foto'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    _controller.crop();
                  },
            child: const Text('Listo'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.bytes,
              controller: _controller,
              aspectRatio: _ratio,
              withCircleUi: widget.circle,
              baseColor: Colors.black,
              maskColor: Colors.black54,
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure():
                    setState(() => _busy = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No se pudo recortar.')),
                    );
                }
              },
            ),
          ),
          if (!widget.circle)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final o in const [
                      ['Libre', null],
                      ['1:1', 1.0],
                      ['4:3', 4 / 3],
                      ['16:9', 16 / 9],
                    ])
                      ChoiceChip(
                        label: Text(o[0] as String),
                        selected: _ratio == o[1],
                        onSelected: (_) {
                          setState(() => _ratio = o[1] as double?);
                          _controller.aspectRatio = _ratio;
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
