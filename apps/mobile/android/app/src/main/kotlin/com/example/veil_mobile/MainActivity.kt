package com.example.veil_mobile

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "veil/platform_security"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyPrivacyProtections()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "applyPrivacyProtections" -> {
                    applyPrivacyProtections()
                    result.success(null)
                }

                "getSecurityStatus" -> {
                    val integrityReasons = detectIntegrityCompromise()
                    result.success(
                        mapOf(
                            "appPreviewProtectionEnabled" to true,
                            "screenCaptureProtectionSupported" to true,
                            "screenCaptureProtectionEnabled" to isSecureFlagEnabled(),
                            "integrityCompromised" to integrityReasons.isNotEmpty(),
                            "integrityReasons" to integrityReasons,
                        ),
                    )
                }

                "excludePathFromBackup" -> {
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun applyPrivacyProtections() {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    private fun isSecureFlagEnabled(): Boolean {
        return window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0
    }

    private fun detectIntegrityCompromise(): List<String> {
        val reasons = mutableListOf<String>()

        if (Build.TAGS?.contains("test-keys") == true) {
            reasons += "Build tags indicate test-keys."
        }

        val suspiciousPaths = listOf(
            "/system/app/Superuser.apk",
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/su/bin/su",
            "/system/bin/.ext/.su",
            "/system/usr/we-need-root/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/data/local/su",
            "/system/bin/failsafe/su",
            "/system/xbin/daemonsu",
            "/init.magisk.rc",
            "/sbin/magisk",
        )
        if (suspiciousPaths.any { File(it).exists() }) {
            reasons += "Known root binaries were found on disk."
        }

        if (canExecuteSu()) {
            reasons += "Executable su binary is available."
        }

        return reasons.distinct()
    }

    private fun canExecuteSu(): Boolean {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            val exitCode = process.waitFor()
            exitCode == 0
        } catch (_: Exception) {
            false
        }
    }
}
