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
