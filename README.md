# Mi Armario 1.7.8

Aplicación Android en español para organizar prendas, componer outfits y planificar su uso. Los datos y fotos se guardan en SQLite y en la carpeta privada del móvil. El análisis de imágenes se realiza localmente; solo la consulta opcional del tiempo necesita Internet.

Esta revisión parte del proyecto recuperado de la **1.4.0**. Reconstruye las ocho mejoras acordadas para la 1.5 y añade las mejoras de imágenes, categorías y composición. No es una recuperación exacta del código perdido de la 1.5 o la 1.6.

## Uso

La app abre en **Armario**. Barra inferior: **Armario, Outfits, Ideas, Hoy, Calendario**. Las tarjetas muestran la foto con encuadre automático para fondos simples. Toca la foto para editar. El botón ⋯ y la pulsación larga abren disponibilidad, favoritas y otras acciones. «Parte superior» incluye también abrigos, chaquetas, americanas y chalecos, conservando su función de capa.

- **Hoy:** si no hay outfit asignado, permite elegir uno guardado o abrir Ideas para obtener propuestas; si está asignado, muestra el conjunto, permite cambiarlo y registrar el uso (con opción de lavado). La meteorología permanece en Ideas.
- **Armario:** alta y edición con foto, nombre y categoría/tipo; los campos opcionales se separan en bloques de colores/temporadas/ocasiones, uso/estilo, características avanzadas (capas/lluvia/viento), talla/marca/tejido/lavado y notas/archivo. Cámara, galería, detección, recorte, aislamiento y pincel conservan botones visibles. El nombre sugerido es editable.
- **Búsqueda:** combina palabras de nombre, notas, tipo, categoría, marca, talla y tejido. No distingue mayúsculas ni acentos en vocales. Los filtros se combinan. Los filtros adicionales y el orden activo se muestran debajo del buscador y se pueden quitar por separado.
- **Alta por lotes:** selecciona hasta 30 fotos. Puedes analizarlas juntas, confirmar el tipo de cada una y aplicar una temporada y una ocasión comunes. «Guardar lote» añade todas las seleccionadas. Las detecciones dudosas se guardan como «Por revisar» y puedes reintentar las fotos que fallen. Para ajustar todos los datos o revisar posibles duplicados, abre la ficha completa. Las prendas ya guardadas se conservan al salir.
- **Detección:** propone tipos y colores; las sugerencias débiles o contradictorias llevan «Por revisar». Ofrece tipos alternativos cuando el modelo los devuelve. Confirma o corrige el tipo; no garantiza reconocer pantalones ni otras prendas correctamente.
- **Outfits:** disposición inicial por zonas aproximadas del cuerpo, modo Maniquí con colocación inicial por tipo, arrastre, superposición, escala y orden de prendas, guardar fotos de referencia y exportar PNG. Libre y Maniquí conservan posiciones y tamaños independientes, con un orden de capas compartido. Puedes poner un nombre al outfit o usar el generado. Al abrir outfits anteriores sin posición asignada para el maniquí, la app coloca las prendas por tipo. Las composiciones guardadas se pueden ampliar a pantalla completa y explorar con zoom.
- **Ideas:** portada más sencilla para entrar al generador; colores, clima manual/por ciudad, estilos, capas, uso reciente, exclusiones por día y conjuntos vinculados. Ajustar permite sustituir por frío, otro color o menor formalidad. Filtra alternativas que rompan capas, ocasión o vínculos. Planificación semanal editable con fotos. Las propuestas destacan sus motivos principales y, cuando faltan opciones, ofrecen accesos para confirmar tipos, revisar exclusiones o cambiar de ocasión.
- **Calendario:** un outfit por día; marca días planificados y usados. El historial guarda los identificadores de las prendas realmente usadas aunque luego se cambie el outfit.
- **Más herramientas:** selector con iconos y accesos a vínculos y utilidades; vinculaciones con miniaturas, compras, historial con fotos desplegables, archivo, edición por lotes, prendas olvidadas, duplicados, maletas, revisión de fichas y lavado por selección.
- **Deshacer:** últimas diez acciones de calendario, planificación semanal o cambios por lote. Una edición posterior de los datos afectados impide la reversión. Al deshacer una semana se conservan los outfits creados y se retiran sus asignaciones. No deshace borrados, cambios de fotos ni restauraciones.
- **Copias:** exportar/restaurar ZIP desde Más herramientas; recordatorio semanal dentro de la app. Restaurar sustituye el armario actual. Las copias no están cifradas.

No hay tareas en segundo plano ni notificaciones programadas del sistema. La aplicación no requiere cuenta, servidor ni suscripción.

## Actualización

Antes de instalar un APK nuevo, exporta una copia desde tu aplicación actual. No desinstales ni borres datos. La configuración conserva `es.personal.mi_armario.local`; debe firmarse con la clave privada externa recuperada, cuyo certificado coincide con el APK 1.6.0 comprobado. No se incluyen claves privadas en este proyecto.

La restauración lee los formatos 1 a 6, incluidos los ZIP de la 1.7.7 que contienen los datos del maniquí con el identificador del formato 5. Las copias nuevas usan el formato 6 y guardan ambas composiciones. Una app antigua puede rechazar ese formato. Se conserva el indicador de revisión `type_review` de la 1.6. La actualización física y la importación de una copia real del usuario deben verificarse en el móvil.

## Desarrollo y compilación

