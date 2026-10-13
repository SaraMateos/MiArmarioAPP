import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Encuadra solamente la vista: nunca modifica el fichero original.
/// Si el fondo no es suficientemente uniforme, conserva la foto completa.
class AutoFramedPhoto extends StatefulWidget {
  const AutoFramedPhoto(this.path, {super.key, this.padding = 0.07});
  final String path;
  final double padding;

  @override
  State<AutoFramedPhoto> createState() => _AutoFramedPhotoState();
}

class _AutoFramedPhotoState extends State<AutoFramedPhoto> {
  static final Map<String, Future<_FramedImage?>> _cache = {};
  late Future<_FramedImage?> _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AutoFramedPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  void _load() {
    // Cache limitado para evitar decodificar cada miniatura en cada scroll.
    if (_cache.length > 120) _cache.clear();
    _result = _cache.putIfAbsent(widget.path, () => _decode(widget.path));
  }

  static Future<_FramedImage?> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 400);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return _FramedImage(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
      final rgba = data.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      int index(int x, int y) => (y * width + x) * 4;
      final corners = [index(0, 0), index(width - 1, 0), index(0, height - 1), index(width - 1, height - 1)];
      final first = corners.first;
      bool similar(int a, int b, int tolerance) =>
          (rgba[a] - rgba[b]).abs() <= tolerance &&
          (rgba[a + 1] - rgba[b + 1]).abs() <= tolerance &&
          (rgba[a + 2] - rgba[b + 2]).abs() <= tolerance &&
          (rgba[a + 3] - rgba[b + 3]).abs() <= tolerance;
      // Solamente encuadrar si las esquinas son transparentes o tienen un
      // fondo casi uniforme. Un fondo fotográfico complejo no es recortable
      // de forma segura sin un segmentador.
      final transparent = corners.every((p) => rgba[p + 3] < 30);
      final uniform = corners.every((p) => similar(first, p, 24));
      if (!transparent && !uniform) {
        return _FramedImage(image, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      }
      int left = width, right = -1, top = height, bottom = -1;
      for (int y = 0; y < height; y += 2) {
        for (int x = 0; x < width; x += 2) {
          final p = index(x, y);
          final foreground = transparent
              ? rgba[p + 3] > 65
              : rgba[p + 3] > 65 && !similar(first, p, 38);
          if (foreground) {
            left = math.min(left, x);
            right = math.max(right, x);
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
      }
      if (right <= left || bottom <= top) {
        return _FramedImage(image, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      }
      // Ante detecciones improbables, priorizar que no se corte ropa.
      if ((right - left) * (bottom - top) < width * height * .015) {
        return _FramedImage(image, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      }
      const safety = 5.0;
      return _FramedImage(image, Rect.fromLTRB(
        math.max(0, left - safety), math.max(0, top - safety),
        math.min(width.toDouble(), right + 2 + safety),
        math.min(height.toDouble(), bottom + 2 + safety),
      ));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_FramedImage?>(
    future: _result,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: Icon(Icons.checkroom_outlined, color: Colors.grey));
      }
      return LayoutBuilder(builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _FramedPainter(snapshot.data!, widget.padding),
        );
      });
    },
  );
}

class _FramedImage {
  final ui.Image image;
  final Rect source;
  _FramedImage(this.image, this.source);
}

class _FramedPainter extends CustomPainter {
  final _FramedImage photo;
  final double padding;
  _FramedPainter(this.photo, this.padding);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = photo.source;
    final available = Size(size.width * (1 - padding * 2), size.height * (1 - padding * 2));
    final scale = math.min(available.width / rect.width, available.height / rect.height);
    final w = rect.width * scale;
    final h = rect.height * scale;
    final target = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
    canvas.drawImageRect(photo.image, rect, target, Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(covariant _FramedPainter oldDelegate) =>
      oldDelegate.photo != photo || oldDelegate.padding != padding;
}
