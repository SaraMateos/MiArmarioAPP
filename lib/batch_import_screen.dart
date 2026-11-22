import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'garment_editor.dart';
import 'local_photo_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';

class BatchImportScreen extends StatefulWidget {
  final WardrobeRepository repo;
  final List<XFile> files;
  const BatchImportScreen({super.key, required this.repo, required this.files});
  @override
  State<BatchImportScreen> createState() => _BatchImportScreenState();
}

class _BatchPhoto {
  final XFile file;
  PhotoAnalysis? analysis;
  String? confirmedType, saveError;
  bool analyzed = false, saved = false, skipped = false;

  _BatchPhoto(this.file);

  String get type => confirmedType ?? analysis?.suggestedType ?? '';
  bool get needsReview =>
      confirmedType == null && (analysis?.needsTypeReview ?? true);
  bool get pending => !saved && !skipped;
}

class _BatchImportScreenState extends State<BatchImportScreen> {
  late final List<_BatchPhoto> photos = widget.files
      .map(_BatchPhoto.new)
      .toList();
  bool opening = false;
  String? progress;
  String season = seasons.first, occasion = occasions.first;
  bool get busy => opening || progress != null;

  Future<void> review(_BatchPhoto photo) async {
    if (busy || photo.saved) return;
    setState(() => opening = true);
    try {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => GarmentEditor(
            repo: widget.repo,
            recoveredPhoto: photo.file.path,
            batchMode: true,
            initialAnalysis: photo.analysis,
            initialSubtype: photo.confirmedType,
            initialSeason: season,
            initialOccasion: occasion,
          ),
        ),
      );
      if (result == true) {
        photo.saved = true;
        photo.skipped = false;
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> chooseType(_BatchPhoto photo) async {
    if (busy || !photo.pending) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Confirmar tipo de prenda')),
            for (final name in garmentTypes.keys)
              ListTile(
                title: Text(name),
                selected: name == photo.type,
                onTap: () => Navigator.pop(sheetContext, name),
              ),
          ],
        ),
      ),
    );
    if (type != null && mounted) setState(() => photo.confirmedType = type);
  }

  Future<void> analyze(_BatchPhoto photo) async {
    try {
      photo.analysis = await LocalPhotoService.analyze(photo.file.path);
    } catch (_) {
      // A failed detection still allows saving the photo for manual review.
      photo.analysis = null;
    }
    photo.analyzed = true;
  }

  Future<void> analyzeAll() async {
    final pending = photos.where((p) => p.pending && !p.analyzed).toList();
    if (busy || pending.isEmpty) return;
    try {
      for (var i = 0; i < pending.length; i++) {
        if (!mounted) return;
        setState(
          () => progress = 'Analizando foto ${i + 1} de ${pending.length}…',
        );
        await analyze(pending[i]);
      }
    } finally {
      if (mounted) setState(() => progress = null);
    }
  }

  Future<void> saveAll() async {
    final pending = photos.where((p) => p.pending).toList();
    if (busy || pending.isEmpty) return;
    try {
      for (var i = 0; i < pending.length; i++) {
        if (!mounted) return;
        final photo = pending[i];
        setState(
          () => progress = 'Guardando prenda ${i + 1} de ${pending.length}…',
        );
        if (!photo.analyzed) await analyze(photo);

        final suggestedColors = (photo.analysis?.colors ?? [])
            .where(colors.contains)
            .toSet()
            .toList();
        final category = photo.analysis?.category;
        final typeLabel = photo.type.isEmpty ? 'Prenda nueva' : photo.type;
        String? imported;
        try {
          imported = await widget.repo.importPhoto(photo.file.path);
          await widget.repo.saveGarment(
            Garment(
              id: const Uuid().v4(),
              name: suggestedColors.isEmpty
                  ? typeLabel
                  : '$typeLabel ${suggestedColors.first.toLowerCase()}',
              category:
                  garmentTypes[photo.type] ??
                  (category != null && categories.contains(category)
                      ? category
                      : categories.first),
              subtype: photo.type,
              photo: imported,
              colorTags: suggestedColors.isEmpty
                  ? [colors.first]
                  : suggestedColors,
              season: season,
              occasion: occasion,
              details: {'needs_review': photo.needsReview},
            ),
          );
          photo.saved = true;
          photo.saveError = null;
        } catch (e) {
          if (imported != null) {
            try {
              await File(widget.repo.photoPath(imported)).delete();
            } on FileSystemException {
              // An unreferenced file can be cleaned by repository maintenance.
            }
          }
          photo.saveError = errorMessage(e);
        }
      }
      if (mounted && pending.any((p) => !p.saved)) {
        message(context, 'Quedan fotos sin guardar. Puedes reintentarlas.');
      }
    } finally {
      if (mounted) setState(() => progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = photos.where((p) => p.saved).length;
    final pending = photos.where((p) => p.pending).length;
    final canAnalyze = photos.any((p) => p.pending && !p.analyzed);
    return PopScope(
      canPop: progress == null,
      child: Scaffold(
        appBar: AppBar(title: const Text('Añadir varias prendas')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '$saved guardadas de ${photos.length}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Confirma el tipo desde el menú de cada foto. Las detecciones dudosas se guardan como Por revisar.',
            ),
            const SizedBox(height: 16),
            AbsorbPointer(
              absorbing: busy,
              child: Column(
                children: [
                  choice('Temporada común', season, seasons, (v) {
                    setState(() => season = v);
                  }),
                  const SizedBox(height: 8),
                  choice('Ocasión común', occasion, occasions, (v) {
                    setState(() => occasion = v);
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: !busy && canAnalyze ? analyzeAll : null,
                  child: const Text('Analizar fotos'),
                ),
                FilledButton(
                  onPressed: !busy && pending > 0 ? saveAll : null,
                  child: Text('Guardar lote ($pending)'),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              Text(progress!),
            ],
            const SizedBox(height: 16),
            for (final (index, photo) in photos.indexed) _row(index, photo),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Finalizar importación'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int index, _BatchPhoto photo) {
    final type = photo.type.isEmpty ? '' : ' · ${photo.type}';
    final status = photo.saved
        ? 'Guardada'
        : photo.skipped
        ? 'Omitida'
        : photo.saveError ??
              (photo.confirmedType != null
                  ? 'Tipo confirmado$type'
                  : photo.analyzed
                  ? photo.needsReview
                        ? 'Por revisar$type'
                        : 'Sugerencia$type'
                  : 'Pendiente de analizar');
    return Card(
      child: ListTile(
        leading: SizedBox.square(dimension: 60, child: Photo(photo.file.path)),
        title: Text('Prenda ${index + 1}'),
        subtitle: Text(status),
        onTap: busy || photo.saved ? null : () => review(photo),
        trailing: photo.saved
            ? const Icon(Icons.check_circle_outline)
            : PopupMenuButton<String>(
                enabled: !busy,
                onSelected: (value) {
                  switch (value) {
                    case 'type':
                      chooseType(photo);
                    case 'review':
                      review(photo);
                    case 'toggle':
                      setState(() => photo.skipped = !photo.skipped);
                  }
                },
                itemBuilder: (_) => [
                  if (!photo.skipped)
                    const PopupMenuItem(
                      value: 'type',
                      child: Text('Confirmar tipo'),
                    ),
                  const PopupMenuItem(
                    value: 'review',
                    child: Text('Abrir ficha completa'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(photo.skipped ? 'Incluir de nuevo' : 'Omitir'),
                  ),
                ],
              ),
      ),
    );
  }
}
