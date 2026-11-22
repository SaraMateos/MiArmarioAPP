import 'auto_framed_photo.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';
import 'local_photo_service.dart';
import 'cutout_editor.dart';
import 'wardrobe_tools.dart';

class GarmentEditor extends StatefulWidget {
  final WardrobeRepository repo;
  final Garment? garment;
  final String? recoveredPhoto;
  final bool batchMode;
  final PhotoAnalysis? initialAnalysis;
  final String? initialSubtype, initialSeason, initialOccasion;
  const GarmentEditor({
    super.key,
    required this.repo,
    this.garment,
    this.recoveredPhoto,
    this.batchMode = false,
    this.initialAnalysis,
    this.initialSubtype,
    this.initialSeason,
    this.initialOccasion,
  });
  @override
  State<GarmentEditor> createState() => _GarmentEditorState();
}

class _GarmentEditorState extends State<GarmentEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController name, notes;
  late String category;
  String subtype = '', generatedBase = 'Prenda nueva';
  bool automaticName = true, needsReview = false, typeConfirmed = false;
  String? analysisNote;
  List<String> typeAlternatives = [];
  final detailControllers = <String, TextEditingController>{};
  String garmentStyle = 'Sin preferencia', layer = 'Automática';
  bool rain = false, wind = false;
  late List<String> colorTags, seasonTags, occasionTags;
  int warmth = 2;
  String? newPhoto, retainedSource;
  String status = 'Disponible';
  bool sourceChanged = false;
  bool favorite = false, busy = false;
  String busyLabel = 'Procesando…';
  final colorSectionTitle = GlobalKey();
  final climateSectionTitle = GlobalKey();
  final detailsSectionTitle = GlobalKey();
  final notesSectionTitle = GlobalKey();
  @override
  void initState() {
    super.initState();
    final g = widget.garment;
    name = TextEditingController(
      text: g?.name ?? (widget.recoveredPhoto != null ? 'Prenda nueva' : ''),
    );
    automaticName = g == null;
    needsReview =
        g == null ||
        g.subtype.isEmpty ||
        (g.details['needs_review'] == true || g.details['type_review'] == true);
    typeConfirmed = g != null && g.subtype.isNotEmpty && !needsReview;
    for (final field in [
      'size',
      'brand',
      'fabric',
      'washing',
      'archive_reason',
    ]) {
      detailControllers[field] = TextEditingController(
        text: g?.details[field] as String? ?? '',
      );
    }
    garmentStyle = g?.details['style'] as String? ?? 'Sin preferencia';
    layer = g?.details['layer'] as String? ?? 'Automática';
    rain = g?.details['rain'] == true;
    wind = g?.details['wind'] == true;
    subtype = g?.subtype ?? '';
    generatedBase = subtype.isEmpty ? 'Prenda nueva' : subtype;
    notes = TextEditingController(text: g?.notes ?? '');
    category = g?.category ?? categories.first;
    if (g == null && widget.initialSubtype != null) {
      subtype = widget.initialSubtype!;
      category = garmentTypes[subtype]!;
      generatedBase = subtype;
      name.text = subtype;
      needsReview = false;
      typeConfirmed = true;
    }
    colorTags = [
      ...g?.colorTags ?? [colors.first],
    ];
    seasonTags = [
      ...g?.seasonTags ?? [widget.initialSeason ?? seasons.first],
    ];
    occasionTags = [
      ...g?.occasionTags ?? [widget.initialOccasion ?? occasions.first],
    ];
    warmth = g?.warmth ?? 2;
    status = g?.status ?? 'Disponible';
    if (g != null && g.sourcePhoto.isNotEmpty) {
      retainedSource = widget.repo.photoPath(g.sourcePhoto);
    }
    favorite = g?.favorite ?? false;
    newPhoto = widget.recoveredPhoto;
    if (widget.garment == null && newPhoto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final initial = widget.initialAnalysis;
        if (initial == null) {
          analyze();
        } else {
          applyAnalysis(initial);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in detailControllers.values) {
      c.dispose();
    }
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    setState(() {
      busy = true;
      busyLabel = 'Preparando foto…';
    });
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (photo != null && mounted) {
        setState(() {
          newPhoto = photo.path;
          retainedSource = null;
          sourceChanged = true;
          if (automaticName) {
            generatedBase = 'Prenda nueva';
            name.text = generatedBase;
          }
        });
        final a = await LocalPhotoService.analyze(photo.path);
        if (mounted) applyAnalysis(a);
      }
    } catch (e) {
      if (mounted) {
        message(
          context,
          'No se ha podido completar la captura o el análisis. Si la foto se muestra, puedes completar los datos manualmente.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> crop() async {
    final source =
        newPhoto ??
        (widget.garment == null
            ? null
            : widget.repo.photoPath(widget.garment!.photo));
    if (source == null) {
      return;
    }
    setState(() {
      busy = true;
      busyLabel = 'Recortando foto…';
    });
    try {
      final result = await ImageCropper().cropImage(
        sourcePath: source,
        maxWidth: 1600,
        maxHeight: 1600,
        compressQuality: 85,
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar prenda',
            toolbarColor: const Color(0xff355c4e),
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
        ],
      );
      if (result != null && mounted) {
        setState(() {
          newPhoto = result.path;
          retainedSource = null;
          sourceChanged = true;
        });
      }
    } catch (_) {
      if (mounted) {
        message(
          context,
          'No se ha podido recortar la foto. La imagen anterior se conserva.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  String? get workingPath =>
      newPhoto ??
      (widget.garment == null
          ? null
          : widget.repo.photoPath(widget.garment!.photo));
  void applyAnalysis(PhotoAnalysis a) {
    setState(() {
      typeAlternatives = a.alternatives
          .where(garmentTypes.containsKey)
          .toList();
      final detected = a.suggestedType;
      final manualType = typeConfirmed && subtype.isNotEmpty;
      if (!manualType) {
        subtype = detected;
        if (detected.isNotEmpty) {
          category = garmentTypes[detected]!;
        } else if (a.category != null) {
          category = a.category!;
        }
        needsReview = a.needsTypeReview;
      }
      if (a.colors.isNotEmpty) colorTags = a.colors;
      generatedBase = manualType
          ? subtype
          : (a.suggestedName ?? 'Prenda nueva');
      if (automaticName) {
        name.text =
            '$generatedBase${a.colors.isNotEmpty ? ' ${a.colors.first.toLowerCase()}' : ''}';
      }
      analysisNote =
          a.warning ??
          (needsReview
              ? 'Por revisar · confirma el tipo antes de guardar. La detección es una sugerencia.'
              : 'Datos sugeridos · puedes corregirlos en la ficha.');
    });
  }

  Future<void> analyze() async {
    final path = workingPath;
    if (path == null || busy) return;
    setState(() {
      busy = true;
      busyLabel = 'Detectando datos…';
    });
    try {
      final a = await LocalPhotoService.analyze(path);
      if (mounted) applyAnalysis(a);
    } catch (e) {
      if (mounted) {
        message(context, photoErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeBackground(bool worn) async {
    final source = workingPath;
    if (source == null || busy) return;
    setState(() {
      busy = true;
      busyLabel = 'Preparando recorte…';
    });
    try {
      final result = await LocalPhotoService.editableBackground(
        source,
        worn: worn,
        accessory: ['Calzado', 'Accesorios'].contains(category),
      );
      final path = result['path']!, original = result['source']!;
      if (!mounted) return;
      final accept = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Revisar recorte'),
          content: SizedBox(
            width: 320,
            height: 330,
            child: InkWell(
              onTap: () => viewPhoto(path),
              child: Photo(path, fit: BoxFit.contain),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Descartar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usar recorte'),
            ),
          ],
        ),
      );
      if (accept == true && mounted) {
        setState(() {
          newPhoto = path;
          retainedSource = original;
          sourceChanged = true;
        });
        try {
          final a = await LocalPhotoService.analyze(path);
          if (mounted) applyAnalysis(a);
        } catch (e) {
          if (mounted) {
            message(context, 'Recorte aplicado. ${photoErrorMessage(e)}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        message(
          context,
          '${photoErrorMessage(e)} La foto anterior se conserva.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> correctCutout() async {
    final path = workingPath;
    if (path == null || busy) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CutoutEditor(path: path, sourcePath: retainedSource),
      ),
    );
    if (result != null && mounted) setState(() => newPhoto = result);
  }

  Future<void> save() async {
    if (busy) return;
    if (name.text.trim().isEmpty) {
      message(context, 'Introduce un nombre para la prenda.');
      return;
    }
    if (!form.currentState!.validate()) {
      return;
    }
    if (newPhoto == null && widget.garment == null) {
      message(context, 'Añade una foto de la prenda.');
      return;
    }
    if (widget.garment == null && workingPath != null) {
      setState(() {
        busy = true;
        busyLabel = 'Guardando prenda…';
      });
      try {
        final own = await DuplicateService.fingerprint(workingPath!);
        final found = <Garment>[];
        for (final g in await widget.repo.garments()) {
          if (g.category != category || !g.colorTags.any(colorTags.contains)) {
            continue;
          }
          try {
            final other = await DuplicateService.fingerprint(
              widget.repo.photoPath(g.photo),
            );
            if (own.contains('0') &&
                own.contains('1') &&
                DuplicateService.distance(own, other) <= 5) {
              found.add(g);
            }
          } catch (_) {
            /* A broken old photo must not block a new garment. */
          }
        }
        if (found.isNotEmpty &&
            mounted &&
            !await confirm(
              context,
              'Posible prenda duplicada',
              'La foto se parece a ${found.take(3).map((g) => g.name).join(', ')}. Puede ser una prenda distinta. ¿Guardar igualmente?',
              action: 'Guardar igualmente',
            )) {
          return;
        }
        if (!mounted) return;
      } catch (_) {
        /* Continue manual save if fingerprint cannot be obtained. */
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      busyLabel = 'Guardando prenda…';
    });
    String? imported, importedSource;
    try {
      if (newPhoto != null) {
        imported = await widget.repo.importPhoto(newPhoto!);
      }
      if (sourceChanged && retainedSource != null) {
        importedSource = await widget.repo.importPhoto(retainedSource!);
      }
      await widget.repo.saveGarment(
        Garment(
          id: widget.garment?.id ?? const Uuid().v4(),
          name: name.text.trim(),
          category: category,
          subtype: subtype,
          details: {
            for (final e in detailControllers.entries)
              e.key: e.value.text.trim(),
            'style': garmentStyle,
            'layer': layer,
            'rain': rain,
            'wind': wind,
            'needs_review': needsReview,
          },
          colorTags: colorTags,
          seasonTags: seasonTags,
          occasionTags: occasionTags,
          warmth: warmth,
          status: status,
          sourcePhoto: sourceChanged
              ? (importedSource ?? '')
              : (widget.garment?.sourcePhoto ?? ''),
          notes: notes.text.trim(),
          photo: imported ?? widget.garment!.photo,
          favorite: favorite,
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      for (final copied in [imported, importedSource].whereType<String>()) {
        // The copy is unreferenced if the database write failed.
        final file = File(widget.repo.photoPath(copied));
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } on FileSystemException {
          /* cleaned later */
        }
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

  Future<void> viewPhoto(String path) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Revisar foto')),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(child: Photo(path, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  // No desplazar el formulario al abrir una sección: el salto del scroll
  // interfería con las opciones y podía dejar desplegables mal colocados.
  void revealSection(GlobalKey title, bool expanded) {}

  Widget _compactSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ExpansionTile(
      maintainState: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final path =
        newPhoto ??
        (widget.garment == null
            ? null
            : widget.repo.photoPath(widget.garment!.photo));
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.batchMode
                ? 'Revisar prenda del lote'
                : widget.garment == null
                ? 'Nueva prenda'
                : 'Editar prenda',
          ),
        ),
        bottomSheet: busy ? const LinearProgressIndicator() : null,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton.icon(
              onPressed: busy ? null : save,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(busy ? busyLabel : 'Guardar prenda'),
            ),
          ),
        ),

        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: [
                SizedBox(
                  height: 205,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: ColoredBox(
                      color: const Color(0xfff4f3ee),
                      child: path == null
                          ? const Center(
                              child: Icon(Icons.add_a_photo_outlined, size: 64),
                            )
                          : InkWell(
                              onTap: () => viewPhoto(path),
                              child: AutoFramedPhoto(path, padding: 0.04),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Cámara'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _compactSection(
                  title: 'Herramientas de fotografía',
                  subtitle: 'Recortar, detectar y mejorar la imagen',
                  icon: Icons.auto_fix_high_outlined,
                  children: [
                if (path != null)
                  TextButton.icon(
                    onPressed: crop,
                    icon: const Icon(Icons.crop),
                    label: const Text('Recortar / girar foto'),
                  ),
                if (path != null) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: analyze,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Detectar datos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: correctCutout,
                        icon: const Icon(Icons.brush),
                        label: const Text('Corregir con pincel'),
                      ),
                      OutlinedButton(
                        onPressed: () => removeBackground(false),
                        child: const Text('Quitar fondo · prenda sola'),
                      ),
                      OutlinedButton(
                        onPressed: () => removeBackground(true),
                        child: const Text('Aislar ropa · puesta'),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Si hay varias prendas, recorta la que quieras guardar.',
                    ),
                  ),
                ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  onChanged: (_) => automaticName = false,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la prenda',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Introduce un nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                if (needsReview)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.fact_check_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              subtype.isEmpty
                                  ? 'Por revisar: selecciona el tipo de prenda antes de guardar.'
                                  : 'Tipo sugerido: confirma si es correcto o elige otra opción.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                choice(
                  'Categoría',
                  category == 'Abrigos' ? 'Parte superior' : category,
                  categories.where((c) => c != 'Abrigos').toList(),
                  (v) => setState(() {
                    if (!matchesCategoryGroup(v, garmentTypes[subtype] ?? v)) {
                      subtype = '';
                    }
                    category = subtype.isEmpty ? v : garmentTypes[subtype]!;
                    needsReview = subtype.isEmpty;
                    typeConfirmed = subtype.isNotEmpty;
                  }),
                ),
                const SizedBox(height: 8),
                choice(
                  'Tipo de prenda',
                  subtype.isEmpty ? 'Sin especificar' : subtype,
                  [
                    'Sin especificar',
                    ...typesForCategoryGroup(
                      category == 'Abrigos' ? 'Parte superior' : category,
                    ),
                  ],
                  (v) => setState(() {
                    subtype = v == 'Sin especificar' ? '' : v;
                    needsReview = subtype.isEmpty;
                    typeConfirmed = subtype.isNotEmpty;
                    if (subtype.isNotEmpty) {
                      category = garmentTypes[subtype]!;
                      generatedBase = subtype;
                      if (automaticName) {
                        name.text = '$subtype ${colorTags.first.toLowerCase()}';
                      }
                    }
                  }),
                ),
                if (analysisNote != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(analysisNote!),
                  ),
                if (needsReview && typeAlternatives.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final candidate in typeAlternatives)
                        ActionChip(
                          label: Text(candidate),
                          onPressed: () => setState(() {
                            subtype = candidate;
                            category = garmentTypes[candidate]!;
                            needsReview = false;
                            typeConfirmed = true;
                            analysisNote = 'Tipo confirmado por ti';
                            if (automaticName) {
                              name.text =
                                  '$candidate ${colorTags.first.toLowerCase()}';
                            }
                          }),
                        ),
                    ],
                  ),
                if (needsReview)
                  TextButton.icon(
                    onPressed: subtype.isEmpty
                        ? null
                        : () => setState(() {
                            needsReview = false;
                            typeConfirmed = true;
                            analysisNote = 'Tipo confirmado por ti';
                          }),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirmar tipo de prenda'),
                  ),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
                ExpansionTile(
                  key: const PageStorageKey('colores-temporadas'),
                  maintainState: true,
                  title: Text(
                    'Colores, temporadas y ocasiones',
                    key: colorSectionTitle,
                  ),
                  onExpansionChanged: (open) =>
                      revealSection(colorSectionTitle, open),
                  subtitle: Text(
                    '${colorTags.join(', ')} · ${seasonTags.join(', ')}',
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    MultiChoice(
                      label: 'Colores',
                      values: [...colors]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
                      selected: colorTags,
                      onChanged: (v) => setState(() => colorTags = v),
                    ),
                    const SizedBox(height: 16),
                    MultiChoice(
                      label: 'Temporadas',
                      values: seasons,
                      selected: seasonTags,
                      exclusiveAllYear: true,
                      onChanged: (v) => setState(() => seasonTags = v),
                    ),
                    const SizedBox(height: 16),
                    MultiChoice(
                      label: 'Ocasiones',
                      values: occasions,
                      selected: occasionTags,
                      onChanged: (v) => setState(() => occasionTags = v),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                ExpansionTile(
                  key: const PageStorageKey('disponibilidad-estilo'),
                  maintainState: true,
                  title: Text(
                    'Disponibilidad y estilo',
                    key: climateSectionTitle,
                  ),
                  onExpansionChanged: (open) =>
                      revealSection(climateSectionTitle, open),
                  subtitle: Text(
                    '$status · ${['Ligera', 'Media', 'Abrigada'][warmth - 1]}',
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  childrenPadding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
                  children: [
                    choice(
                      'Disponibilidad',
                      status,
                      garmentStates,
                      (v) => setState(() => status = v),
                    ),
                    const SizedBox(height: 16),
                    choice(
                      'Nivel de abrigo',
                      ['Ligera', 'Media', 'Abrigada'][warmth - 1],
                      ['Ligera', 'Media', 'Abrigada'],
                      (v) => setState(
                        () => warmth =
                            ['Ligera', 'Media', 'Abrigada'].indexOf(v) + 1,
                      ),
                    ),

                    const SizedBox(height: 16),
                    choice(
                      'Estilo de la prenda',
                      garmentStyle,
                      outfitStyles,
                      (v) => setState(() => garmentStyle = v),
                    ),
                  ],
                ),
                ExpansionTile(
                  key: const PageStorageKey('caracteristicas-avanzadas'),
                  maintainState: true,
                  title: const Text('Características avanzadas'),
                  subtitle: const Text('Capas, lluvia y viento'),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (['Parte superior', 'Abrigos'].contains(category)) ...[
                      choice('Función como capa', layer, garmentLayers,
                          (v) => setState(() => layer = v)),
                      const SizedBox(height: 20),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Protege de la lluvia'),
                      subtitle: const Text('Solo si conoces su protección'),
                      value: rain,
                      onChanged: (v) => setState(() => rain = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Protege del viento'),
                      value: wind,
                      onChanged: (v) => setState(() => wind = v),
                    ),
                  ],
                ),
                ExpansionTile(
                  key: const PageStorageKey('talla-marca'),
                  maintainState: true,
                  title: Text(
                    'Talla, marca y cuidados',
                    key: detailsSectionTitle,
                  ),
                  onExpansionChanged: (open) =>
                      revealSection(detailsSectionTitle, open),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    for (final e in {
                      'size': 'Talla',
                      'brand': 'Marca',
                      'fabric': 'Tejido',
                      'washing': 'Instrucciones de lavado',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextFormField(
                          controller: detailControllers[e.key],
                          maxLength: 300,
                          decoration: InputDecoration(labelText: e.value),
                        ),
                      ),
                  ],
                ),
                ExpansionTile(
                  key: const PageStorageKey('notas-archivo'),
                  maintainState: true,
                  title: Text('Notas y opciones', key: notesSectionTitle),
                  onExpansionChanged: (open) =>
                      revealSection(notesSectionTitle, open),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    if (status == 'Archivada')
                      TextFormField(
                        controller: detailControllers['archive_reason'],
                        maxLength: 300,
                        decoration: const InputDecoration(
                          labelText: 'Motivo: vendida, donada, talla…',
                        ),
                      ),
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
                      title: const Text('Favorita'),
                      value: favorite,
                      onChanged: (v) => setState(() => favorite = v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
