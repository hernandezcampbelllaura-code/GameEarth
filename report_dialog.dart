import 'package:flutter/material.dart';

import '../services/db.dart';

/// Diálogo para denunciar una publicación ('post'), un comentario
/// ('comment', hay que pasar [postId]) o un usuario ('user').
Future<void> showReportDialog(
  BuildContext context, {
  required String type,
  required String targetId,
  required String ownerId,
  String? postId,
  String preview = '',
}) async {
  const reasons = [
    'Spam',
    'Acoso o discurso de odio',
    'Contenido sexual',
    'Violencia',
    'Otro',
  ];
  String? selected;
  final messenger = ScaffoldMessenger.of(context);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          type == 'post'
              ? 'Denunciar publicación'
              : type == 'comment'
                  ? 'Denunciar comentario'
                  : 'Denunciar usuario',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in reasons)
              ListTile(
                dense: true,
                title: Text(r),
                leading: Icon(
                  selected == r
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => setState(() => selected = r),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    ),
  );

  if (ok == true && selected != null) {
    try {
      await Db.report(
        type: type,
        targetId: targetId,
        ownerId: ownerId,
        reason: selected!,
        postId: postId,
        preview: preview,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Gracias, revisaremos la denuncia.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
    }
  }
}
