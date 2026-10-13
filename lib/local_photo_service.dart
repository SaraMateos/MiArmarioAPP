import 'package:flutter/services.dart';

class PhotoAnalysis {
  final String? category, suggestedName, warning;
  final List<String> colors, alternatives;
  final double confidence;
  const PhotoAnalysis({
    this.category,
    this.warning,
    this.suggestedName,
    required this.colors,
    this.confidence = 0,
    this.alternatives = const [],
  });
  factory PhotoAnalysis.fromMap(Map<Object?, Object?> m) => PhotoAnalysis(
    category: m['category'] as String?,
    warning: m['warning'] as String?,
    suggestedName: m['name'] as String?,
    colors: ((m['colors'] as List?) ?? []).cast<String>(),
    alternatives: ((m['alternatives'] as List?) ?? []).cast<String>(),
    confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
  );
}

class LocalPhotoService {
  static const _channel = MethodChannel('es.personal.mi_armario/local_photo');
  static Future<PhotoAnalysis> analyze(String path) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('analyze', {
      'path': path,
    });
    if (result == null) {
      throw const FormatException('No se ha podido analizar la foto.');
    }
    return PhotoAnalysis.fromMap(result);
  }

  static Future<Map<String, String>> editableBackground(
    String path, {
    bool worn = false,
    bool accessory = false,
  }) async {
    final result = await _channel.invokeMapMethod<String, String>(
      'editableBackground',
      {'path': path, 'worn': worn, 'accessory': accessory},
    );
    if (result == null) {
      throw const FormatException('No se ha podido recortar.');
    }
    return result;
  }

  static Future<String> removeBackground(
    String path, {
    bool worn = false,
    bool accessory = false,
  }) async {
    final result = await _channel.invokeMethod<String>('removeBackground', {
      'path': path,
      'worn': worn,
      'accessory': accessory,
    });
    if (result == null) {
      throw const FormatException('No se ha podido recortar la prenda.');
    }
    return result;
  }
}

String photoErrorMessage(Object error) {
  if (error is PlatformException) {
    final detail = error.details;
    final type = detail is Map ? detail['type'] : null;
    final reason = detail is Map ? detail['reason'] : null;
    return '${error.message ?? 'No se ha podido procesar la foto.'}${type is String ? ' Código: $type.' : ''}${reason is String && reason.isNotEmpty ? ' Detalle: $reason' : ''}';
  }
  return 'No se ha podido procesar la foto. Puedes conservarla y completar los datos manualmente.';
}
