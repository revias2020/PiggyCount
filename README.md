# 小猪记账

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey)](#)
[![Version](https://img.shields.io/badge/version-0.2.1-green)](pubspec.yaml)

**免费 · 开源 · 本机优先** 的个人记账应用。

数据默认只存在你的手机里；可选 AI 智能记账与自备网盘同步。无广告、无内购、无强制账号。

</div>

---

## 为什么选小猪记账

| | 常见记账 App | 小猪记账 |
|---|---|---|
| 费用 | 高级功能常收费 | **完全免费**，MIT 开源 |
| 数据 | 多存第三方云 | **本机 SQLite 优先**，可选自建同步 |
| 隐私 | 可能追踪 / 分析 | **无广告、无追踪、无强制登录** |
| 记账方式 | 多为手动 | 手动 + 文字 / 图片 / 语音 / 截图自动化 |

> 平台：Android · iOS（**0.2.1 真机测试以 Android 为主**；桌面小组件目前仅 Android）  
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
- 图表：趋势、构成（主分类 / 子分类 / 标签）、对比、单笔排行
- 汇总：收入 · 支出 · 结余

### 智能记账（可选）

需自行配置 **智谱** 或任意 **OpenAI 兼容** 接口：

- 文字对话记账与分析
- 拍照 / 相册图片识别入账
- 语音记账（系统 ASR）
- Android：截图监听、系统分享入账；桌面**收支速览**小组件

### 数据

- CSV 导入 / 导出（可选 AI 列名与分类/标签映射）
- 分类导出（含自定义图标）
- 可选云同步：自备 **WebDAV**（推荐）或简化 **S3** 兼容端；多设备合并的是同步工作区，不是把 CSV 当同步文件

---

## 快速开始

### 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install) 稳定版（SDK 约束见 `pubspec.yaml`）
- Android Studio（真机 / 模拟器）；iOS 需 macOS + Xcode

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

### 打 Android 测试包（推荐按 ABI 分包）

```bash
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。当前 release 配置使用 **debug 签名**，仅适合自测与熟人 sideload；换正式签名前请先导出数据。keystore / Key 等密钥**不要**提交到 Git。

更完整的验收清单与已知风险见 [docs/development.md](docs/development.md)。

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/framework.md](docs/framework.md) | 产品边界与功能地图（维度 A–H） |
| [docs/development.md](docs/development.md) | 同维度实现手册、风险与验收 |
| [docs/version.md](docs/version.md) | 升级日志 |

应用内「关于 → 使用教程」是面向使用者的操作说明。

---

## 路线与边界

当前版本**刻意不做**：多币种、账户 / 支付方式体系、预算、暗色模式、多语言、订阅内购、家庭协同记账。

欢迎 Issue / PR；请先说明动机与影响面。

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
