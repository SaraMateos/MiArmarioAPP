import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';

class OutfitImageService {
  static Future<Uint8List> render(
    WardrobeRepository repo,
    Outfit outfit,
    List<Garment> all,
  ) async {
    final pieces = orderedGarments(
      all.where((g) => outfit.items.any((i) => i.garmentId == g.id)),
    );
    if (pieces.isEmpty) {
      throw const FormatException('El outfit no tiene prendas para exportar.');
    }
    const width = 1200, columns = 3;
    final rows = (pieces.length / columns).ceil();
    final height = 180 + rows * 450;
    final recorder = ui.PictureRecorder(), loaded = <ui.Image>[];
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xfffaf8f4), BlendMode.src);
    void label(
      String text,
      Offset point,
      double size,
      double maxWidth, {
      bool bold = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            color: const Color(0xff243e34),
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      painter.paint(canvas, point);
      painter.dispose();
    }

    try {
      label(outfit.name, const Offset(40, 35), 40, 1120, bold: true);
      label(outfit.occasion, const Offset(40, 95), 25, 1120);
      for (var i = 0; i < pieces.length; i++) {
        final g = pieces[i];
        final codec = await ui.instantiateImageCodec(
          await File(repo.photoPath(g.photo)).readAsBytes(),
          targetWidth: 650,
        );
        late ui.Image image;
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
        loaded.add(image);
        final x = 40.0 + (i % columns) * 390, y = 160.0 + (i ~/ columns) * 450;
        final scale = min(350 / image.width, 330 / image.height),
            w = image.width * scale,
            h = image.height * scale;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 350, 425),
            const Radius.circular(20),
          ),
          Paint()..color = Colors.white,
        );
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(x + (350 - w) / 2, y + (330 - h) / 2, w, h),
          Paint()..filterQuality = FilterQuality.high,
        );
        label(g.name, Offset(x + 14, y + 335), 24, 322, bold: true);
        label(
          '${roleOf(g)}${roleOf(g) == 'Parte superior' ? ' · ${layerOf(g)}' : ''}',
          Offset(x + 14, y + 392),
          18,
          322,
        );
      }
      final picture = recorder.endRecording();
      late ui.Image image;
      try {
        image = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw const FormatException('No se ha podido generar la imagen.');
        }
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      for (final image in loaded) {
        image.dispose();
      }
    }
  }

  static Future<void> export(
    BuildContext context,
    WardrobeRepository repo,
    Outfit outfit,
    List<Garment> garments,
  ) async {
    try {
      final bytes = await render(repo, outfit, garments);
      final filename = outfit.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9áéíóúñÁÉÍÓÚÑ_-]'),
        '_',
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar imagen del outfit',
        fileName: '$filename.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: bytes,
      );
      if (context.mounted && path != null) {
        message(
          context,
          'Imagen guardada. Puedes compartirla desde Archivos o la galería.',
        );
      }
    } catch (e) {
      if (context.mounted) message(context, errorMessage(e));
    }
  }
}
