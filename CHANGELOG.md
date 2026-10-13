## 1.7.6

- Encuadre automático no destructivo sobre fondos simples en Armario y editor; se evita reducir el tamaño útil de la prenda por márgenes del archivo.
- Eliminado botón flotante de añadir; se conserva el botón superior.
- Separadas opciones de uso/estilo de características avanzadas; etiquetas independientes y espaciado revisado.
- Conservados modelo, persistencia y herramientas existentes. Compilación y pruebas Flutter pendientes.

## 1.7.5 (2026-10-13)

- Armario: eliminados titular y eslogan; las fotos se muestran completas (`BoxFit.contain`) en sus tarjetas, sin recorte.
- Edición y alta: previsualización menos alta (205 px), fotografía centrada, espacio vertical reducido.
- Herramientas de foto agrupadas en panel plegado independiente: recortar/girar, analizar, pincel, quitar fondo y aislar ropa.
- Campos secundarios conservados en secciones plegables con etiquetas simplificadas y espaciado reducido; acciones y persistencia existentes sin alteraciones.
- Sin cambio de esquema de datos. Validación con Flutter y Android pendiente en entorno local.

## 1.7.4 (2026-10-13)

- Selector de composición Libre/Maniquí en creación y edición de outfits.
- Arrastre, escala y superposición disponibles en ambas vistas; orden sincronizado.
- Colocación inicial y botón de recolocación exclusivos de Maniquí, silueta oculta en Libre.
- Guardado/exportación de la vista activa, sin cambios de esquema.
- Revisión de documentación; compilación y pruebas Flutter pendientes.

## 1.7.3 (2026-10-13)

- Navegación: Armario, Outfits, Ideas, Hoy, Calendario; arranque en Armario.
- Hoy: selector de outfits guardados, ideas nuevas si no se ha elegido ninguno, visualización y cambio de conjunto.
- Armario: fotografías con tarjetas más grandes y menos separaciones.
- Prendas: jerarquía de secciones numeradas y fotografía destacada.
- Outfits: colocación sugerida por zonas, recolocación tipo maniquí, referencia de silueta y arrastre libre.
- Ideas: portada organizada con entrada al generador de propuestas existente.
- Más herramientas: opciones identificadas mediante iconografía.
- Persistencia: sin cambios de esquema; sin borrado de datos existentes.
- Verificación: pendiente análisis, tests y ejecución en dispositivo con Flutter.

# 1.7.2 — ajustes de interfaz (código fuente; APK no compilado aquí)

- Inicio en Armario, manteniendo Hoy e Ideas.
- Fotos sin texto en la cuadrícula, accesos a copias en Más herramientas.
- Aclaración de las categorías superiores/exteriores y revisión guiada de prenda.
- Paneles opcionales estables sin salto automático al desplegarlos.

# 1.7.1 — reconstruida desde 1.4.0

- Validación final: 67 pruebas, navegación inicial en Hoy y compatibilidad de plugins Kotlin al compilar.

- Reconstrucción de Hoy, sustituciones por motivo, alta simplificada, búsqueda ampliada, revisión, lavado, deshacer y diagnóstico de alternativas.
- Miniaturas en vínculos, exclusiones e historial; historial basado en usos registrados.
- Tipos filtrados por categoría, sugerencias débiles Por revisar y alternativas de reconocimiento.
- Composición ampliable y controles de foto visibles.
- Inicio en Hoy, tarjetas de Armario solo con imagen y acciones por pulsación larga.
- Parte superior incluye exteriores en filtros y tipos, manteniendo sus roles de capas.
- Revisión de prendas reorganizada, foto ampliable y paneles opcionales independientes.
- Copias movidas a Más herramientas e Ideas visible en navegación. Documentación actualizada.

# Cambios

## 1.3.0 — 12/10/2026

- Aislamiento de ropa puesta con intérprete CPU directo, normalización y softmax; detalle técnico de fallos.
- Nombre automático de ejemplo, descripción sugerida y respeto a edición manual.
- 29 tipos de prenda, filtro y reglas por papel para evitar conjuntos incoherentes.
- Ideas y semana con fotos ordenadas por categoría y cuadrícula compacta.
- Calendario con días planificados/usados y navegación de meses.
- SQLite/ZIP 4, lectura de formatos anteriores y firma conservada.

## 1.2.1 — 12/10/2026

- Reglas R8 explícitas para JNI de ONNX Runtime, MediaPipe y protobuf.
- Análisis de colores independiente del fallo de categoría y códigos de error visibles.
- Diferenciar error de recorte y error de análisis posterior.
- Ideas muestra guardadas/disponibles, categorías faltantes y revisión directa de prendas.
- Planificación manual con selección de prendas y confirmación al sustituir un día ocupado.
- Mensaje de semana ocupada separado de falta de combinaciones.

## 1.2.0 — 12/10/2026

- Disponibilidad disponible/en lavado/guardada, filtros y exclusión de sugerencias.
- Fijar prendas y sustituir una pieza; preferencias locales con valoraciones y reinicio.
- Semana revisable antes de guardar, intercambio de fechas libres y recuento de repeticiones.
- Prendas olvidadas, posibles duplicados y maletas con selección/checklist/sugerencia.
- Pincel de recorte con recuperación desde original, undo/redo y vista previa.
- Aviso semanal de copia en la app, aplazable y desactivable.
- SQLite/ZIP 3, importación de formatos 1/2/3; originales incluidos en copias.
- Firma/identificador de 1.1 conservados para actualización directa.

## 1.1.0 — 12/10/2026

- Colores, temporadas y ocasiones múltiples; nivel de abrigo.
- Importación por lotes con revisión individual.
- Recorte automático y sugerencias de categoría/colores ejecutados localmente.
- Ideas por clima, colores y uso; prenda ancla y planificación semanal.
- Temperatura manual o previsión por ciudad, caché y alternativa sin red.
- Uso histórico por prenda, ordenación por usos y fechas resistentes al horario de verano.
- SQLite 2 y formato ZIP 2, compatibles con los datos/copias de la primera versión.
- Guardado visible en el formulario, firma conservada externamente y APK ARM64 para S23.
- Instalación separada de 1.0.0 y traslado por copia ZIP para conservar la instalación anterior.

## 1.0.0

Armario local, cámara/galería/recorte manual, outfits visuales, calendario y copias ZIP.


## 1.7.7
- Selector de prendas en cuadrícula con búsqueda y categorías.
- Composición sin explicación redundante y fotografías encuadradas de mayor tamaño.
- Borrado mediante papelera y arrastre con un dedo.
- Maniquí con centrado automático por zona, recolocación y ajuste manual.
- Posiciones y escalas independientes persistidas para Libre y Maniquí (SQLite v6).
