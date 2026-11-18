package com.goldenbridge.pay

import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity est requis par local_auth (biométrie).
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Bloque captures et enregistrements d'écran, et masque l'aperçu dans le multitâche.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.goldenbridge.pay/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceStatus" -> result.success(
                        mapOf(
                            "rooted" to isRooted(),
                            "emulator" to isEmulator(),
                            "developerMode" to isDeveloperMode(),
                            "screenProtected" to true,
                        )
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun isRooted(): Boolean {
        if (Build.TAGS?.contains("test-keys") == true) return true
        val paths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/su", "/su/bin/su",
            "/data/local/su", "/data/local/bin/su", "/data/local/xbin/su", "/system/app/Superuser.apk",
            "/data/adb/magisk", "/sbin/.magisk", "/system/bin/.ext/su",
        )
        return paths.any { runCatching { File(it).exists() }.getOrDefault(false) }
    }

    private fun isEmulator(): Boolean =
        Build.FINGERPRINT.startsWith("generic") || Build.FINGERPRINT.contains("emulator") ||
            Build.MODEL.contains("Emulator") || Build.MODEL.contains("Android SDK built for") ||
            Build.HARDWARE.contains("goldfish") || Build.HARDWARE.contains("ranchu") ||
            Build.PRODUCT.contains("sdk")

    private fun isDeveloperMode(): Boolean = runCatching {
        Settings.Global.getInt(contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) != 0
    }.getOrDefault(false)
}
