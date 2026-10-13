import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'wardrobe_tools.dart';
import 'ui_common.dart';

class CutoutEditor extends StatefulWidget {
  final String path;
  final String? sourcePath;
  const CutoutEditor({super.key, required this.path, this.sourcePath});
  @override
  State<CutoutEditor> createState() => _CutoutEditorState();
}

class _CutoutEditorState extends State<CutoutEditor> {
  ui.Image? current, source;
  final strokes = <BrushStroke>[], redo = <BrushStroke>[];
  bool restore = false, busy = true, showSource = false;
  double size = 18;
  final transform = TransformationController();
  bool navigate = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<ui.Image> decode(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> load() async {
    try {
      final a = await decode(widget.path);
      final b = await decode(widget.sourcePath ?? widget.path);
      if (!mounted) {
        a.dispose();
        b.dispose();
        return;
      }
      current = a;
      source = b;
      if (a.width != b.width || a.height != b.height) {
        throw const FormatException('Las fotos no están alineadas.');
      }
    } catch (e) {
      error = errorMessage(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    transform.dispose();
    current?.dispose();
    source?.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final recorder = ui.PictureRecorder();
      paintCutout(ui.Canvas(recorder), current!, source!, strokes);
      final picture = recorder.endRecording();
      final image = await picture.toImage(current!.width, current!.height);
      picture.dispose();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw const FormatException('No se ha podido guardar el recorte.');
        }
        final folder = await getTemporaryDirectory();
        final path = '${folder.path}/brush_${const Uuid().v4()}.png';
        await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
        if (mounted) Navigator.pop(context, path);
      } finally {
        image.dispose();
      }
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Corregir recorte'),
        actions: [
          IconButton(
            tooltip: 'Deshacer',
            onPressed: busy || strokes.isEmpty
                ? null
                : () => setState(() => redo.add(strokes.removeLast())),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Rehacer',
            onPressed: busy || redo.isEmpty
                ? null
                : () => setState(() => strokes.add(redo.removeLast())),
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? Center(child: Text(error))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.sourcePath == null
                        ? 'Borra el fondo con el dedo. Recuperar repone píxeles de esta foto; los recortes antiguos sin original no permiten recuperar partes ya borradas.'
                        : 'Borra o recupera partes con el dedo. Vista original ayuda a situar los bordes.',
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final image = current!;
                      final scale =
                          (constraints.maxWidth / image.width <
                              constraints.maxHeight / image.height)
                          ? constraints.maxWidth / image.width
                          : constraints.maxHeight / image.height;
                      Offset point(Offset p) => Offset(
                        (p.dx / scale).clamp(0, image.width.toDouble()),
                        (p.dy / scale).clamp(0, image.height.toDouble()),
                      );
                      return InteractiveViewer(
                        transformationController: transform,
                        minScale: 1,
                        maxScale: 6,
                        panEnabled: navigate,
                        scaleEnabled: navigate,
                        child: Center(
                          child: SizedBox(
                            width: image.width * scale,
                            height: image.height * scale,
                            child: GestureDetector(
                              onPanStart: showSource || navigate
                                  ? null
                                  : (d) => setState(() {
                                      redo.clear();
                                      strokes.add(
                                        BrushStroke(
                                          [point(d.localPosition)],
                                          size /
                                              scale /
                                              transform.value
                                                  .getMaxScaleOnAxis(),
                                          restore,
                                        ),
                                      );
                                    }),
                              onPanUpdate: showSource || navigate
                                  ? null
                                  : (d) => setState(
                                      () => strokes.isEmpty
                                          ? null
                                          : strokes.last.points.add(
                                              point(d.localPosition),
                                            ),
                                    ),
                              child: CustomPaint(
                                painter: _CutoutPainter(
                                  image,
                                  source!,
                                  strokes,
                                  scale,
                                  showSource,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('Mover / ampliar'),
                              selected: navigate,
                              onSelected: (v) => setState(() => navigate = v),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.zoom_out_map),
                              label: const Text('Restablecer zoom'),
                              onPressed: () =>
                                  transform.value = Matrix4.identity(),
                            ),
                          ],
                        ),
                        const Text(
                          'Activa Mover / ampliar para arrastrar y ampliar con dos dedos. Desactívalo para pintar sobre el detalle.',
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Borrar'),
                              selected: !restore,
                              onSelected: (_) =>
                                  setState(() => restore = false),
                            ),
                            ChoiceChip(
                              label: const Text('Recuperar'),
                              selected: restore,
                              onSelected: (_) => setState(() => restore = true),
                            ),
                            FilterChip(
                              label: const Text('Vista original'),
                              selected: showSource,
                              onSelected: (v) => setState(() => showSource = v),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('Pincel'),
                            Expanded(
                              child: Slider(
                                value: size,
                                min: 3,
                                max: 45,
                                onChanged: (v) => setState(() => size = v),
                              ),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: save,
                          icon: const Icon(Icons.check),
                          label: const Text('Aplicar corrección'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

class _CutoutPainter extends CustomPainter {
  final ui.Image image, source;
  final List<BrushStroke> strokes;
  final double scale;
  final bool showSource;
  _CutoutPainter(
    this.image,
    this.source,
    this.strokes,
    this.scale,
    this.showSource,
  );
  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += 16) {
      for (var x = 0.0; x < size.width; x += 16) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 16, 16),
          Paint()
            ..color = ((x ~/ 16 + y ~/ 16) % 2 == 0
                ? const Color(0xffeeeeee)
                : const Color(0xffcccccc)),
        );
      }
    }
    canvas.save();
    canvas.scale(scale);
    if (showSource) {
      canvas.drawImage(source, Offset.zero, Paint());
    } else {
      paintCutout(canvas, image, source, strokes);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter old) => true;
}
