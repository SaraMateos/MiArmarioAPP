import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'auto_framed_photo.dart';

void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String errorMessage(Object error) => error is FormatException
    ? error.message
    : 'No se ha podido completar la operación. Comprueba el espacio libre y vuelve a intentarlo.';
Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = 'Eliminar',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Widget choice(
  String label,
  String value,
  List<String> values,
  ValueChanged<String> onChanged,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: [
    Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 7),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    DropdownButtonFormField<String>(
      key: ValueKey('$label:$value:${values.join("|")}'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      items: values.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  ],
);

class Photo extends StatelessWidget {
  final String path;
  final BoxFit fit;
  const Photo(this.path, {super.key, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) => Image.file(
    File(path),
    fit: fit,
    cacheWidth: 650,
    errorBuilder: (context, error, stack) =>
        const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
  );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onAction;
  final String? action;
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onAction,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(subtitle, textAlign: TextAlign.center),
          if (onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

class OutfitBoard extends StatelessWidget {
  final WardrobeRepository repo;
  final List<Garment> garments;
  final List<OutfitItem> items;
  final int? selected;
  final bool allowZoom;
  final bool showFigure;
  final double? aspectRatio;
  final ValueChanged<int>? onSelect;
  final void Function(int, double, double)? onMove;
  const OutfitBoard({
    super.key,
    required this.repo,
    required this.garments,
    required this.items,
    this.selected,
    this.allowZoom = true,
    this.showFigure = false,
    this.aspectRatio,
    this.onSelect,
    this.onMove,
  });
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio ?? (showFigure ? 1.0 : .85),
    child: LayoutBuilder(
      builder: (context, box) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: const Color(0xffeeeae2),
            child: Stack(
              children: [
                if (items.isEmpty)
                  const Center(
                    child: Text('Añade prendas para crear tu outfit'),
                  ),
                Transform(
                  transform: _presentationTransform(box),
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _piece(context, box, i),
                    ],
                  ),
                ),
                if (allowZoom && onSelect == null && items.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Ver composición a pantalla completa',
                      icon: const Icon(Icons.fullscreen),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Composición del outfit'),
                            ),
                            body: LayoutBuilder(
                              builder: (c, bounds) => InteractiveViewer(
                                minScale: 1,
                                maxScale: 4,
                                child: Center(
                                  child: SizedBox(
                                    width: (bounds.maxHeight * .85).clamp(
                                      0.0,
                                      bounds.maxWidth,
                                    ),
                                    child: OutfitBoard(
                                      repo: repo,
                                      garments: garments,
                                      items: items,
                                      allowZoom: false,
                                      showFigure: showFigure,
                                      aspectRatio: aspectRatio,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Matrix4 _presentationTransform(BoxConstraints box) {
    if (onSelect != null || items.isEmpty) return Matrix4.identity();
    var left = box.maxWidth, top = box.maxHeight, right = 0.0, bottom = 0.0;
    for (final item in items) {
      if (!garments.any((g) => g.id == item.garmentId)) continue;
      final size = box.maxWidth * .52 * item.scale;
      final x = item.x * (box.maxWidth - size).clamp(0.0, double.infinity);
      final y = item.y * (box.maxHeight - size).clamp(0.0, double.infinity);
      if (x < left) left = x;
      if (y < top) top = y;
      if (x + size > right) right = x + size;
      if (y + size > bottom) bottom = y + size;
    }
    if (right <= left || bottom <= top) return Matrix4.identity();
    final sx = box.maxWidth / (right - left + 24);
    final sy = box.maxHeight / (bottom - top + 24);
    final zoom = (sx < sy ? sx : sy).clamp(1.0, 2.2);
    return Matrix4.diagonal3Values(zoom, zoom, 1)..setTranslationRaw(
      box.maxWidth / 2 - zoom * (left + right) / 2,
      box.maxHeight / 2 - zoom * (top + bottom) / 2,
      0,
    );
  }

  Widget _piece(BuildContext context, BoxConstraints box, int i) {
    final item = items[i];
    final found = garments.where((g) => g.id == item.garmentId);
    if (found.isEmpty) {
      return const SizedBox.shrink();
    }
    final size = box.maxWidth * .52 * item.scale;
    final maxX = (box.maxWidth - size).clamp(0.0, double.infinity);
    final maxY = (box.maxHeight - size).clamp(0.0, double.infinity);
    return Positioned(
      left: item.x * maxX,
      top: item.y * maxY,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: onSelect == null ? null : () => onSelect!(i),
        onPanStart: onMove == null ? null : (_) => onSelect?.call(i),
        onPanUpdate: onMove == null
            ? null
            : (details) => onMove!(
                i,
                maxX == 0 ? 0 : details.delta.dx / maxX,
                maxY == 0 ? 0 : details.delta.dy / maxY,
              ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected == i
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 0,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: AutoFramedPhoto(repo.photoPath(found.first.photo), padding: .035),
          ),
        ),
      ),
    );
  }
}

class MultiChoice extends StatelessWidget {
  final String label;
  final List<String> values, selected;
  final ValueChanged<List<String>> onChanged;
  final bool exclusiveAllYear;
  const MultiChoice({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.exclusiveAllYear = false,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in values)
            FilterChip(
              label: Text(v),
              selected: selected.contains(v),
              onSelected: (on) {
                final next = [...selected];
                if (on) {
                  if (exclusiveAllYear && v == 'Todo el año') {
                    next.clear();
                  } else if (exclusiveAllYear) {
                    next.remove('Todo el año');
                  }
                  next.add(v);
                } else {
                  next.remove(v);
                }
                if (next.isEmpty) {
                  message(context, 'Selecciona al menos una opción.');
                  return;
                }
                onChanged(next);
              },
            ),
        ],
      ),
    ],
  );
}
