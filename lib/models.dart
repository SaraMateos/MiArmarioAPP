import 'dart:convert';

const garmentStates = ['Disponible', 'En lavado', 'Guardada', 'Archivada'];

const categories = [
  'Parte superior',
  'Parte inferior',
  'Vestidos',
  'Abrigos',
  'Calzado',
  'Accesorios',
];
const garmentTypes = <String, String>{
  'Camiseta': 'Parte superior',
  'Polo': 'Parte superior',
  'Camisa': 'Parte superior',
  'Blusa': 'Parte superior',
  'Jersey': 'Parte superior',
  'Sudadera': 'Parte superior',
  'Camiseta deportiva': 'Parte superior',
  'Pantalón': 'Parte inferior',
  'Vaqueros': 'Parte inferior',
  'Falda': 'Parte inferior',
  'Shorts': 'Parte inferior',
  'Leggings': 'Parte inferior',
  'Pantalón deportivo': 'Parte inferior',
  'Vestido': 'Vestidos',
  'Mono': 'Vestidos',
  'Abrigo': 'Abrigos',
  'Chaqueta': 'Abrigos',
  'Americana': 'Abrigos',
  'Chaleco': 'Abrigos',
  'Zapatillas': 'Calzado',
  'Zapatos': 'Calzado',
  'Zapatos de vestir': 'Calzado',
  'Botas': 'Calzado',
  'Sandalias': 'Calzado',
  'Bolso': 'Accesorios',
  'Cinturón': 'Accesorios',
  'Bufanda': 'Accesorios',
  'Gorro': 'Accesorios',
  'Joyas': 'Accesorios',
};
String inferGarmentType(String name) {
  final n = name.toLowerCase();
  for (final e in <String, String>{
    'vaquero': 'Vaqueros',
    'jean': 'Vaqueros',
    'pantalón deportivo': 'Pantalón deportivo',
    'pantalon deportivo': 'Pantalón deportivo',
    'leggings': 'Leggings',
    'pantalón': 'Pantalón',
    'pantalon': 'Pantalón',
    'falda': 'Falda',
    'short': 'Shorts',
    'bermuda': 'Shorts',
    'mono': 'Mono',
    'vestido': 'Vestido',
    'camiseta deportiva': 'Camiseta deportiva',
    'camiseta': 'Camiseta',
    'polo': 'Polo',
    'camisa': 'Camisa',
    'blusa': 'Blusa',
    'jersey': 'Jersey',
    'sudadera': 'Sudadera',
    'americana': 'Americana',
    'chaqueta': 'Chaqueta',
    'abrigo': 'Abrigo',
    'chaleco': 'Chaleco',
    'zapatilla': 'Zapatillas',
    'zapatos de vestir': 'Zapatos de vestir',
    'zapato': 'Zapatos',
    'bota': 'Botas',
    'sandalia': 'Sandalias',
    'bolso': 'Bolso',
    'cinturón': 'Cinturón',
    'bufanda': 'Bufanda',
    'gorro': 'Gorro',
  }.entries) {
    if (RegExp('(^|[^a-záéíóúñ])${RegExp.escape(e.key)}').hasMatch(n)) {
      return e.value;
    }
  }
  return '';
}

String roleOf(Garment g) =>
    garmentTypes[g.subtype] ??
    garmentTypes[inferGarmentType(g.name)] ??
    g.category;
List<Garment> orderedGarments(Iterable<Garment> pieces) => pieces.toList()
  ..sort(
    (a, b) =>
        categories.indexOf(roleOf(a)).compareTo(categories.indexOf(roleOf(b))),
  );
const seasons = ['Todo el año', 'Primavera', 'Verano', 'Otoño', 'Invierno'];
const occasions = ['Diario', 'Trabajo', 'Deporte', 'Fiesta', 'Formal'];
const colors = [
  'Negro',
  'Blanco',
  'Gris',
  'Beige',
  'Marrón',
  'Azul',
  'Azul marino',
  'Celeste',
  'Turquesa',
  'Verde',
  'Verde oliva',
  'Verde salvia',
  'Rojo',
  'Burdeos',
  'Rosa',
  'Rosa palo',
  'Coral',
  'Morado',
  'Lila',
  'Amarillo',
  'Mostaza',
  'Naranja',
  'Crema',
  'Caqui',
  'Plateado',
  'Dorado',
  'Multicolor',
];

