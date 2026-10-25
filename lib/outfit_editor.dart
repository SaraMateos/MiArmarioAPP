import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'outfit_image_service.dart';
import 'auto_framed_photo.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';

class OutfitEditor extends StatefulWidget {
  final WardrobeRepository repo;
  final List<Garment> garments;
  final Outfit? outfit;
  const OutfitEditor({
    super.key,
    required this.repo,
    required this.garments,
    this.outfit,
  });
  @override
  State<OutfitEditor> createState() => _OutfitEditorState();
}

class _OutfitEditorState extends State<OutfitEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController name, notes;
  late List<OutfitItem> items;
  late List<String> occasionTags;
  bool favorite = false, busy = false;
  int? selected;
  String referencePhoto = '';
  String? pendingReference;
  bool removeReference = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.outfit?.name ?? '');
    notes = TextEditingController(text: widget.outfit?.notes ?? '');
    items = widget.outfit?.items.map((i) => i.copy()).toList() ?? [];
    occasionTags = [
      ...widget.outfit?.occasionTags ?? [occasions.first],
    ];
    favorite = widget.outfit?.favorite ?? false;
    referencePhoto = widget.outfit?.referencePhoto ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> add() async {
    final available = widget.garments
        .where((g) => !items.any((i) => i.garmentId == g.id))
        .toList();
    if (available.isEmpty) {
      message(context, 'Todas tus prendas ya están en este outfit.');
      return;
    }
    if (items.length >= 30) {
      message(context, 'Puedes añadir hasta 30 prendas por outfit.');
      return;
    }
    final garment = await showModalBottomSheet<Garment>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => _GarmentPicker(
        repo: widget.repo, garments: available,
      ),
    );
    if (garment != null && mounted) {
      setState(() {
        items.add(
          OutfitItem(
            garmentId: garment.id,
            x: _defaultPosition(garment, items.length).$1,
            y: _defaultPosition(garment, items.length).$2,
          ),
        );
        _sortLayers();
        selected = items.indexWhere((i) => i.garmentId == garment.id);
      });
    }
  }

  String _garmentKind(Garment garment) =>
      '${garment.category} ${garment.subtype}'.toLowerCase();

  (double, double) _defaultPosition(Garment garment, int index) {
    final kind = _garmentKind(garment);
    // Posiciones normalizadas en el lienzo: las prendas interiores quedan
    // detrás de las capas exteriores y cada familia ocupa su zona natural.
    if (kind.contains('vestido') || kind.contains('mono') || kind.contains('vestidos')) {
      return (.5, .43);
    }
    if (kind.contains('calzado') || kind.contains('zapato') ||
        kind.contains('bota') || kind.contains('sandalia')) {
      return (.5, .87);
    }
    if (kind.contains('inferior') || kind.contains('pantal') ||
        kind.contains('falda') || kind.contains('short')) {
      return (.5, .65);
    }
    if (kind.contains('abrigo') || kind.contains('chaqueta') ||
        kind.contains('americana') || kind.contains('chaleco')) {
      return (.5, .24);
    }
    if (kind.contains('superior') || kind.contains('camisa') ||
        kind.contains('camiseta') || kind.contains('jersey') ||
        kind.contains('sudadera') || kind.contains('blusa') ||
        kind.contains('polo')) {
      return (.5, .27);
    }
    if (kind.contains('accesorio') || kind.contains('bolso') ||
        kind.contains('bufanda') || kind.contains('gorro')) {
      return (.72, .35);
    }
    return (.5, .43);
  }

  int _layerPriority(Garment g) {
    final kind = _garmentKind(g);
    if (kind.contains('calzado') || kind.contains('zapato') ||
        kind.contains('bota') || kind.contains('sandalia')) {
      return 0;
    }
    if (kind.contains('inferior') || kind.contains('pantal') ||
        kind.contains('falda') || kind.contains('short')) {
      return 1;
    }
    if (kind.contains('vestido') || kind.contains('mono')) {
      return 2;
    }
    if (kind.contains('camiseta') || kind.contains('camisa') ||
        kind.contains('blusa') || kind.contains('polo')) {
      return 3;
    }
    if (kind.contains('jersey') || kind.contains('sudadera')) {
      return 4;
    }
    if (kind.contains('chaqueta') || kind.contains('abrigo') ||
        kind.contains('americana') || kind.contains('chaleco')) {
      return 5;
    }
    return 2;
  }

  void _sortLayers() {
    final byId = {for (final g in widget.garments) g.id: g};
    int compare(OutfitItem a, OutfitItem b) =>
        _layerPriority(byId[a.garmentId] ?? widget.garments.first)
            .compareTo(_layerPriority(byId[b.garmentId] ?? widget.garments.first));
    items.sort(compare);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    if (items.isEmpty) {
      message(context, 'Añade al menos una prenda al outfit.');
      return;
    }
    setState(() => busy = true);
    String? imported;
    try {
      if (pendingReference != null) {
        imported = await widget.repo.importPhoto(pendingReference!);
      }
      await widget.repo.saveOutfit(
        Outfit(
          id: widget.outfit?.id ?? const Uuid().v4(),
          name: name.text.trim().isEmpty
              ? (widget.outfit?.name.isNotEmpty == true
                  ? widget.outfit!.name
                  : 'Look ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}')
              : name.text.trim(),
          occasionTags: occasionTags,
          items: [
            for (var i = 0; i < items.length; i++)
              OutfitItem(garmentId: items[i].garmentId,
                x: items[i].x, y: items[i].y, scale: items[i].scale,
              ),
          ],
          notes: notes.text.trim(),
          favorite: favorite,
          referencePhoto: imported ?? (removeReference ? '' : referencePhoto),
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (imported != null) {
        final file = File(widget.repo.photoPath(imported));
        if (await file.exists()) await file.delete();
      }
      if (mounted) {
        message(context, errorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.outfit == null ? 'Crear outfit' : 'Editar outfit'),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Tu combinación',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: add,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Añadir prenda'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutfitBoard(
                repo: widget.repo,
                garments: widget.garments,
                items: items,
                showFigure: false,
                selected: selected,
                onSelect: (i) => setState(() => selected = i),
                onMove: (i, dx, dy) => setState(() {
                  items[i].x = (items[i].x + dx).clamp(0.0, 1.0);
                  items[i].y = (items[i].y + dy).clamp(0.0, 1.0);
                }),
              ),
              if (selected != null && selected! < items.length) ...[
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 1,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Icon(Icons.open_with, size: 18),
                        const SizedBox(width: 6),
                        const Text('Tamaño'),
                        Expanded(child: Slider(
                          min: .5, max: 1.6,
                          value: items[selected!].scale.clamp(.5, 1.6),
                          onChanged: (v) => setState(() => items[selected!].scale = v),
                        )),
                        IconButton(
                          tooltip: 'Eliminar prenda',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() {
                            final garmentId = items[selected!].garmentId;
                            items.removeWhere((item) => item.garmentId == garmentId);
                            selected = null;
                          }),
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                        ),
                      ]),
                      Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() {
                              items[selected!].x = .5;
                              items[selected!].y = .5;
                            }),
                            icon: const Icon(Icons.center_focus_strong, size: 18),
                            label: const Text('Centrar'),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              final garmentId = items[selected!].garmentId;
                              final index = items.indexWhere((item) => item.garmentId == garmentId);
                              if (index >= 0) {
                                final item = items.removeAt(index);
                                items.add(item);
                              }
                              selected = items.indexWhere((item) => item.garmentId == garmentId);
                            }),
                            icon: const Icon(Icons.flip_to_front, size: 18),
                            label: const Text('Al frente'),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              final garmentId = items[selected!].garmentId;
                              final index = items.indexWhere((item) => item.garmentId == garmentId);
                              if (index >= 0) {
                                final item = items.removeAt(index);
                                items.insert(0, item);
                              }
                              selected = items.indexWhere((item) => item.garmentId == garmentId);
                            }),
                            icon: const Icon(Icons.vertical_align_bottom, size: 18),
                            label: const Text('Al fondo'),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Prendas', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final garment = widget.garments.where((g) => g.id == items[i].garmentId).firstOrNull;
                      final isSelected = selected == i;
                      return Semantics(
                        button: true,
                        selected: isSelected,
                        label: garment?.name ?? 'Prenda ${i + 1}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => selected = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 84,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.secondaryContainer
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outlineVariant,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: garment == null
                                      ? const Icon(Icons.checkroom, size: 32)
                                      : AutoFramedPhoto(
                                          widget.repo.photoPath(garment.photo),
                                          padding: .04,
                                        ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  garment?.name ?? 'Prenda ${i + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (pendingReference != null ||
                  (!removeReference && referencePhoto.isNotEmpty))
                SizedBox(
                  height: 240,
                  child: Photo(
                    pendingReference ?? widget.repo.photoPath(referencePhoto),
                    fit: BoxFit.contain,
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Foto puesto'),
                    onPressed: () async {
                      try {
                        final photo = await ImagePicker().pickImage(
                          source: ImageSource.camera,
                          maxWidth: 1600,
                          maxHeight: 1600,
                          imageQuality: 85,
                        );
                        if (photo != null && mounted) {
                          setState(() {
                            pendingReference = photo.path;
                            removeReference = false;
                          });
                        }
                      } catch (e) {
                        if (context.mounted) {
                          message(context, errorMessage(e));
                        }
                      }
                    },
                  ),
                  if (pendingReference != null || referencePhoto.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        pendingReference = null;
                        removeReference = true;
                      }),
                      child: const Text('Quitar foto'),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Exportar imagen'),
                    onPressed: items.isEmpty
                        ? null
                        : () => OutfitImageService.export(
                            context,
                            widget.repo,
                            Outfit(
                              id: widget.outfit?.id ?? 'export',
                              name: name.text.trim().isEmpty
                                  ? (widget.outfit?.name.isNotEmpty == true
                                      ? widget.outfit!.name
                                      : 'Mi outfit')
                                  : name.text.trim(),
                              items: items,
                              occasionTags: occasionTags,
                            ),
                            widget.garments,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: name,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Nombre del outfit',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Escribe un nombre para el outfit.'
                    : null,
              ),
              const SizedBox(height: 12),
              MultiChoice(
                label: 'Ocasiones',
                values: occasions,
                selected: occasionTags,
                onChanged: (v) => setState(() => occasionTags = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: notes,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Favorito'),
                value: favorite,
                onChanged: (v) => setState(() => favorite = v),
              ),
              FilledButton.icon(
                onPressed: busy ? null : save,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(busy ? 'Guardando…' : 'Guardar outfit'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GarmentPicker extends StatefulWidget {
  const _GarmentPicker({required this.repo, required this.garments});
  final WardrobeRepository repo;
  final List<Garment> garments;
  @override
  State<_GarmentPicker> createState() => _GarmentPickerState();
}

class _GarmentPickerState extends State<_GarmentPicker> {
  String category = 'Todas';
  String query = '';
  @override
  Widget build(BuildContext context) {
    final categories = ['Todas', ...widget.garments.map((g) => g.category).toSet()];
    final shown = widget.garments.where((g) =>
        (category == 'Todas' || g.category == category) &&
        (query.isEmpty || g.name.toLowerCase().contains(query.toLowerCase()))).toList();
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Text('Elige una prenda', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
            hintText: 'Buscar prendas', isDense: true)),
        const SizedBox(height: 8),
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal,
          children: [for (final c in categories) Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: Text(c), selected: category == c,
              onSelected: (_) => setState(() => category = c)),
          )])),
        const SizedBox(height: 8),
        Expanded(child: GridView.builder(
          itemCount: shown.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: .82),
          itemBuilder: (context, i) {
            final garment = shown[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.pop(context, garment),
              child: Column(children: [
                Expanded(child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.all(6),
                  child: AutoFramedPhoto(widget.repo.photoPath(garment.photo), padding: .04),
                )),
                const SizedBox(height: 5),
                Text(garment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (garment.status != 'Disponible')
                  Text(garment.status, style: Theme.of(context).textTheme.labelSmall),
              ]),
            );
          },
        )),
      ]),
    ));
  }
}
