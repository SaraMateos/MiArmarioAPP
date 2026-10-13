package es.personal.mi_armario

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var processor: LocalPhotoProcessor? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        processor = LocalPhotoProcessor(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "es.personal.mi_armario/local_photo")
            .setMethodCallHandler { call, result ->
                if (call.method != "analyze" && call.method != "removeBackground" && call.method != "editableBackground") { result.notImplemented(); return@setMethodCallHandler }
                val path = call.argument<String>("path")
                if (path == null) { result.error("input", "Falta una foto local.", null); return@setMethodCallHandler }
                executor.execute {
                    try {
                        val output: Any? = if (call.method == "analyze") processor!!.analyze(path)
                            else processor!!.removeBackground(path, call.argument<Boolean>("worn") ?: false, call.argument<Boolean>("accessory") ?: false, call.method == "editableBackground")
                        main.post { result.success(output) }
                    } catch (e: Throwable) {
                        val code = e.javaClass.simpleName
                        val reason = (e.message ?: "").replace(path, "[foto local]").replace(Regex("/[A-Za-z0-9_.:/-]+"), "[ruta local]").take(300)
                        val explanation = when (e) {
                            is OutOfMemoryError -> "No hay memoria suficiente para procesar la foto. Prueba con una imagen más pequeña."
                            is UnsatisfiedLinkError, is NoClassDefFoundError, is NoSuchMethodError -> "No se ha podido iniciar el motor local de fotos."
                            is IllegalArgumentException -> "No se ha podido leer la foto o encontrar una máscara válida. Prueba a recortar primero la prenda."
                            else -> "No se ha podido procesar la foto en el móvil."
                        }
                        main.post { result.error("local_photo", explanation, mapOf("operation" to call.method, "type" to code, "reason" to reason)) }
                    }
                }
            }
    }
    override fun onDestroy() {
        executor.execute { processor?.close() }
        executor.shutdown()
        super.onDestroy()
    }
}
