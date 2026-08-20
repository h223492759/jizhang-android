package com.example.u_gen_tmp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * 自动记账：监听支付类 App 的通知，把解析后的信息写入待处理队列，
 * 并拉起主 Activity，由 Flutter 侧弹窗确认后记账。
 *
 * 检测到支付通知时同时在系统通知栏弹一条 heads-up（点开直接进入主界面），
 * 让用户即使在后台也能感知到"自动记账正在处理这笔"。
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
        // 抓一个金额作为通知摘要（取第一个 ¥/￥/元）
        val amtMatch = Regex("[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
            ?: Regex("([0-9]+(?:\\.[0-9]{1,2})?)\\s*元").find(all)
        val amt = amtMatch?.groupValues?.getOrNull(1) ?: ""
        val id = "${System.currentTimeMillis()}_${pkg}"
        val item = JSONObject()
            .put("id", id)
            .put("pkg", pkg)
            .put("title", title)
            .put("text", all)
            .put("time", sbn.postTime)
        AutoRecordStore.appendPending(this, item)
        // 在系统通知栏弹一条 heads-up
        postHeadsUp(pkg, title, amt)
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

    private fun postHeadsUp(pkg: String, title: String, amount: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureChannel(nm)
            // 点击通知 → 打开主界面
            val pi = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val src = when (pkg) {
                "com.eg.android.AlipayGphone" -> "支付宝"
                "com.tencent.mm", "com.tencent.wepay" -> "微信支付"
                "com.unionpay" -> "云闪付"
                else -> pkg
            }
            val titleStr = if (amount.isNotEmpty()) "检测到 $src ¥$amount" else "检测到 $src 通知"
            val body = if (title.isNotEmpty()) title else "自动记账已加入待处理"
            val n = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(titleStr)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_EVENT)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            nm.notify(NOTIFY_ID, n)
        } catch (_: Exception) {
        }
    }

    private fun ensureChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val ch = NotificationChannel(
            CHANNEL_ID, "自动记账",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "检测到支付类通知时弹出，点击进入主界面确认记账"
            enableVibration(true)
        }
        nm.createNotificationChannel(ch)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}

    companion object {
        const val CHANNEL_ID = "auto_record"
        const val NOTIFY_ID = 1001
    }
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
