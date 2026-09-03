package com.example.u_gen_tmp

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "jizhang/auto_record"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchPending" -> {
                    result.success(AutoRecordStore.readPending(this))
                }
                "removePending" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("id")?.toString() ?: ""
                    AutoRecordStore.removePending(this, id)
                    result.success(true)
                }
                "openNotifSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "openA11ySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "a11yEnabled" -> {
                    // 无障碍兜底通道是否已在系统设置中开启（读系统开关，无需权限）
                    val enabled = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                    ) ?: ""
                    val on = enabled.split(':').any {
                        it.contains("AutoRecordAccessibilityService")
                    }
                    result.success(on)
                }
                "enabled" -> {
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
