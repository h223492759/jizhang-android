package com.example.u_gen_tmp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.util.Log
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * 自动记账：监听支付类 App 的通知，必须命中强信号词（支付成功/到账/收款等）
 * 才写入待处理队列 + 弹 heads-up。营销/虚拟积分类通知直接丢弃，
 * 避免"检测到但没记账"的误导。
 *
 * 命中后：① 入队 ② 弹 heads-up（点开直接进入主界面）
 * 让用户即使在后台也能感知到"自动记账正在处理这笔"。
 */
class AutoRecordListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (!AutoRecordStore.ALLOWED_PACKAGES.contains(pkg)) {
            Log.d("AutoRecord", "skip pkg not in whitelist: $pkg")
            return
        }
        val n: Notification = sbn.notification
        val extras = n.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val info = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val all = listOf(title, text, big, info).joinToString(" ") { it.trim() }.trim()
        Log.d("AutoRecord", "onPosted pkg=$pkg all=${all.take(200)}")
        if (all.length < 2) return
        // 强信号词过滤（与 Flutter _parse 一致）：必须是支付/收款完成类通知才入队 + 弹 heads-up
        // 营销/虚拟积分通知（含金额/收款字眼但不是真实账单）直接丢弃，避免"检测到但没记账"误导
        val strongKw = listOf(
            "支付成功", "付款成功", "成功付款", "支付成功通知", "已支付", "已付款",
            "收款成功", "已收款", "收款通知", "收款到账",
            "转账成功", "转账", "已存入", "收到转账", "转入",
            "扣款成功", "已扣款", "已消费", "消费", "扣款", "交易提醒",
            "入账", "到账", "还款成功", "已还款", "退款成功", "已退款"
        )
        // 虚拟积分类（含"到账"也不记账）
        val virtualKw = listOf(
            "积分", "金币", "京豆", "里程", "成长值", "信用分", "蚂蚁积分",
            "积分到账", "积分入账", "返积分", "送积分", "领积分", "待领取",
            "金币到账", "星星", "等级", "经验值", "会员积分"
        )
        val hasStrong = strongKw.any { all.contains(it) }
        Log.d("AutoRecord", "hasStrong=$hasStrong amt=$amt")
        if (!hasStrong) return  // 没强信号词一律不入队（如营销「邀请店主领用收钱码可得20元」）
        if (virtualKw.any { all.contains(it) }) return  // 虚拟积分直接丢弃
        // 抓一个金额作为通知摘要（取第一个 ¥/￥/元）
        val amtMatch = Regex("[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
            ?: Regex("([0-9]+(?:\\.[0-9]{1,2})?)\\s*元").find(all)
        val amt = amtMatch?.groupValues?.getOrNull(1) ?: ""
        Log.d("AutoRecord", "hasStrong=$hasStrong amt=$amt")
        val id = "${System.currentTimeMillis()}_${pkg}"
        val item = JSONObject()
            .put("id", id)
            .put("pkg", pkg)
            .put("title", title)
            .put("text", all)
            .put("time", sbn.postTime)
        AutoRecordStore.appendPending(this, item)
        Log.d("AutoRecord", "enqueued id=$id pkg=$pkg amt=$amt")
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
                "com.cmbchina.cc", "com.cmbchina.biz", "com.cmbchina.mobilebank" -> "招行信用卡"
                else -> pkg
            }
            // 文案：'已加入待处理'（不是'已记账'，避免误导）。
            // 真正是否记账成功要等 Flutter _parse + _recordFlow 完成，
            // 弹 heads-up 时 native 不知道 Flutter 是否会丢弃（如通知没金额）。
            val titleStr = "已加入待处理 $src"
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
            description = "已记账：自动从支付类通知记账，点击查看详情"
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
        // 支付宝多包名（不同版本/子应用）
        "com.eg.android.AlipayGphone", // 支付宝 主 app
        "com.aliyun.snotif",           // 支付宝 阿里云推送通道（聚合通知走这条）
        "com.alipay.consumer",         // 支付宝 消费者版
        "com.alipay.android.uiapay",   // 支付宝 内嵌支付 SDK
        "com.alipay.mobile",           // 支付宝 老包名
        // 微信
        "com.tencent.mm",              // 微信 主 app
        "com.tencent.wepay",           // 微信支付组件
        // 其他
        "com.unionpay",                // 云闪付
        // 招商银行多包名
        "com.cmbchina.cc",             // 掌上生活
        "com.cmbchina.biz",            // 企业银行
        "com.cmbchina.mobilebank",     // 手机银行
        "com.cmbwallet",               // 招行信用卡独立 app（最常见包名）
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