List<String> readSelections(Object? value) {
  if (value is List) return value.cast<String>().toList();
  if (value is! String || value.isEmpty) {
    throw const FormatException('Selección no válida.');
  }
  if (value.startsWith('[')) {
    final decoded = jsonDecode(value);
    if (decoded is! List) throw const FormatException('Selección no válida.');
    return decoded.cast<String>().toList();
  }
  return [value]; // Original 1.0 backups/database.
}

bool validSelections(Object? value, List<String> allowed) {
  try {
    final values = readSelections(value);
    return values.isNotEmpty &&
        values.length <= allowed.length &&
        values.toSet().length == values.length &&
        values.every(allowed.contains);
  } catch (_) {
    return false;
  }
}

class Garment {
  final String id, name, category, notes, photo, status, sourcePhoto, subtype;
  final List<String> colorTags, seasonTags, occasionTags;
  final Map<String, Object?> details;
  final int warmth;
  final bool favorite;
  Garment({
    required this.id,
    required this.name,
    required this.category,
    required this.photo,
    String color = 'Negro',
    String season = 'Todo el año',
    String occasion = 'Diario',
    List<String>? colorTags,
    List<String>? seasonTags,
    List<String>? occasionTags,
    this.notes = '',
    this.favorite = false,
    this.warmth = 2,
    this.status = 'Disponible',
    this.sourcePhoto = '',
    this.subtype = '',
    this.details = const {},
  }) : colorTags = List.unmodifiable(colorTags ?? [color]),
       seasonTags = List.unmodifiable(seasonTags ?? [season]),
       occasionTags = List.unmodifiable(occasionTags ?? [occasion]);
  bool get available => status == 'Disponible';
  String get color => colorTags.join(', ');
  String get season => seasonTags.join(', ');
  String get occasion => occasionTags.join(', ');
  factory Garment.fromMap(Map<String, Object?> m) => Garment(
    id: m['id'] as String,
    name: m['name'] as String,
    category: m['category'] as String,
    colorTags: readSelections(m['color']),
    seasonTags: readSelections(m['season']),
    occasionTags: readSelections(m['occasion']),
    photo: m['photo'] as String,
    notes: m['notes'] as String,
    favorite: m['favorite'] == 1,
    warmth: (m['warmth'] as int?) ?? 2,
    status: (m['status'] as String?) ?? 'Disponible',
    sourcePhoto: (m['source_photo'] as String?) ?? '',
    subtype: (m['subtype'] as String?) ?? '',
    details: Map<String, Object?>.from(
      jsonDecode(m['details'] as String? ?? '{}') as Map,
    ),
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': garmentTypes[subtype] ?? category,
    'color': jsonEncode(colorTags),
    'season': jsonEncode(seasonTags),
    'occasion': jsonEncode(occasionTags),
    'notes': notes,
    'photo': photo,
    'favorite': favorite ? 1 : 0,
    'warmth': warmth,
    'status': status,
    'source_photo': sourcePhoto,
    'subtype': subtype,
    'details': jsonEncode(details),
  };
}

class OutfitItem {
  final String garmentId;
  double x, y, scale;
  double mannequinX, mannequinY, mannequinScale;
  OutfitItem({
    required this.garmentId,
    this.x = .1,
    this.y = .1,
    this.scale = 1,
    double? mannequinX, double? mannequinY, double? mannequinScale,
  }) : mannequinX = mannequinX ?? x, mannequinY = mannequinY ?? y, mannequinScale = mannequinScale ?? scale;
  factory OutfitItem.fromMap(Map<String, Object?> m) => OutfitItem(
    garmentId: m['garment_id'] as String,
    x: (m['x'] as num).toDouble(),
    y: (m['y'] as num).toDouble(),
    scale: (m['scale'] as num).toDouble(),
    mannequinX: (m['mannequin_x'] as num?)?.toDouble(),
    mannequinY: (m['mannequin_y'] as num?)?.toDouble(),
    mannequinScale: (m['mannequin_scale'] as num?)?.toDouble(),
  );
  Map<String, Object?> toMap(String outfitId, int position) => {
    'outfit_id': outfitId,
    'garment_id': garmentId,
    'position': position,
    'x': x,
    'y': y,
    'scale': scale,
    'mannequin_x': mannequinX,
    'mannequin_y': mannequinY,
    'mannequin_scale': mannequinScale,
  };
  OutfitItem copy() =>
      OutfitItem(garmentId: garmentId, x: x, y: y, scale: scale, mannequinX: mannequinX, mannequinY: mannequinY, mannequinScale: mannequinScale);
}

