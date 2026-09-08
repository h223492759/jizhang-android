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
                "getSilent" -> {
                    // 静默模式：自动记账只弹 heads-up、不拉起 App（默认开启）
                    result.success(AutoRecordStore.isSilent(this))
                }
                "setSilent" -> {
                    val v = (call.arguments as? Map<*, *>)?.get("v") as? Boolean ?: false
                    AutoRecordStore.setSilent(this, v)
                    result.success(true)
                }
                "getPayMethods" -> {
                    // v2.2.0：当前启用的支付方式 id 列表（native 端为唯一事实源）
                    result.success(AutoRecordStore.enabledMethodIds(this).toList())
                }
                "setPayMethods" -> {
                    // v2.2.0：设置启用支付方式（Flutter 设置页勾选后同步；后台服务按此过滤）
                    val ids = (call.arguments as? Map<*, *>)?.get("ids")
                    val list = when (ids) {
                        is List<*> -> ids.mapNotNull { it?.toString() }
                        else -> emptyList()
                    }
                    AutoRecordStore.setPayMethods(this, list)
                    result.success(true)
                }
                "enabled" -> {
                    result.success(true)
                }
                "notifyRecorded" -> {
                    // v260908：Flutter 自动记账成功后统一弹一次「已记账」heads-up（不再逐条弹）
                    val body = (call.arguments as? Map<*, *>)?.get("body")?.toString() ?: ""
                    AutoRecordStore.postRecordedHeadsUp(this, body)
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
