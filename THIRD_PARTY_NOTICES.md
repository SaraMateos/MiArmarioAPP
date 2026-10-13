# Componentes y modelos de terceros

## Modelos empaquetados
Las fotos se procesan con estos archivos incluidos en el APK. No se descargan modelos al usar la app.

- U²-NetP: arquitectura U²-Net, Xuebin Qin y colaboradores. ONNX distribuido por rembg. Segmentación del objeto principal; no identifica por sí solo prendas en una persona.
- SelfieMulticlass 256×256: Google MediaPipe. Se usa la clase clothes (4) y, para calzado/accesorios, others (5). Conserva la ropa de la imagen recortada; no separa automáticamente varias prendas individuales.
- EfficientNet-Lite0: Google MediaPipe. Clasificador general ImageNet; no es un clasificador especializado de armario. Sus etiquetas de ropa se traducen a categorías generales, con umbral de confianza 0,25. Puede no reconocer una prenda.

Fuentes y hashes exactos: android/app/src/main/assets/models/manifest.json.
Licencias/notices upstream: licenses/U2NET_LICENSE.txt y licenses/MEDIAPIPE_LICENSE.txt. Conservar los avisos de autoría y licencia al redistribuir modelos o código de terceros.

## Bibliotecas
Flutter/Dart, MediaPipe Tasks, ONNX Runtime, sqflite y los paquetes indicados en pubspec.lock conservan sus licencias originales. MediaPipe y ONNX Runtime se integran como dependencias Android mediante Maven. El código y licencias de los proyectos upstream son las referencias canónicas:
- https://github.com/google-ai-edge/mediapipe
- https://github.com/microsoft/onnxruntime
- https://github.com/xuebinqin/U-2-Net
- https://github.com/danielgatis/rembg

## Tiempo
Las previsiones y búsqueda de ciudades proceden de Open-Meteo:
https://open-meteo.com/
Se muestra atribución en la app. La API pública se usa para este proyecto personal no comercial, sin clave API. Para distribuir una versión comercial hay que revisar las condiciones vigentes del proveedor.

## Intérprete de ropa puesta (1.3)
LiteRT Interpreter y litert-api 1.4.2 de Google AI Edge: https://github.com/google-ai-edge/LiteRT . Se integran como dependencias Maven Android conservando sus licencias upstream. El modelo SelfieMulticlass permanece igual; ahora se ejecuta directamente por CPU, con normalización de su metadata y softmax de logits.
