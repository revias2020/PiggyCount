# 小猪记账

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey)](#)
[![Version](https://img.shields.io/badge/version-0.3.0-green)](pubspec.yaml)

**免费 · 开源 · 本机优先** 的个人记账应用。

数据默认只存在你的手机里；可选 AI 智能记账与 WebDAV / S3 云快照。无广告、无内购、无强制账号。

---

## 为什么选小猪记账

| | 常见记账 App | 小猪记账 |
|---|---|---|
| 费用 | 高级功能常收费 | **完全免费**，MIT 开源 |
| 数据 | 多存第三方云 | **本机 SQLite 优先**，可选自建同步 |
| 隐私 | 可能追踪 / 分析 | **无广告、无追踪、无强制登录** |
| 记账方式 | 多为手动 | 手动 + 文字 / 图片 / 语音 / 截图自动化 |

> 平台：Android · iOS  
> 界面语言：简体中文（当前仅亮色模式）

---

## 功能概览

### 记账

- **多账本** — 生活 / 工作等分开记，顶栏一键切换
- **两层分类** — 支出 / 收入各自维护主分类与子分类；支持自定义图标
- **标签** — 独立于分类；支持字符串组与数值组，智能记账可自动选标
- **记一笔** — 底部弹层 + 自定义数字键盘；支持再记一笔
- **日历 / 搜索** — 按日查看；关键词、金额、日期、分类筛选与批量操作

### 报表

- 周期：**周 / 月 / 年 / 自定义区间**
- 图表：趋势、构成（主分类 / 子分类 / 标签）、月度对比、单笔排行
- 汇总：收入 · 支出 · 结余

### 智能记账（可选）

需自行配置 **智谱** 或任意 **OpenAI 兼容** 接口：

- 文字对话记账与分析
- 拍照 / 相册图片识别入账
- 语音记账（系统 ASR）
- Android：截图监听、系统分享入账
- iOS：快捷指令引导

### 数据

- CSV 导入 / 导出
- 分类导出（含自定义图标）
- 可选云快照：**WebDAV**、简化 **S3**

---

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter（Material 3） |
| 状态管理 | Riverpod |
| 本地数据库 | Drift / SQLite |
| 图表 | fl_chart |
| 应用包名 | `com.xiaozhu.piggy_count` |

---

## 快速开始

### 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install)（稳定版，SDK 见 `pubspec.yaml`）
- Android Studio / Xcode（按目标平台）

### 运行

```bash
git clone https://github.com/revias2020/PiggyCount.git
cd PiggyCount
flutter pub get
flutter run
```

### 测试

```bash
flutter test
```

### 图标与启动页

修改 `assets/brand/app_icon.png` 后重新生成：

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

---

## 构建发布包

```bash
# Android
flutter build apk --release
# 或
flutter build appbundle --release

# iOS（需 macOS + Xcode）
flutter build ipa --release
```

---

## 文档

- [开发文档](docs/开发文档.md) — 产品与技术规格
- [开发进度](docs/开发进度.md) — 阶段完成情况

---

## 路线与边界

当前版本**刻意不做**：多币种、账户 / 支付方式体系、预算、暗色模式、多语言、订阅内购。

欢迎 Issue / PR 讨论方向；请先说明动机与影响面。

---

## 贡献

1. Fork 本仓库并创建分支
2. 保持改动聚焦、风格与现有代码一致
3. 提交前跑通 `flutter analyze` / `flutter test`
4. 发起 Pull Request，简要说明「为什么改」

---

## 许可证

本项目基于 [MIT License](LICENSE) 开源发布。你可以自由使用、修改、分发，包括商用，只需保留版权与许可声明。

```
Copyright (c) 2026 revias2020
```