Requisitos: Flutter 3.47.7 / Dart 3.13.5, JDK 17, Android SDK 36, Build Tools 36.0.0, NDK 28.2.13676358 y CMake 3.22.1. Bibliotecas Dart: `pubspec.yaml` y `pubspec.lock`; motores nativos y modelos: documentación técnica y avisos de terceros.

```powershell
$env:ARMARIO_SIGNING_KEY = 'RUTA_LOCAL_A_LA_CLAVE_PRIVADA'
.\COMPILAR_APK.ps1
```

El script obtiene dependencias, ejecuta análisis y pruebas, y compila ARM64. APK: `build/app/outputs/flutter-apk/app-release.apk`. GitHub Actions ejecuta análisis y pruebas de Flutter al abrir o actualizar un pull request y al subir cambios a `main`. Se detiene si falta la clave o falla una comprobación. Para desarrollo: `flutter pub get`, `flutter run -d ID_DEL_MOVIL`.

## Diagnóstico

Si una foto no puede analizarse, se conserva y puedes completar el tipo manualmente. En fotos con una persona o varias prendas, recorta primero la prenda que quieres guardar. Las propuestas requieren una base y una parte inferior, o un vestido/mono; revisa disponibilidad, exclusiones y conjuntos vinculados si faltan alternativas.

No hay archivo de logs de usuario ni códigos de salida propios de la app. Android registra errores nativos en Logcat. Para desarrollo usa `flutter logs`; no adjuntes imágenes privadas ni copias completas a incidencias públicas. El script de compilación propaga fallos como errores de PowerShell.

Consulta [DOCUMENTACION_TECNICA.md](DOCUMENTACION_TECNICA.md) y [VALIDACION.md](VALIDACION.md).

La vista de composición ajusta el encuadre al conjunto de prendas para aprovechar el lienzo (hasta 2,2×) y ofrece zoom a pantalla completa. El editor conserva las coordenadas y escalas guardadas. Las detecciones pendientes de confirmar se excluyen de propuestas automáticas, con explicación en Ideas.

## Historial de interfaz

### Cambios en 1.7.3

Esta entrega modifica la navegación, el resumen de Hoy, la presentación del acceso a Ideas, el selector de Más herramientas, el mosaico de Armario y el lienzo del editor de outfits. No modifica el esquema SQLite ni elimina información ya guardada. El editor de prendas mejora la jerarquía visual de los bloques, conservando campos y detección. La silueta es una referencia 2D y no un avatar 3D ni un ajuste automático de las imágenes.

**Validación pendiente:** Flutter no está disponible en el entorno de edición; ejecutar `flutter pub get`, `flutter analyze`, `flutter test` y `flutter run` antes de generar release. Algunos tests heredados basados en la portada anterior podrían necesitar ajustar expectativas.

## Cambios en 1.7.4

En Crear/Editar outfit se puede alternar entre **Libre** y **Maniquí**. Cada modo mantiene sus posiciones y tamaños durante la edición; permite arrastrar, escalar y cambiar el orden de las prendas. El maniquí utiliza una silueta de orientación y una distribución inicial por tipo de prenda, no representa un avatar real ni prueba virtual de ropa. El botón «Recolocar sobre el maniquí» reinicia únicamente la distribución de esa vista. **Al guardar se persiste solo la composición del modo activo** en el formato SQLite actual; al volver a abrir, la vista maniquí se reconstruye desde los tipos de prenda, por lo que no guarda independientemente sus posiciones anteriores. No se modifica el formato de copias. Validación Flutter pendiente.

### Interfaz 1.7.5
El Armario muestra las fotografías completas y centradas sin textos introductorios. En Añadir/Editar prenda la previsualización es más compacta, los datos básicos se mantienen visibles y las herramientas de imagen y los datos complementarios están en paneles plegables. Las imágenes que incluyan márgenes dentro del propio archivo pueden requerir «Recortar / girar foto» para que la prenda se vea más grande.

## Ajustes de 1.7.6

- El Armario mantiene únicamente el botón **+** superior para añadir prendas; en Outfits se conserva su acceso superior.
- El encuadre visual automático detecta prendas sobre fondos transparentes o aproximadamente uniformes y reduce el margen vacío, sin tocar las fotografías guardadas ni modificar las copias. En fondos complejos conserva el encuadre original, que puede ajustarse con las herramientas fotográficas existentes.
- Añadir/Editar prenda muestra la fotografía en una tarjeta mediana con encuadre más ajustado. Las opciones de **Uso y estilo** están separadas de **Características avanzadas** (capa, lluvia y viento). Los desplegables usan etiquetas exteriores y márgenes verticales.
- No cambia el almacenamiento SQLite, el formato de copia ni la lógica de guardado.
- **Pendiente de validar:** `flutter pub get`, `flutter analyze`, `flutter test` y `flutter run` en Android; verificar encuadres con fondos difíciles, edición, secciones, y actualización de instalación existente sin borrar datos.


## Outfits (1.7.7)
- El selector de prendas utiliza búsqueda, filtros por categoría y una cuadrícula fotográfica de dos columnas.
- La composición Libre permite arrastrar con un dedo; el tamaño se controla mediante el deslizador y el borrado se hace con el icono de papelera.
- Maniquí coloca las prendas inicialmente por tipo y permite ajustes manuales. «Recolocar sobre el maniquí» reinicia esa distribución.
- Ambas vistas guardan por separado posición y tamaño en SQLite.
