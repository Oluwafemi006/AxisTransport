package com.axistransport.axis_transport_flutter

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity : exigée par local_auth (invite biométrique).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Enregistrement d'un fichier dans Téléchargements via MediaStore (aucune permission requise).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "axis/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("unsupported", "Android 10 ou plus récent requis.", null)
                    return@setMethodCallHandler
                }
                try {
                    val name = call.argument<String>("name")!!
                    val bytes = call.argument<ByteArray>("bytes")!!
                    val folder = Environment.DIRECTORY_DOWNLOADS + "/Axis Transport"
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, name)
                        put(MediaStore.Downloads.MIME_TYPE, call.argument<String>("mime") ?: "application/pdf")
                        put(MediaStore.Downloads.RELATIVE_PATH, folder)
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val resolver = applicationContext.contentResolver
                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Création du fichier impossible.")
                    resolver.openOutputStream(uri)!!.use { it.write(bytes) }
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                    result.success("$folder/$name")
                } catch (error: Exception) {
                    result.error("save_failed", error.message, null)
                }
            }
    }
}
