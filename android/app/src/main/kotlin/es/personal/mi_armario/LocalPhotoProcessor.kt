package es.personal.mi_armario

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imageclassifier.ImageClassifier
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.io.File
import java.nio.FloatBuffer
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

/** Bundled models only. This class contains no network operations. */
class LocalPhotoProcessor(private val context: Context) : AutoCloseable {
    private var classifier: ImageClassifier? = null
    private var clothingInterpreter: Interpreter? = null
    private var saliency: OrtSession? = null
    private val environment by lazy { OrtEnvironment.getEnvironment() }

    private fun read(path: String): Bitmap {
        val file = File(path).canonicalFile
        val bases = listOf(File(context.applicationInfo.dataDir)) + context.externalCacheDirs.filterNotNull()
        require(bases.any { file.path.startsWith(it.canonicalPath + File.separator) })
        require(file.isFile)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > 1600) sample *= 2
        val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: error("Image cannot be decoded")
        val orientation = try { ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1) } catch (_: Exception) { 1 }
        val matrix = Matrix()
        when (orientation) {
            2 -> matrix.setScale(-1f, 1f)
            3 -> matrix.setRotate(180f)
            4 -> matrix.setScale(1f, -1f)
            5 -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
            6 -> matrix.setRotate(90f)
            7 -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
            8 -> matrix.setRotate(270f)
        }
        val oriented = if (matrix.isIdentity) decoded else Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true).also { decoded.recycle() }
        return if (oriented.config == Bitmap.Config.ARGB_8888) oriented else oriented.copy(Bitmap.Config.ARGB_8888, false).also { oriented.recycle() }
    }
    private fun getClassifier(): ImageClassifier {
        if (classifier == null) {
            val options = ImageClassifier.ImageClassifierOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath("models/efficientnet_lite0.tflite").build())
                .setRunningMode(RunningMode.IMAGE).setMaxResults(40).build()
            classifier = ImageClassifier.createFromOptions(context, options)
        }
        return classifier!!
    }
    fun analyze(path: String): Map<String, Any?> {
        val bitmap = read(path)
        try {
            val white = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(white)
            canvas.drawColor(Color.WHITE)
            canvas.drawBitmap(bitmap, 0f, 0f, null)
            val input = BitmapImageBuilder(white).build()
            var category: String? = null
            var name: String? = null
            var confidence = 0.0
            var warning: String? = null
            val alternatives = linkedMapOf<String, Pair<String, Double>>()
            try {
                val results = getClassifier().classify(input)
                for (classification in results.classificationResult().classifications()) {
                    for (item in classification.categories()) {
                        val mapped = mapLabel(item.categoryName().lowercase())
                        if (mapped != null && item.score() >= 0.05f) {
                            val previous = alternatives[mapped.second]
                            if (previous == null || item.score() > previous.second) alternatives[mapped.second] = mapped.first to item.score().toDouble()
                        }
                        if (mapped != null && item.score() >= 0.05f && item.score() > confidence) {
                            category = mapped.first
                            name = mapped.second
                            confidence = item.score().toDouble()
                        }
                    }
                }
            } catch (e: Throwable) {
                warning = "Categoría automática no disponible (" + e.javaClass.simpleName + "). Puedes elegirla manualmente; los colores se calculan por separado."
            } finally { input.close(); white.recycle() }
            if (warning == null && alternatives.values.any { it.first != category && it.second >= confidence * 0.75 }) {
                warning = "Hay varias categorías posibles. Confirma el tipo de prenda."
            }
            return mapOf("category" to category, "name" to name, "confidence" to confidence, "colors" to dominantColors(bitmap), "warning" to warning, "alternatives" to alternatives.entries.sortedByDescending { it.value.second }.take(5).map { it.key })
        } finally { bitmap.recycle() }
    }
    private fun mapLabel(label: String): Pair<String, String>? {
        val mappings = listOf(
            Triple(listOf("jersey", "sweatshirt", "pullover", "cardigan"), "Parte superior", "Jersey"),
            Triple(listOf("t-shirt", "tee shirt", "shirt"), "Parte superior", "Camiseta"),
            Triple(listOf("jean", "denim"), "Parte inferior", "Vaqueros"),
            Triple(listOf("trouser", "pant", "slack", "pajama"), "Parte inferior", "Pantalón"),
            Triple(listOf("short", "bermuda"), "Parte inferior", "Shorts"),
            Triple(listOf("legging", "tights"), "Parte inferior", "Leggings"),
            Triple(listOf("miniskirt", "hoopskirt", "sarong"), "Parte inferior", "Falda"),
            Triple(listOf("gown", "dress"), "Vestidos", "Vestido"),
            Triple(listOf("trench coat", "fur coat", "poncho", "raincoat", "jacket", "suit"), "Abrigos", "Abrigo"),
            Triple(listOf("running shoe", "sneaker"), "Calzado", "Zapatillas"),
            Triple(listOf("sandal"), "Calzado", "Sandalias"),
            Triple(listOf("loafer", "clog"), "Calzado", "Zapatos"),
            Triple(listOf("boot"), "Calzado", "Botas"),
            Triple(listOf("handbag", "backpack", "purse", "hat", "sunglass", "scarf", "belt"), "Accesorios", "Accesorio")
        )
        for ((words, category, name) in mappings) if (words.any { label.contains(it) }) return category to name
        return null
    }
    private fun colorName(pixel: Int): String {
        val hsv = FloatArray(3)
        Color.colorToHSV(pixel, hsv)
        val h = hsv[0]; val s = hsv[1]; val v = hsv[2]
        if (v < .19f) return "Negro"
        if (s < .12f) return if (v > .82f) "Blanco" else "Gris"
        if (h in 15f..55f && s < .42f && v > .65f) return "Beige"
        if (h in 8f..55f && v < .58f) return "Marrón"
        return when {
            h < 12f || h >= 345f -> if (v > .7f && s < .55f) "Rosa" else "Rojo"
            h < 42f -> "Naranja"
            h < 68f -> "Amarillo"
            h < 170f -> "Verde"
            h < 265f -> "Azul"
            h < 315f -> "Morado"
            else -> "Rosa"
        }
    }
    private fun dominantColors(bitmap: Bitmap): List<String> {
        val small = Bitmap.createScaledBitmap(bitmap, 96, 96, true)
        try {
            val pixels = IntArray(96 * 96); small.getPixels(pixels, 0, 96, 0, 0, 96, 96)
            val transparent = pixels.any { Color.alpha(it) < 80 }
            val counts = mutableMapOf<String, Int>()
            for (y in 10 until 86) for (x in 10 until 86) {
                val pixel = pixels[y * 96 + x]
                if (Color.alpha(pixel) < 180) continue
                if (!transparent && (x < 16 || x > 80 || y < 16 || y > 80)) continue
                val name = colorName(pixel)
                counts[name] = (counts[name] ?: 0) + 1
            }
            val total = counts.values.sum().coerceAtLeast(1)
            return counts.entries.sortedByDescending { it.value }.filter { it.value.toDouble() / total >= .12 }.take(3).map { it.key }
        } finally { small.recycle() }
    }
    private fun clothingMask(bitmap: Bitmap, accessory: Boolean): Bitmap {
        if (clothingInterpreter == null) {
            val bytes = context.assets.open("models/selfie_multiclass.tflite").use { it.readBytes() }
            val model = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply { put(bytes); rewind() }
            clothingInterpreter = Interpreter(model, Interpreter.Options().setNumThreads(2))
        }
        val interpreter = clothingInterpreter!!
        val shape = interpreter.getInputTensor(0).shape()
        require(shape.size == 4 && shape[0] == 1 && shape[3] == 3)
        val height = shape[1]; val width = shape[2]
        val resized = Bitmap.createScaledBitmap(bitmap, width, height, true)
        val pixels = IntArray(width * height)
        resized.getPixels(pixels, 0, width, 0, 0, width, height)
        if (resized !== bitmap) resized.recycle()
        val input = ByteBuffer.allocateDirect(pixels.size * 3 * 4).order(ByteOrder.nativeOrder())
        for (pixel in pixels) {
            input.putFloat((Color.red(pixel) - 127.5f) / 127.5f)
            input.putFloat((Color.green(pixel) - 127.5f) / 127.5f)
            input.putFloat((Color.blue(pixel) - 127.5f) / 127.5f)
        }
        input.rewind()
        val outputShape = interpreter.getOutputTensor(0).shape()
        require(outputShape.size == 4 && outputShape[0] == 1 && outputShape[3] == 6)
        val outHeight = outputShape[1]; val outWidth = outputShape[2]
        val output = ByteBuffer.allocateDirect(outWidth * outHeight * 6 * 4).order(ByteOrder.nativeOrder())
        interpreter.run(input, output); output.rewind()
        val mask = IntArray(outWidth * outHeight)
        for (i in mask.indices) {
            val logits = FloatArray(6) { output.float }
            val largest = logits.maxOrNull()!!
            var total = 0.0; var selected = 0.0
            for (category in 0..5) {
                val weight = Math.exp((logits[category] - largest).toDouble())
                total += weight
                if (category == 4 || (accessory && category == 5)) selected += weight
            }
            val clothes = (selected / total).toFloat()
            val alpha = ((clothes.coerceIn(0f,1f) - .35f) / .3f * 255f).toInt().coerceIn(0,255)
            mask[i] = Color.argb(alpha,255,255,255)
        }
        return Bitmap.createBitmap(mask,outWidth,outHeight,Bitmap.Config.ARGB_8888)
    }
    private fun foregroundMask(bitmap: Bitmap): Bitmap {
        if (saliency == null) {
            val options = OrtSession.SessionOptions().apply { setIntraOpNumThreads(2); setInterOpNumThreads(1) }
            try { saliency = environment.createSession(context.assets.open("models/u2netp.onnx").use { it.readBytes() }, options) }
            finally { options.close() }
        }
        val resized = Bitmap.createScaledBitmap(bitmap, 320, 320, true)
        val rgb = IntArray(320 * 320); resized.getPixels(rgb, 0, 320, 0, 0, 320, 320); resized.recycle()
        val size = rgb.size
        val data = FloatArray(size * 3)
        val means = floatArrayOf(.485f, .456f, .406f)
        val deviations = floatArrayOf(.229f, .224f, .225f)
        val maximum = rgb.maxOf { max(Color.red(it), max(Color.green(it), Color.blue(it))) }.coerceAtLeast(1).toFloat()
        for (i in rgb.indices) {
            val values = intArrayOf(Color.red(rgb[i]), Color.green(rgb[i]), Color.blue(rgb[i]))
            for (c in 0..2) data[c * size + i] = (values[c] / maximum - means[c]) / deviations[c]
        }
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(data), longArrayOf(1, 3, 320, 320)).use { tensor ->
            saliency!!.run(mapOf(saliency!!.inputNames.first() to tensor)).use { outputs ->
                val buffer = (outputs.get(0) as OnnxTensor).floatBuffer
                val values = FloatArray(size); buffer.get(values)
                val low = values.minOrNull()!!; val high = values.maxOrNull()!!
                require(high - low > .01f)
                val mask = IntArray(size) { i ->
                    val alpha = (((values[i] - low) / (high - low) - .15f) / .7f * 255).toInt().coerceIn(0, 255)
                    Color.argb(alpha, 255, 255, 255)
                }
                return Bitmap.createBitmap(mask, 320, 320, Bitmap.Config.ARGB_8888)
            }
        }
    }
    fun removeBackground(path: String, worn: Boolean, accessory: Boolean, editable: Boolean = false): Any {
        val bitmap = read(path)
        try {
            val mask = if (worn) clothingMask(bitmap, accessory) else foregroundMask(bitmap)
            val scaled = Bitmap.createScaledBitmap(mask, bitmap.width, bitmap.height, true)
            val original = IntArray(bitmap.width * bitmap.height)
            val alphas = IntArray(original.size)
            bitmap.getPixels(original, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            scaled.getPixels(alphas, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            if (scaled !== mask) scaled.recycle()
            mask.recycle()
            var count = 0; var left = bitmap.width; var top = bitmap.height; var right = 0; var bottom = 0
            for (i in original.indices) {
                val alpha = Color.alpha(original[i]) * Color.alpha(alphas[i]) / 255
                original[i] = (original[i] and 0x00ffffff) or (alpha shl 24)
                if (alpha > 60) {
                    count++; val x = i % bitmap.width; val y = i / bitmap.width
                    left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                }
            }
            require(count > original.size / 100 && right > left && bottom > top)
            // Return a transparent PNG; original is never overwritten.
            val result = Bitmap.createBitmap(original, bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val margin = max(bitmap.width, bitmap.height) / 50
            left = (left - margin).coerceAtLeast(0); top = (top - margin).coerceAtLeast(0)
            right = (right + margin).coerceAtMost(bitmap.width - 1); bottom = (bottom + margin).coerceAtMost(bitmap.height - 1)
            val cropped = if (editable) result else Bitmap.createBitmap(result, left, top, right - left + 1, bottom - top + 1)
            val file = File(context.cacheDir, "wardrobe_cutout_" + UUID.randomUUID() + ".png")
            try { file.outputStream().use { require(cropped.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
            finally { if(cropped !== result) cropped.recycle(); result.recycle() }
            if (editable) {
                val source = File(context.cacheDir, "wardrobe_source_" + UUID.randomUUID() + ".png")
                source.outputStream().use { require(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                return mapOf("path" to file.path, "source" to source.path)
            }
            return file.path
        } finally { bitmap.recycle() }
    }
    override fun close() { classifier?.close(); clothingInterpreter?.close(); saliency?.close() }
}
