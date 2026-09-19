package com.example.u_gen_tmp

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
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
    // v2.0.1：删除裸词「收款/转账/转入/扣款/消费」——这些词在支付宝/微信日常页面
    // （转账按钮、收款码、付款记录）常驻，每次打开就触发记账，已误记 N 笔 0 元/小数。
    // 改为只保留【完成态】复合词；「到账」保留（招行碰一碰结果页常用）。
    private val strongKw = listOf(
        "支付成功", "付款成功", "成功付款", "支付成功通知", "已支付", "已付款",
        "收款成功", "已收款", "收款通知", "收款到账",
        "转账成功", "已存入", "收到转账",
        "扣款成功", "已扣款", "已消费", "交易提醒",
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

    // v2.0.1：覆盖支付宝/微信日常入口页 + 原列表页（修「打开就记」主因之一）
    // v2.2.24 拆成两组（修「支付成功页被当成历史明细页」漏记）：
    //   2026-09-19 11:23 支付宝碰一碰成功后页面顶部是「支付成功，回首页，佳丰生活超市黄村店」，
    //   旧逻辑用 top.contains("首页") 判定 → "回首页".contains("首页")=true → 整笔被丢弃（漏记）。
    //   ① exact：短导航词（首页/我的/服务…）**必须整段相等**才算命中，
    //      "回首页"/"客户服务"/"送朋友" 这类按钮/营销文案不再误伤；
    //   ② contains：列表页特征长词，段内含即算命中（"账单明细"、"交易记录"…）。
    private val listPageTopExactKw = listOf(
        "我的", "朋友", "通讯录", "消息", "聊天", "首页", "扫一扫",
        "付款码", "收钱码", "卡包", "余额", "服务", "全部", "收藏", "设置"
    )
    private val listPageTopContainsKw = listOf(
        "账单", "明细", "交易记录", "收支", "流水", "历史", "账户余额", "待还",
        // 入口页的按钮/栏位文案（整段经常带前后缀，故用 contains；支付结果页不会出现）
        "客户服务", "搜索好友", "好友", "我的户号", "缴费记录"
    )

    // 命中冷却：同「包|金额」30s 内只入队一次（防同一结果页/同额行反复触发误抓；
    // 连续两笔不同金额的真支付不受影响——按金额区分而不是按包名一刀切）
    private val lastEnqueueAt = HashMap<String, Long>()

    private var debounce: Runnable? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        if (e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return
        if (!AutoRecordStore.ALLOWED_PACKAGES.contains(pkg)) return
        // v2.2.0：支付方式开关——未勾选来源的页面事件直接忽略（与通知通道同一启用集合）
        if (!AutoRecordStore.isPayMethodEnabled(this, pkg)) return
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
        // v2.2.24：①短导航词改整段相等匹配（"回首页" 不再命中 "首页"，修碰一碰漏记）
        //          ②顶部已出现【完成态强信号词】→ 判定为支付结果页，结果页优先，
        //            直接跳过列表页启发式（历史明细页顶部极少出现「支付成功」这类完成态词）
        val topSegs = texts.take(3).map { it.trim() }
        val top = topSegs.joinToString("，")
        val topIsResultPage = topSegs.any { seg -> strongKw.any { seg.contains(it) } }
        if (!topIsResultPage && isListPageTop(topSegs)) {
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
        val kwIdx = hits.minByOrNull { it.second }!!.second
        // v2.2.6：京东 app 的「到账/入账」单字 = 营销/虚拟到账（京东金条借款/白条还款/
        // 邀请奖励等"我的-金融"模块文案），不是真实收入；招行碰一碰结果页的「到账」
        // 仍可识别（pkg != 京东）。支付宝 app 的「到账」单字同理多为网商银行/借呗营销文案。
        if ((kw == "到账" || kw == "入账") &&
            (pkg == "com.jingdong.app.mall" || pkg.startsWith("com.jd.") ||
             pkg == "com.eg.android.AlipayGphone")) {
            logFile("[无障碍] 京东/支付宝app+到账/入账单字=营销到账，跳过 pkg=$pkg kw=$kw")
            return
        }
        // v2.0.1：金额必须出现在「强信号词 ±30 字」窗口内——避开页面里无关的余额/费率/
        // 积分数字（之前把账户余额 0.14 / 0.50 当成支付金额误识）。
        val winStart = (kwIdx - 30).coerceAtLeast(0)
        val winEnd = (kwIdx + kw.length + 30).coerceAtMost(all.length)
        val window = all.substring(winStart, winEnd)
        // v2.2.24：成功页常把「￥」和数字放进两个可访问性节点，页面文本就成了
        // 「支付成功，回首页，￥，12.00」→ 严格正则匹配不到 → 旧逻辑判「窗口内无金额」丢弃整笔
        // （2026-09-19 碰一碰漏记的第二道闸）。依次尝试：严格(±30) → 宽松(±30) → 宽松(±60)。
        var amt = extractAmount(window)
        if (amt.isEmpty()) amt = extractAmountLoose(window)
        if (amt.isEmpty()) {
            val w2s = (kwIdx - 60).coerceAtLeast(0)
            val w2e = (kwIdx + kw.length + 60).coerceAtMost(all.length)
            amt = extractAmountLoose(all.substring(w2s, w2e))
        }
        // v2.0.1：窗口内既无金额也无「0 元 / 0.00 / 免支付」明确字样 → 跳过不入账
        // （修「打开支付宝就记 0 元占位」问题；保留 0 元保底以防页面无金额的成功页漏记）
        if (amt.isEmpty()) {
            val zeroHint = Regex("(?:^|\\D)0(?:\\.0+)?\\s*(?:元|人民币)|免支付").containsMatchIn(window)
            if (!zeroHint) {
                logFile("[无障碍] 窗口内无金额且非明确免支付，跳过 kw=$kw pkg=$pkg win=\"$window\"")
                return
            }
        }
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
                // v260908：不再逐条弹「已加入待处理」heads-up（弹窗太多）；只在 Flutter
                // 真正记账成功后统一弹一次「已记账」（AutoRecordStore.postRecordedHeadsUp）。
                // v2.0.1：不调 launchMain 抢前台——用户要求「弹 heads-up 即可，跳转 App 太烦」
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

    /** 顶部三词是否像「列表 / 入口页」（历史明细页防误抓）；见 listPageTopExactKw 注释 */
    private fun isListPageTop(segs: List<String>): Boolean {
        for (raw in segs) {
            val s = raw.trim()
            if (s.isEmpty()) continue
            if (listPageTopExactKw.any { it == s }) return true
            if (listPageTopContainsKw.any { s.contains(it) }) return true
        }
        return false
    }

    /** 金额提取（与通知监听同款正则族：¥xx / xx元 / xx人民币），归一化两位小数 */
    private fun extractAmount(all: String): String {
        val m = Regex("[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
            ?: Regex("([0-9]+(?:\\.[0-9]{1,2})?)\\s*(?:元|人民币)").find(all)
            ?: Regex("(?:人民币|RMB)\\s*([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
        return normAmount(m?.groupValues?.getOrNull(1))
    }

    /**
     * 宽松金额提取（v2.2.24）：容忍「￥」与数字被拆成两个节点——
     * 中间只允许空白/常见分隔符（，,、:：）最多 4 个，**不允许汉字**，
     * 避免把「￥ 余额 1000.00」这类无关数字当成支付金额。
     */
    private fun extractAmountLoose(all: String): String {
        val m = Regex("[¥￥][\\s，,、:：]{0,4}?([0-9]+(?:\\.[0-9]{1,2})?)").find(all)
        return normAmount(m?.groupValues?.getOrNull(1))
    }

    private fun normAmount(v: String?): String {
        if (v.isNullOrEmpty()) return ""
        return try {
            String.format(Locale.US, "%.2f", v.toDouble())
        } catch (_: Exception) {
            v
        }
    }

    // ---------- 用户可见反馈（v260908 收口） ----------
    // 不再在每次页面检测成功时逐条弹「已加入待处理」heads-up（弹窗太多）；入队只写日志，
    // 记账成功与否由 App 端决定，成功后统一弹一次「已记账」提醒
    // （Flutter 记账成功 → MethodChannel notifyRecorded → AutoRecordStore.postRecordedHeadsUp）。
    // 删除：pkgLabel / postHeadsUp / ensureChannel / launchMain（v2.0.1 已删抢前台）

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