class Outfit {
  final String id, name, notes, referencePhoto;
  final List<String> occasionTags;
  final bool favorite;
  final List<OutfitItem> items;
  Outfit({
    required this.id,
    required this.name,
    required this.items,
    String occasion = 'Diario',
    List<String>? occasionTags,
    this.notes = '',
    this.referencePhoto = '',
    this.favorite = false,
  }) : occasionTags = List.unmodifiable(occasionTags ?? [occasion]);
  String get occasion => occasionTags.join(', ');
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'occasion': jsonEncode(occasionTags),
    'notes': notes,
    'favorite': favorite ? 1 : 0,
    'reference_photo': referencePhoto,
  };
}

class DayPlan {
  final String date, outfitId;
  final bool worn;
  const DayPlan(this.date, this.outfitId, this.worn);
  Map<String, Object?> toMap() => {
    'date': date,
    'outfit_id': outfitId,
    'worn': worn ? 1 : 0,
  };
}

class WearStat {
  final int count;
  final DateTime? lastWorn;
  const WearStat({this.count = 0, this.lastWorn});
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime calendarDayOffset(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);
int calendarDayDifference(DateTime a, DateTime b) => DateTime.utc(
  a.year,
  a.month,
  a.day,
).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

const outfitStyles = [
  'Sin preferencia',
  'Casual',
  'Minimalista',
  'Elegante',
  'Deportivo',
];
const garmentLayers = ['Automática', 'Base', 'Intermedia', 'Exterior'];
String layerOf(Garment g) {
  final explicit = g.details['layer'];
  if (explicit is String &&
      explicit != 'Automática' &&
      garmentLayers.contains(explicit)) {
    return explicit;
  }
  if (roleOf(g) == 'Abrigos') return 'Exterior';
  final type = g.subtype.isEmpty ? inferGarmentType(g.name) : g.subtype;
  return ['Jersey', 'Sudadera'].contains(type) ? 'Intermedia' : 'Base';
}

bool validGarmentDetails(Object? value) {
  if (value is! Map ||
      !value.keys.every(
        [
          'size',
          'brand',
          'fabric',
          'washing',
          'style',
          'layer',
          'rain',
          'wind',
          'archive_reason',
          'needs_review',
          'type_review',
        ].contains,
      )) {
    return false;
  }
  for (final e in value.entries) {
    if (['rain', 'wind', 'needs_review', 'type_review'].contains(e.key)) {
      if (e.value is! bool) return false;
    } else if (e.value is! String || (e.value as String).length > 300) {
      return false;
    }
  }
  return (!value.containsKey('style') ||
          outfitStyles.contains(value['style'])) &&
      (!value.containsKey('layer') || garmentLayers.contains(value['layer']));
}

String normalizedSearch(String value) {
  var result = value.toLowerCase();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  for (final e in accents.entries) {
    result = result.replaceAll(e.key, e.value);
  }
  return result;
}

bool matchesGarmentSearch(Garment g, String query) {
  final words = normalizedSearch(query)
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final content = normalizedSearch(
    '${g.name} ${g.notes} ${g.subtype} ${g.category} ${g.details["size"] ?? ""} ${g.details["brand"] ?? ""} ${g.details["fabric"] ?? ""}',
  );
  return words.every(content.contains);
}

// UI grouping only: stored roles and recommendation layers remain precise.
bool matchesCategoryGroup(String group, String role) =>
    group == role || (group == 'Parte superior' && role == 'Abrigos');
List<String> typesForCategoryGroup(String group) => garmentTypes.entries
    .where((e) => matchesCategoryGroup(group, e.value))
    .map((e) => e.key)
    .toList();
