package com.example.u_gen_tmp

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * 自动记账：监听支付类 App 的通知，把解析后的信息写入待处理队列，
 * 并拉起主 Activity，由 Flutter 侧弹窗确认后记账。
 */
class AutoRecordListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (!AutoRecordStore.ALLOWED_PACKAGES.contains(pkg)) return
        val n: Notification = sbn.notification
        val extras = n.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val info = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val all = listOf(title, text, big, info).joinToString(" ") { it.trim() }.trim()
        if (all.length < 2) return
        // 简单过滤：不含金额/付款相关字样就不处理
        if (!all.contains("¥") && !all.contains("￥") && !all.contains("元") &&
            !all.contains("支付") && !all.contains("付款") && !all.contains("收款") &&
            !all.contains("转账") && !all.contains("消费") && !all.contains("支出")
        ) return
        val id = "${System.currentTimeMillis()}_${pkg}"
        val item = JSONObject()
            .put("id", id)
            .put("pkg", pkg)
            .put("title", title)
            .put("text", all)
            .put("time", sbn.postTime)
        AutoRecordStore.appendPending(this, item)
        // 拉起主界面（若已在后台则回到前台）
        val i = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("auto_record", id)
        }
        try {
            startActivity(i)
        } catch (_: Exception) {
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}
}

/** 待处理队列存储（SharedPreferences，JSON 数组） */
object AutoRecordStore {
    val ALLOWED_PACKAGES = setOf(
        "com.eg.android.AlipayGphone", // 支付宝
        "com.tencent.mm",              // 微信
        "com.unionpay",                // 云闪付
        "com.tencent.wepay",           // 微信支付组件
    )
    private const val KEY = "auto_record_queue"

    fun readPending(ctx: Context): List<String> {
        val sp = sp(ctx)
        return try {
            val arr = JSONArray(sp.getString(KEY, "[]") ?: "[]")
            (0 until arr.length()).map { arr.getJSONObject(it).toString() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun appendPending(ctx: Context, item: JSONObject) {
        val sp = sp(ctx)
        val cur = try {
            JSONArray(sp.getString(KEY, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        // 最多保留 50 条，防堆积
        while (cur.length() >= 50) cur.remove(0)
        cur.put(item)
        sp.edit().putString(KEY, cur.toString()).apply()
    }

    fun removePending(ctx: Context, id: String) {
        if (id.isEmpty()) return
        val sp = sp(ctx)
        val cur = try {
            JSONArray(sp.getString(KEY, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val out = JSONArray()
        for (i in 0 until cur.length()) {
            val o = cur.getJSONObject(i)
            if (o.optString("id") != id) out.put(o)
        }
        sp.edit().putString(KEY, out.toString()).apply()
    }

    private fun sp(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences("auto_record", Context.MODE_PRIVATE)
}
