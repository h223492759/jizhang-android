package com.example.u_gen_tmp

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 自动记账·无障碍兜底通道（v2.0.0 实验功能；不好用可整体退回 v1.5.6，见发布记录）
 *
 * 定位：通知监听够不着的漏单场景——支付成功只出现在 App 内页面/弹窗、没有系统通知
 * （招行碰一碰、部分扫码/收款结果页）。命中后写入与通知监听【同一条】待处理队列
 * （SharedPreferences auto_record_queue），Flutter 端统一走 _parse → 排除规则 → 去重 →
 * 落库，App 内无需区分来源。
 *
 * 功耗收敛设计（目标 ~1%/天，用户要求：不用 OCR）：
 *  - 只订阅 TYPE_WINDOW_STATE_CHANGED（窗口/弹窗切换，低频；manifest xml 配置）
 *  - packageNames 白名单 = 与通知通道同一份支付 App
 *  - 无 OCR、无轮询；事件防抖 400ms；处理完立即 recycle 节点树
 *  - 页面级启发式防误抓（历史账单/明细页顶部词不记；强信号须出现在页面前半部）
 *  - 命中冷却 30s/包 + 队列级「同包同额 60s」去重（通知通道优先）
 *  - 延迟 3s 入队：给可能后到的系统通知让路，减少双通道双记
 *
 * ⚠️ 词表与 AutoRecordListenerService.kt / Flutter auto_record_service.dart strongKw
 * 保持同步（改一处必改三处，2026-08-30 教训）。
 */
