# 记账本 (jizhang-android)

安卓端记账 App，UI / 交互高保真复刻「鲨鱼记账」，对接 [jizhang](https://github.com/h223492759/jizhang) 后端 REST API。

## 功能
- 多服务器配置（内网 / 外网地址）、登录、账本切换
- 记一笔：分类选择（支出/收入）+ 自定义数字键盘 + 日期/备注
- 明细：按日分组的流水列表
- 图表：月/年 支出/收入，分类占比
- 账单：月账单 / 年账单
- 预算：年度总预算 + 分类预算进度
- 资产：存款目标（净资产）+ 分类钱包
- 发现：AI 助手（自然语言记账解析、月度分析）
- 我的：设置、关于、退出登录

## 技术栈
Flutter 3.22 + Dio + Riverpod + fl_chart + SharedPreferences

## 构建
```bash
flutter pub get
flutter build apk --release
```
APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。

## 发布
推送到 `main` 触发 CI 构建；打 `v*` tag 自动发布 GitHub Release（含 APK）。
