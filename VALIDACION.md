# Validación — Mi Armario 1.7.6

No se ha ejecutado Flutter en este entorno; las pruebas históricas de versiones anteriores no acreditan esta entrega.

Verificar en Android: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`. Comprobar el mosaico con fondos uniformes, transparentes y fotografías reales; en todos los casos debe verse la prenda completa y centrada sin pérdida de la foto original. Comprobar que solo hay botón + superior en Armario, las cuatro secciones de edición, separación entre los selectores, y que capa/lluvia/viento se guardan igual que antes. Probar creación y edición de una prenda, prendas anteriores, outfits, Ideas, Hoy y copia/restauración con datos de prueba.

# Validación — Mi Armario 1.7.3

## Alcance real de esta entrega

Se revisó la estructura del ZIP 1.7.2 y se modificaron los fuentes de Flutter. **No se han ejecutado `flutter analyze`, `flutter test`, `flutter run` ni una compilación de APK**, por ausencia del SDK Flutter. Las 67 pruebas de la versión antigua descritas a continuación son resultados históricos, no certificación de 1.7.3.

## Validación recomendada en el móvil

1. `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`.
2. Verificar la barra de navegación y el inicio directo en Armario.
3. Añadir y editar prendas, desplegar todos los bloques y guardar sin perder campos.
4. Crear outfits con superior/inferior/abrigo/calzado, arrastrar y superponer prendas, guardar y reabrir comprobando posiciones.
5. Probar el selector de Hoy con y sin planificación; comprobar Ideas y el registro de uso.
6. Comprobar accesos de Más herramientas y restauración de copias **solo con una copia de prueba**.

## Limitaciones

El lienzo representa una composición 2D sugerida y no un maniquí 3D. El ZIP de origen no incluía `.git`; no se ha inventado ningún historial de commits. No se entrega APK 1.7.3 porque no se pudo compilar ni verificar firma.

---

# Validación — Mi Armario 1.7.1 reconstruida

Fecha: 13 de octubre de 2026.

## Comprobaciones realizadas

- Flutter 3.47.7 / Dart 3.13.5; análisis y suite completos ejecutados en esta entrega.
- Dependencias resueltas sin conexión con `pubspec.lock`; modelos nativos conservados.
- `flutter analyze --no-pub`: sin incidencias.
- `flutter test --no-pub`: **67 pruebas correctas**.
- Reconstrucción: deshacer uso con prendas originales tras editar outfit, lote de disponibilidad, conflicto tras edición posterior, referencias borradas, límite de diez acciones, limpieza al restaurar y deshacer semana.
- Búsqueda combinada por campos y normalización de acentos; validación de revisión y diagnóstico de exclusiones.
- UI: uso desde Hoy con lavado opcional, limpieza por selección y corrección de una detección dudosa a Pantalón sin SnackBar rutinario.
- Regresión: copias, migraciones, calendario, outfits, importación múltiple, herramientas, gestos del editor y preferencias, conforme a la suite recuperada.
- Capturas de Hoy, lavado y revisión inspeccionadas a 412 × 892; sin solapamientos. Las fotos se precargan en la prueba para permitir verificar su renderizado en Flutter Test.
- La base recuperada no contiene `.git`; no se ha eliminado ninguna carpeta Git.
- La clave privada recuperada tiene el mismo certificado SHA-256 que el APK 1.6.0 de referencia. Se conservan el identificador original y un código de versión mayor (10 frente a 8).

## APK

Compilación release completada correctamente (ARM64, aproximadamente 100 MB). Firma verificada con apksigner; certificado SHA-256 idéntico al APK 1.6.0 de referencia. Identificador `es.personal.mi_armario.local`, versión 1.7.1 y código 10 comprobados con aapt. El APK contiene solo bibliotecas ARM64; modelos empaquetados idénticos a los del proyecto.

## Pendiente en móvil físico

Instalación sobre la app existente con una copia previa y comprobación del armario real. Probar cámara/galería, importación por lotes, aislamiento de ropa, pincel, zoom, compartir PNG y selectores de archivos. Comprobar clasificación con fotos reales de pantalones: el modelo sigue siendo general y puede equivocarse; las propuestas dudosas requieren confirmación.

La suite no sustituye una prueba en S23 con Android 16. No se ha ejecutado una instalación en ese dispositivo desde este entorno.

## Revisión del código 1.7.2

- Se comprobó el código fuente y la existencia de los accesos a Ideas y Copias en el ZIP. No se pudo ejecutar Flutter en este entorno; los ajustes nuevos **no** han pasado aquí `flutter analyze`, `flutter test` ni una compilación Android. La validación de 67 pruebas indicada más arriba corresponde al paquete recibido y no certifica estas modificaciones.
- El ZIP recibido no incluye `.git`; no existe historial de commits verificable. No se incluye un APK nuevo hasta poder compilar y firmar con la clave compatible.

## Validación pendiente 1.7.4

Sin Flutter SDK en este entorno: ejecutar `flutter pub get`, `flutter analyze`, `flutter test` y `flutter run` en el móvil. Verificar cambio Libre/Maniquí sin perder prendas, arrastre independiente, eliminación/capas sincronizadas, tamaño, guardar en ambas vistas y reabrir (solo persiste vista activa).

### Versión 1.7.5
- Revisión estática de referencias de imagen, edición, secciones y callbacks.
- **Pendiente**: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run` en dispositivo Android y compilación release. Flutter SDK no está instalado en este entorno.
- Comprobar que las prendas con fondos/márgenes internos se ven completas y centradas, sin prometer recorte automático.
- Comprobar edición de todos los campos, fotografía, guardado y datos anteriores.


## Pendiente de validación: 1.7.7
Entorno de edición sin Flutter/Dart/Android SDK: **no se ha ejecutado** `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run` ni compilación de APK.
Verificar en el móvil: (1) apertura del selector en cuadrícula, filtro y búsqueda; (2) añadido y borrado de una prenda; (3) arrastre y tamaño en Libre; (4) recolocación y arrastre en Maniquí; (5) prioridad de capas y traer al frente; (6) guardar, cerrar y reabrir para comprobar ambas composiciones; (7) apertura de outfits anteriores tras migrar SQLite 5 a 6; (8) exportación, backups y restauración. No desinstalar la versión anterior antes de respaldar los datos.