class AutoRecordAccessibilityService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())

    // 与通知监听同一份强信号词（页面命中「支付成功/收款成功…」才算完成页）。
    // 注：页面文本通常没有「交易提醒」这类通知标题词，主要靠 支付成功/付款成功/
    // 收款成功/转账成功/交易成功/扣款 等完成态词命中。
    private val strongKw = listOf(
        "支付成功", "付款成功", "成功付款", "支付成功通知", "已支付", "已付款",
        "收款成功", "已收款", "收款通知", "收款到账", "收款",
        "转账成功", "转账", "已存入", "收到转账", "转入",
        "扣款成功", "已扣款", "已消费", "消费", "扣款", "交易提醒",
        "入账", "到账", "还款成功", "已还款", "退款成功", "已退款",
        // 页面高频完成态词（通知文本少见但结果页必有）
        "交易成功", "支付完成", "付款完成", "交易完成", "缴费成功"
    )

    // 节点级黑名单：含这些词的短节点不进正文（促销/积分行混入会误导 Flutter 跳过或误判）
    private val skipNodeKw = listOf(
        "积分", "金币", "京豆", "里程", "成长值", "优惠", "秒杀", "领券",
        "抵扣", "返利", "折扣", "特惠", "促销", "立减", "满减", "代金券",
        "拼团", "砍价", "抽奖", "活动", "会员", "邀请", "推荐", "红包"
    )

    // 页面前 3 个节点若含这些词 → 疑似历史账单/明细/流水列表页，不记
    private val listPageTopKw = listOf("账单", "明细", "交易记录", "收支", "流水", "历史", "全部")

    // 命中冷却：同「包|金额」30s 内只入队一次（防同一结果页/同额行反复触发误抓；
    // 连续两笔不同金额的真支付不受影响——按金额区分而不是按包名一刀切）
    private val lastEnqueueAt = HashMap<String, Long>()

    private var debounce: Runnable? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        if (e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return
        if (!AutoRecordStore.ALLOWED_PACKAGES.contains(pkg)) return
        // 防抖：窗口变化可能连发（弹窗出现/布局稳定），只处理最后一发
        val now = System.currentTimeMillis()
        debounce?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable { processWindow(pkg, now) }
        debounce = r
        mainHandler.postDelayed(r, 400)
    }

    override fun onInterrupt() {}

    private fun processWindow(pkg: String, evtTime: Long) {
        val root = rootInActiveWindow ?: return
        val texts = mutableListOf<String>()
        try {
            collectTexts(root, texts, 0)
        } catch (_: Exception) {
        } finally {
            root.recycle()
        }
        if (texts.isEmpty()) return
        // 顶部词疑似历史明细页 → 不记（防浏览旧账单被当成新支付）
        val top = texts.take(3).joinToString("，")
        if (listPageTopKw.any { top.contains(it) }) {
            logFile("[无障碍] 顶部命中列表词，疑似历史明细，跳过 pkg=$pkg top=$top")
            return
        }
        val all = texts.joinToString("，").trim()
        if (all.length < 4) return
        // 强信号词须出现在页面前 60%（成功页头条在顶部；历史账单页「支付成功」常在底部）
        val hits = strongKw.mapNotNull { kw ->
            val i = all.indexOf(kw)
            if (i >= 0) kw to i else null
        }.filter { it.second <= all.length / 2 }
        if (hits.isEmpty()) {
            Log.d("AutoRecordA11y", "no strong kw in first half pkg=$pkg all=${all.take(60)}")
            return
        }
        val kw = hits.minByOrNull { it.second }!!.first
        val amt = extractAmount(all)
        // 同「包|金额」冷却（页面重发/同额列表行防抖；无金额占位也用空串区分）
        val sigKey = "$pkg|$amt"
        val nowMs = System.currentTimeMillis()
        val last = lastEnqueueAt[sigKey] ?: 0L
        if (nowMs - last < 30_000L) {
            Log.d("AutoRecordA11y", "cooldown skip sig=$sigKey")
            return
        }
        val id = "${System.currentTimeMillis()}_a11y_$pkg"
        val item = JSONObject()
            .put("id", id)
            .put("pkg", pkg)
            .put("src", "a11y") // Flutter 双通道去重标记（notif 条目无此字段）
            .put("amt", amt)    // 归一化金额（队列级同额去重用；0 元占位为空串）
            .put("title", kw)   // 命中关键词 → 流水名「支付方式hh:mm关键词」
            .put("text", all.take(600))
            .put("time", evtTime)
        logFile("[无障碍] 页面命中 pkg=$pkg kw=$kw amt=${amt.ifEmpty { "未识别" }}")
        // 延迟 3s 入队：给可能后到的系统通知让路（同包同额 60s 内通知通道优先）
        mainHandler.postDelayed({
            val appended = AutoRecordStore.appendA11yPending(this, item)
            if (appended) {
                lastEnqueueAt[sigKey] = System.currentTimeMillis()
                logFile("[无障碍] 已入队 id=${id.takeLast(18)} amt=${amt.ifEmpty { "0元占位" }}")
                postHeadsUp(pkg, kw, amt)
                launchMain(id)
            } else {
                logFile("[无障碍] 队列去重跳过：同包同额已有条目（通知通道优先） kw=$kw")
            }
        }, 3000)
    }

    /** 深度遍历收集可见短节点文本（促销长文/超长详情丢弃，控制总量） */
    private fun collectTexts(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > 22 || out.size > 80) return
        try {
            if (node.isVisibleToUser) {
                val t = node.text?.toString()?.trim()
                if (!t.isNullOrEmpty() && t.length in 1..60 &&
                    !skipNodeKw.any { t.contains(it) }
                ) {
                    out.add(t)
                }
            }
            val count = node.childCount
            for (i in 0 until count) {
                val child = node.getChild(i)
                if (child != null) {
                    try {
                        collectTexts(child, out, depth + 1)
                    } finally {
                        child.recycle()
                    }
                }
            }
        } catch (_: Exception) {
        }
    }

    /** 金额提取（与通知监听同款正则族：¥xx / xx元 / xx人民币），归一化两位小数 */
    private fun extractAmount(all: String): String {
        val m = Regex("[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
            ?: Regex("([0-9]+(?:\\.[0-9]{1,2})?)\\s*(?:元|人民币)").find(all)
            ?: Regex("(?:人民币|RMB)\\s*([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
        val v = m?.groupValues?.getOrNull(1) ?: return ""
        return try {
            String.format(Locale.US, "%.2f", v.toDouble())
        } catch (_: Exception) {
            v
        }
    }

    // ---------- 与通知监听一致的用户可见反馈（弹 heads-up + 拉起主界面） ----------

    private fun pkgLabel(pkg: String): String = when (pkg) {
        "com.eg.android.AlipayGphone", "com.aliyun.snotif",
        "com.alipay.consumer", "com.alipay.android.uiapay", "com.alipay.mobile" -> "支付宝"
        "com.tencent.mm", "com.tencent.wepay" -> "微信支付"
        "com.unionpay" -> "云闪付"
        "com.cmbchina.cc", "com.cmbchina.biz", "com.cmbchina.mobilebank",
        "com.cmbwallet" -> "招行信用卡"
        else -> pkg
    }

    private fun postHeadsUp(pkg: String, kw: String, amount: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureChannel(nm)
            val pi = PendingIntent.getActivity(
                this, 1,
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val src = pkgLabel(pkg)
            val titleStr = "已加入待处理 $src"
            val body = if (amount.isNotEmpty()) "识别到支付页面 ¥$amount" else "识别到支付页面（无金额，已记待录入）"
            val n = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(titleStr)
                .setContentText("$body · $kw")
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
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID, "自动记账", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "自动从支付通知/支付页面记账"
            enableVibration(true)
        }
        nm.createNotificationChannel(ch)
    }

    private fun launchMain(id: String) {
        try {
            val i = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("auto_record", id)
            }
            startActivity(i)
        } catch (_: Exception) {
        }
    }

    /** 用户可见日志：与通知通道同文件（native_logs.json），[无障碍] 前缀区分来源 */
    private fun logFile(msg: String) {
        val now = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.CHINA).format(Date())
        AutoRecordStore.appendLog(this, "[$now]$msg")
    }

    companion object {
        const val CHANNEL_ID = "auto_record"
        const val NOTIFY_ID = 1002
    }
}
