# 小猪记账 · 开发手册

> 与 [framework.md](./framework.md) **同一套功能维度**。本文件写实现：怎么跑、关键规则、代码落点。  
> 用户安装见 [README.md](../README.md)。

**版本：** `0.4.0+7`（公开源码 + GitHub Release `arm64-v8a` 测试包）· 整理 2026-08-23  
升级说明见 [version.md](./version.md)。

文中「ADR-xxx」为历史决策编号索引（附录）；规则正文在各功能节。领域词见仓库根 [CONTEXT.md](../CONTEXT.md)，完整 ADR 见 [docs/adr/](./adr/)。

---

## 怎么读

| 维度 | 章节 | 对应 framework |
|---|---|---|
| **A** 工程底座 | §1 | §9 |
| **B** 核心数据 | §2 账本 · §3 分类 · §4 标签 | §3 |
| **C** 日常记账 | §5 | §4 |
| **D** 报表 | §6 | §5 |
| **E** 智能记账 | §7 引擎 · §8 渠道 | §6 |
| **F** 数据互通 | §9 云与同步 · §10 CSV | §7 |
| **G** 桌面 | §11 | §8 |
| **H** 系统与发布 | §12 日志 · §13 品牌 · §14 验收 | §1 / §9 |

每节固定四块：**做什么 → 怎么跑 → 关键规则 → 代码**。

---

# A · 工程底座

## 1. 启动与本地库

### 做什么

App 启动即打开 Drift 库；新库播种出厂目录；业务经 Repository，页面不拼 SQL。

### 怎么跑

1. `main.dart`：程序日志钩子 →（Android）`sqlite3_flutter_libs` → `AppDatabase.open()` → `runApp`  
2. `schemaVersion = 9`  
3. **`onCreate`**：建表 + 导入出厂分类/标签  
4. **`onUpgrade`**：补列并回填（`syncId` / `updatedAt` / `deletedAt` / `fingerprint` 等）；**不会**每次启动把用户删掉的目录种回来  

同一安装内目录删光也不会自动补 → 走管理页「恢复默认」。曾按名删「生活日用」已取消（误伤自建同名）。

### 关键规则

- 出厂目录只在新库种一次（ADR-0039）  
- 实体跨设备身份用创建时 UUID（`syncId`）；账单亦然（ADR-044）。指纹只作内容签名，不当身份  
- 改动比较：墙上时钟 `updatedAt`；删除：墓碑 `deletedAt`  

### 代码

| 环节 | 路径 |
|---|---|
| 入口 | `lib/main.dart` |
| 表 / 打开迁移 | `lib/data/tables.dart`、`app_database.dart` |
| 出厂清单 / 补缺 | `default_catalog.dart`、`default_catalog_applier.dart` |
| Repository | `lib/data/repositories/*` |
| 迁移测试 | `test/schema_v9_migration_test.dart` |

---

# B · 核心数据

## 2. 账本

### 做什么

账单的归属容器。分类与标签全局共享。

### 怎么跑

- 出厂「日常账本」；顶栏点账本名 → 列表内切换 / 新建 / 重命名 / 删除  
- 「我的」**无**账本管理入口  

### 关键规则

- 未删除账本名全库唯一；撞名框下红字  
- 删整本须说明：**账本复活**——对端若有比删除更晚的账单增改，同步后本与那些账单会回来（不是按名并进后来新建的同名账）  
- 较晚改动 = 各设备墙上时钟，不是记账日、也不是谁后点同步（ADR-042）  

### 代码

`lib/widgets/ledger_list_sheet.dart` · `details_header.dart` / `app_top_bar.dart` · `ledger_repository.dart` · `ledger_session_provider.dart`

---

## 3. 分类

### 做什么

支出 / 收入两套两层树；管理 + 记一笔选类 + 图标展示。

### 怎么跑

1. `parentId == null` 主分类，否则子分类（不可再挂子）  
2. 记一笔：点主类展开子类，也可点主类直记  
3. 管理：主网格只列主类 → 详情弹层（编辑 / 改为子类 / 删除 + 子类列表）  
4. 改为子类 / 移主类：弹**选择主分类**网格（未选灰、选中彩）→ 确认；目标下已有子则「改为子类」拒绝  
5. 自定义图标：网格首位「＋」→ 相册 → 强制 1:1 → ~96×96 存本地，**只绑当前分类**  
6. 「…」：**清除未使用** / **恢复默认**  

### 关键规则

| 规则 | 说明 |
|---|---|
| 名唯一 | **同收支类型内**主+子唯一；跨类型可同名。勿全库禁重名；勿仅同级唯一（否则两棵树下可各有「午餐」） |
| 删除 | 子类有账禁删；主类自身或任一下有账禁删（列出子类名），否则级联删 |
| 清除未使用 | 无账单引用才删；主类须自身+全部子类皆无账；确认+条数 |
| 恢复默认 | 出厂清单合并补缺；不删自建、不搬家 |
| 彩标 | Material 按 **icon key** 固定色；未知/未分类 → 中性灰；颜色不入库 |
| 环 vs 列表 | 报表**构成环**用观赏色板；列表/排行图标跟彩标（勿把环做成彩标色） |
| 同步 | 自定义图标文件**不进**工作区；导出 zip 可含图 |
| 默认树 | 仅部分支出主类挂默认子树；收入不补（ADR-011） |

### 代码

`category_manage_page.dart` · `category_repository.dart` · `category_icon_view.dart` / `category_icons.dart` · `custom_icon_service.dart` · `category_detail_page.dart`  
技术：`image_cropper`、`flutter_image_compress`、`archive`

---

## 4. 标签

### 做什么

挂在账单上的标注体系（不是分类的一层）；服务管理与智能选标。

### 怎么跑

| 组类型 | 选标 |
|---|---|
| 字符串组 | 语义相关；组内可多选；智能每组最多 2 |
| 数值组 | 金额落 `[min,max)`；组内互斥 1；禁重叠 |

组有 scope：`both` / `expense` / `income`。管理页展示全部组；记一笔/智能按账单类型过滤。

出厂：「支付/渠道」（字符串·支出）九渠道 + 「额度」（数值·全部）三档。无 `groupId` 创建 → **外部导入**组（勿再落到「支付/渠道」）。

### 关键规则

- 标签名、组名全库唯一  
- 组内有标 → **禁删组**（不级联、不暗塞默认组）  
- 允许空组；智能跳过空组  
- 自动生成标签：须「已有字符串组名 + 新标名」；不自动建组、不在数值组建档；配额不随组数量切换  
- 清除未使用 / 恢复默认：同分类语义  
- 标签色入库；列表须随 `tags` 表变更刷新 chip（ADR-035）  
- 行内全量 chip 横滑 + 淡出（退役 `+N` 弹层）  
- 报表标签构成扁平按名；无标 → 合成桶「未标注」（不入库）  

### 代码

`tag_manage_page.dart` · `tag_repository.dart` · `tag_colors.dart` · 选标在 `record_editor_sheet` · `tag_detail_page.dart`

---

# C · 日常记账

## 5. 明细 · 记一笔 · 日历 · 搜索

日常记账是用户主路径：看列表 → 记一笔 → 查历史。

### 5.1 明细

**做什么：** 当前账本按月浏览与汇总。

**怎么跑：**

- 一体顶栏：`piggyCount` + 标题 + 账本 ▾ + 日历 + **同步** + **核对信封**（有待核对红点）+ 搜索（本 Tab 无壳层 `AppTopBar`）  
- 同步钮：未已测通禁用；点即同步确认，不先开同步页  
- 月度汇总：年月网格；收入｜支出｜结余；**不做**类型筛选  
- **浏览月换月（本轮）：** 仅明细账单列表区（含空状态）支持左右滑切换 **浏览月**——左滑下一月、右滑上一月；达阈值即改月（非 PageView 邻页预览），列表滚回顶部，无过渡动画。边界：**今−8 年 … 本月**（可进空月，不可进未来）；触顶/触底静默忽略。点年月网格仍可跨月跳转；**共用** `year_month_grid_sheet` 同步禁选未来月。竖向滚列表优先于换月；标签 chip 槽内横滑仍只滚 chip（ADR-036），不触发换月。分类/标签明细 ◀▶ 本轮不改。

**待核对（ADR-050）：** 后台直存（`screenshot` / `share`）成功后进入待核对（`syncId`，当前账本，本机持久）。明细行 **核对高亮**（蓝描边 + 极浅蓝底）仅本次前台，进后台清除，回前台按仍待核对重打；**点高亮行 = 已看且不打开编辑**，无高亮时点行仍编辑。信封底部弹层：列表跳转、单条已看、一键已读；有待核对显示红点。成功通知进 App 滚到该笔。日历/搜索本轮不接入。

**统一账单行**（明细/日历/搜索/分类明细/标签明细共用）：

- 左圆标 → 分类明细（月度可换月；主类含子类；**未分类可进**；无迁移编辑）  
- 中上：分类名 + 标签 chip（横滑）；中下：时间 + 可选备注  
- 右：金额（支出绿 / 收入红）  
- 点 chip → 标签明细；点行 → 编辑  
- **仅明细**长按删除；其它列表本轮不挂删除  

报表构成下钻进来的分类/标签明细：带入报表周期，顶栏只读。

**代码：** `details_page.dart` · `details_month_swipe_area.dart` · `details_month_bounds.dart` · `home_shell.dart` · `details_header.dart` · `pending_review_sheet.dart` · `pending_review_providers.dart` · `transaction_row_tile.dart` · `fading_tag_chip_strip.dart` · `transaction_providers.dart`（`MonthLedgerView`）

### 5.2 记一笔

**做什么：** 手动入账主界面；智能入口收口到扇形与备注旁侧入口。

**怎么跑：**

1. FAB 单击 → 工作台 **85%**；长按 → 真扇形（圆心=FAB 中心，半径 ~96–110，约 100°/135°/170°；收锚 + 遮罩；拖选松手）  
2. 主层：类型、时间、金额、分类（`Expanded`）、标签入口、备注入口、**固定金额键盘**（键高 ~40–42）  
3. 时间：居中 Dialog；双输入（始终两位）+ 小时 `0–23` 网格 + 分钟每 5 分快捷；非法确定红字不关；写回保留秒（ADR-051）  
4. 选标：次级 ~**55%**，点 chip 即生效；标题行右上「确认」仅关层  
5. 备注：独立层 ~**36%**，仅此调系统键盘并顶起；「完成」写回；主层不上移  
6. 新建备注旁：语音（左）/ 相机（右）；均关层丢草稿后走对应确认流；编辑无此二钮；非附图  

其它工作台高度：分类编辑 50%、标签/组 40%、主分类详情封顶 85%、选主分类列表 ~45%。sheet 透明底 + 内层白卡；禁 `useSafeArea: true`。

**代码：** `record_fab.dart` · `record_editor_sheet.dart` · `record_time_picker_dialog.dart` · `amount_keypad.dart` · `workspace_sheet.dart` · `voice_billing_sheet.dart` · `image_billing_sheet.dart`

### 5.3 日历

独立页；打开聚焦明细当前月，互不回写。格内可同时 ±。点日看列表。「在该日记账」预填选中日 + **此刻时分秒**。无 FAB。

账单时间：库存到秒、界面到分；改日期/时间保留原秒。

**代码：** `calendar_page.dart` · `happened_at.dart`

### 5.4 搜索

当前账本。关键词：备注 / 分类 / 金额字串 / **标签名** + 金额·日期·分类筛选。批量改备注、改分类、删除。

**代码：** `search_page.dart`

### 本节锁定

ADR-002 / 003 / 013 / 016 / 029 / 036 / 039 / 040 / 051（及明细同步钮 ADR-042；待核对 ADR-050）

---

# D · 报表分析

## 6. 报表

### 做什么

选定账本、周期、收支类型下的聚合视图。

### 怎么跑

1. **再显刷新：** 写账单只标过期；切回报表 / 从子页返回 / 报表可见时写完 → 静默换快照。勿对报表做全程 Drift watch。  
2. 周期：周月年靠左 `< 文案 >` + 网格弹层；自定义用系统区间。右侧支出/收入。  
3. 三卡：  
   - **趋势：** 面积折线；图区高 ~140、顶留白 ~30；气泡钉最后有数据日；零值不连线  
   - **构成：** 环=观赏色板按金额排名；环外标注 Top**8**；列表=真实分类图标；点行下钻（报表周期只读）  
   - **对比排行：** 周期柱 + Top10 → **排行全页**（顶栏：总支出｜总收入｜笔数；金额排序；多选仅批量删；页内不换期）  
4. AI 浮动球：可拖、松手左右贴边（边距 ~8）；开关只控显隐  

### 关键规则

- 构成环色 ≠ 分类彩标（ADR-033 vs 008）  
- 漏标过期 → 「改了账报表不更新」  
- **用户可见统计只计存活账单**（`deletedAt` 为空）；`StatisticsRepository` 与明细同源过滤，墓碑永不入合计/构成/排行（ADR-046）  
- 删除确认：单删「确定删除这条账单？删除后不可恢复。」；批量「确定删除选中的 N 笔账单？删除后不可恢复。」  

### 代码

`report_page.dart` · `report_providers.dart` · `report_period.dart` · `report_route_observer.dart` · `lib/widgets/report/*` · `rank_full_page.dart` · `statistics_repository.dart`

---

# E · 智能记账

智能 = **配置与引擎**（§7）+ **各入口渠道**（§8）。先配服务商，再谈渠道。

## 7. AI 服务商与提取引擎

### 做什么

把文本/图片变成 `BillInfo`，再匹配目录落库。不托管用户 Key。

### 怎么跑

**配置：**

- 内置智谱（名/Base 锁死）+ ≤5 OpenAI 兼容  
- 能力绑定：文本对话 / 图片理解 / **语音直接记账** 各一商；仅展示该侧**测通成功**者（语音模型可空=该商不支持）
- 测连 timeout 15s；文本识别 30s、图片/语音识别 60s；保存时未测侧会打网；失败仍落盘，弹窗「返回编辑 / 确认保存」（确认则回服务商管理；遮罩/返回=留下）；绑定中的自定义商禁删  
- **语音测连（ADR-059）：** 用 1s / 16-bit PCM / 8kHz 静音 WAV（对齐 BeeCount）；禁止空 data；静音空响应仍算测通；`input_audio` 在 content 中置于文本之前  
- M1：旧单配置迁到内置或新建自定义并双绑；旧服务商无 `voiceModel` 时智谱补 `glm-4-voice`  
- **语音识别引擎（ADR-052 / ADR-067）：** 默认 **未启用**；实引擎为 Vosk 中文小包 / Whisper base（ModelScope 下载，不进安装包）/ AI 语音模型；系统 ASR 已废止  
- **语音音频还原（ADR-060）：** 仅 Android；弹层结束时条件还原 `AudioManager` 模式；「重新说」不还原

**流水线：**

```
文本或图片或语音音频
  → resolve(文本|视觉|语音)
  → PromptBuilder（目录、scope、CURRENT_TIME 到秒、实付、备注规则）
  → OpenAiCompatibleClient
  → BillInfo[] → 确认 UI 或后台直存
  → BillCreationService（分类/智能选标）→ 落库
```

文本还用于：听写后结构化、CSV AI 映射。视觉用于：截图/分享/拍照/相册。语音能力用于：AI 语音模型**直接记账**（ADR-052）。

### 关键规则

- **实付金额：** 有应付与实付时取实付  
- **账单时间：** 资金变动时刻（支付 > 订单类标签）；禁止自取/配送/预约等履约时间；仅有履约时间则用 `CURRENT_TIME`  
- **提取备注：** ≤15 字；店名/商品优先；支付方式走标签  
- **分类消歧（ADR-047）：** Prompt 按主类分组；可回写值为主类裸名与「主类-子类」；先主类再子类，都不贴用主类；匹配优先复合名再裸名；确认/明细展示仍用裸名  
- 空 Key / 未就绪：中文提示 +「去设置」，不静默打网；**前台确认弹层**（语音/图片）只用弹层内引导，不叠轻提示（ADR-057） 

### 代码

`ai_provider_config.dart` · `ai_provider_store.dart` · `openai_compatible_client.dart` · `prompt_builder.dart` · `ai_category_match.dart` · `extraction_engine.dart` · `ai_bookkeeper.dart` · `bill_creation_service.dart` · `ai_settings_page.dart` 等 · `ai_providers.dart`  
默认智谱：`open.bigmodel.cn` · `glm-4-flash` / `glm-4v-flash`

---

## 8. 记账渠道

### 做什么

同一套提取能力，按入口选择**前台确认**或**后台直存**。

### 怎么跑

| 渠道 | 入口 | 落库 |
|---|---|---|
| 手动 | FAB 单击 | 无 AI |
| 拍照 / 图片 / 备注旁相机 | 扇形或相机 | Vision → **识别确认弹层** |
| 语音 / 备注旁语音 | 扇形或备注旁 | 未启用时弹层内引导去设置（ADR-067）；否则按引擎：听写→文本结构化 **或** AI 直接记账 → **单卡**（ADR-052）；标题行右上关闭；底栏左「重新说」、聆听中右「识别」；**Android 关层后条件还原音频模式**（ADR-060） |
| 截图自动 | 「我的」开关（默认关） | 通知 → Vision → **自动落库** |
| 分享入账 | 系统分享 | 始终可收（不受截图开关）→ 同上 |

**分享入账（Android）：** `ShareRelayActivity`（透明）接 `ACTION_SEND` / **`ACTION_SEND_MULTIPLE`**（ADR-058）→ 拷图（上限 9，超出截取前 9）→ **拷图成功即同 id 直发「已收到…」并起 FGS**；**等 `startForeground`（或 ≤1.5s）后再**以 `SINGLE_TOP|CLEAR_TOP|NEW_TASK` 打进 `MainActivity`（ADR-063 / **069**；**无固定 500/600ms**；冷启 onCreate 只写 pending 由 `getPending` 取走，热启 onNewIntent 立即推送）。**热启动**不得出现启动页；冷启动仍走主界面 LaunchTheme。Dart 接手后 `startForegroundService` 刷新文案，**先 `moveTaskToBack` 回源**，再 **「已收到…」最短展示 1s**（`ShareEarlyProgressGate`，回源后起算）后进识别；直存批次进行中返回键同样送后台（不 `finish`），避免拆掉 Flutter 引擎导致识别静默中断。多选截取时早期/结果通知注明「已截取前 9 张」。

**前台多图（ADR-058）：** 扇形「图片」/备注旁相册用系统多选（`pickMultiImage`），上限 9、超出截取并轻提示；**不做** App 内选图闸门。全部串行 Vision 后再出确认层；loading 可取消（丢弃 inflight，已完成组仍进确认层）。确认层**按图分组**（组头小缩略图可点全屏静态原图）；失败/空结果组可重试。拍照仍单张。iOS 同步前台多选；多选分享仅 Android。

**识别确认弹层：** 复选默认全选；确认(N)；关即丢弃；串行落库可部分成功重试；行内只读；圆标按名匹配，未命中「未分类」（勿用落库兜底类）。**Vision 回退（ADR-055 / 072）：** 前台与后台直存均为每已测通服务商仅调 1 次，失败立即切下一候选（后台不再同商 3s 再打）；前台 loading 展示失败原因与「正在切换至 XX（模型）重试…」。

**后台：** `AutoBillingService` 串行；**优先级（ADR-075）：** `share` > 全部 `screenshot`（含补扫），高优先级内 FIFO，不打断 inflight。截图识别中 / 关联窗未门闩 / 低优队将被挡住时来了分享，进度/FGS 正文「等待当前识别结束后处理分享…」。**结果（ADR-076 方案 A）：** 整批高+低队列空后再出一条「识别结果」（不再分享段中途单独 flush）。结果通知（截图取消除外）标题固定 **「识别结果」**；正文按桶拼接、**省略为 0 的段**：`入账 N 笔（¥x.xx）`（两位小数）、`跳过 x 笔`、`失败 x 张`、有前文时 `另有 x 张阻塞，打开 App 后继续` / 纯阻塞时 `x 张阻塞，打开 App 后继续`。段序固定；有入账/跳过/失败与阻塞并存时用 `；` 接阻塞句。**失败张** = 本批一切不自动重试的终态整图（含未识别、终态 API/网络、落库失败折成张等），≠ **阻塞**。点击：失败张>0→明细+失败 Dialog（多张原因换行合并）；否则→明细，有入账则仍可滚到成功笔。未点不弹。无通知权限仍可直存。未就绪：后台失败通知引导设置；前台轻提示或「去设置」Dialog（ADR-071）。直存批次开始时开启返回保活，批次结束关闭。

**后台直存前台服务（ADR-054 / 063 / 069 / 076）：** Android 截图/分享 Vision 批次持有 `AutoBillingForegroundService`（`dataSync`），保证 App 在 `paused` 或冷启动分享后立即 `moveTaskToBack` 时 Dart 与网络仍可执行；进度通知与 `piggy_auto_billing` 渠道同 id（1001）。**归属（ADR-076）：** holders `{assoc, share, batch, retry}`，空才 stop；关联窗取消只放 `assoc`，不误杀分享/批次，**仍发**取消结果 1101；补扫相位「补扫到截图 / 正在补识别…」；顺序 stop FGS 后再发「识别结果」。分享入账：**Relay 拷图成功即同 id 直发进度并起 FGS**（早于 Dart / 早于主界面闪现，ADR-063），且 **等 `startForeground`（或短超时）后再进 MainActivity**（ADR-069，避免冷启空窗），且须在 `moveTaskToBack` **之前**已持有 FGS（ADR-054）。普通 `start`/`update` 亦先直发再 `startForegroundService`。Dart `isActive` 须与原生对齐，批次结束再 `stop`。传输失败且当时 App 不在前台：入本机队列记 **阻塞**（不入失败张）；批次结果通知按上款写出阻塞段。`resumed` 时进度（不横幅）「识别继续」/「继续调用AI分析」（仅 retry 相位，不全局劫持），再 `retryPendingOnResume` 串行重跑；整批空后用同 result id 发「识别结果」横幅。

**截图关联窗（ADR-068；废止独立稳定期 / 2min 总时限 / ±15s 删原补扫）：** 检出即开 **15s 关联窗**（自首次检出）并早期进度（**原生立刻起 FGS**「检测到截图」，Dart 再对齐 `isActive`）；同路径不重置时钟（名称+size 未变则忽略）；门闩读当前磁盘文件。窗内原仍在又来新图 → **短观察 2s**（旧消失=替换，仍在=连拍）。删原且内存无后继 → **删原短等 2s** 等新候选（来了=替换，超时取消并通知「截图已取消，未入账」）。**真替换立刻入账门闩**。废止 DATE_ADDED±15s 当场捞盘补扫与候选 2min 硬切。**非候选过滤**：`IS_TRASHED`、path/name 含 trash、DISPLAY_NAME 含 `@delete` 不入候选（短日志）。门闩前不入已处理集。连拍各路径独立；Vision 仍串行。分享入账、前台选图不走上述窗口。程序日志时长用 **s**。

Android：`ScreenshotObserver`（MediaStore + **监听目录∩关键词** + 关联窗 + 短观察 + 删原短等；ADR-070）。**首次**开开关做目录发现扫描后进入目录页（再次开启保留已存列表，不自动重扫）；空列表不注册 Observer，监听目录行**副标题**红字「不可用，未配置监听目录」。目录详情列表：主标题相对键，副标题**展示用绝对路径**（运行时主存储根 + 相对键，灰字不省略）。**回前台补扫（ADR-074 / 076）：** 开关开时 `paused` 记水位 W；`resumed` 幂等重绑后扫 `DATE_ADDED > max(W, now−24h)`（无 W 回退 5min）并立刻门闩；扫成功后 W=`now`；进度文案「补扫到截图 / 正在补识别…」（非关联窗「等待确认」）。去重靠路径 `processed`，不靠水位。iOS：保持原样（快捷指令引导；无监听目录入口）。

### 关键规则

- 「我的」不放选图入口  
- **应用内轻反馈（ADR-071）：** 纯文案用 `PigToast`（root Overlay 白胶囊，偏下约 65%～70% 屏高）；需「去设置」等操作用 Dialog；不用 SnackBar  
- 后台日志：触发→识别→落库；Vision 记录调用与切换（ADR-053 / ADR-055 / **072**；无同商 3s 再打）  
- 报表对话助手已下线（ADR-049）；历史 `source=ai_chat` 保留不迁移  

### 代码

`auto_billing_service.dart` · `billing_notification_service.dart` · `pending_billing_retry_store.dart` · `foreground_billing_bridge.dart` · `image_share_handler.dart` · `share_early_progress_gate.dart` · `screenshot_monitor_service.dart` · `android_activity_bridge.dart` · Native `AutoBillingForegroundService.kt` · `ShareRelayActivity.kt` · `SharedImageIngress.kt` · `ScreenshotObserver.kt` · `MainActivity` activity channel · `speech_engine_preference.dart` · `offline_asr_model_store.dart` · `voice_recognition_session.dart` · `voice_audio_recorder.dart` · `bill_select_tile.dart`

---

# F · 数据互通

云配置、多端同步、本机 CSV 是三条线。

## 9. 云服务与同步

### 做什么

自备网盘上对齐「这个人的全部账本 + 全局目录」。

### 怎么跑

**入口拆分（「我的」同卡：云服务 → 同步 → 数据管理）：**

| 页 | 职责 |
|---|---|
| 云服务 | 关/WebDAV/S3 + 测连（测当前表单，不隐式整单保存）→ 已测通指纹 |
| 同步 | 主按钮「同步」；自动同步开关占位不可用 |
| 明细同步钮 | 同一套流程，不先开同步页 |

已测通 = 已保存 + 字段齐 + 指纹一致。改凭证失效。

**同步流程：**

```
已测通 → 确认（建议先导出）→ 拉 piggy_workspace.json
  → 合并 → 预览（目录/账本/账单；疑似重复可选保留/合并）→ 写云 + apply 本机
```

**次序：** 分类对齐（支/收分开，UUID→同名折；落树：新增主→子变主→改挂→新增子→主变子→删）→ 标签 → 账本同名折合（改写指纹中账本 UUID）→ 账单按身份合并。分类/标签按**名称**挂回。载荷禁带本机自增 id。

**指纹：** 账本 UUID + 金额到分 + 时间到秒；改金额/时间换指纹不换身份。本机存活账单禁止同指纹。同步预览对「不同身份、相同指纹」可选合并或保留；合并整条 LWW，落败留墓碑（ADR-044）。

### 关键规则

- 冲突：较晚改动整条覆盖  
- 账单墓碑超过 90 天：写云前裁掉，本机同步时硬删  
- 不同步：自定义图标、家庭共账、云上可读 CSV  
- 曾用「当前账本 CSV 上传下载」当同步 → **已废止**（ADR-042）；拆页与已测通仍有效（ADR-041）  
- S3：简化 Bearer，非 SigV4 → 测试用 **WebDAV**  
- 风险：先写云再 apply；本机失败时云可能已新  

### 代码

`cloud_sync_page.dart` · `sync_page.dart` · `cloud_sync_actions.dart` · `cloud_sync_service.dart` · `lib/sync/workspace_*.dart` · `bill_fingerprint.dart` · `test/workspace_*_test.dart`

---

## 10. CSV 与分类包

### 做什么

本机文件进出；**不是**同步。

### 怎么跑 · 账单 CSV

1. 数据管理：导入/导出；页上「AI 智能映射」开关（拨动不调模型）  
2. 无表头（首行像一笔账）→ 拒绝  
3. 关 AI：仅列名映射；开 AI：列名→分类→标签（空步跳过），逐步调文本模型  
4. 日期/金额必映射；类型未映射当支出；账本名未映射进当前本；CSV 中**未知账本名会新建**  
5. 分类/标签映射弹层：**自动**（匹配/建树或外部导入）vs **忽略**（分类空 / 该标签名不挂）；默认自动  
6. 确认后 **导入进度层**（不可取消；已写入不回滚）  

导出：Android `Download/PiggyCount/`；iOS 分享。

### 怎么跑 · 分类包

分类管理导入 CSV/YAML/zip（含 BeeCount）；合并或覆盖 → 进度层；**无**映射向导。导出 zip 可含 `custom_icons/`。

### 代码

`data_manage_page.dart` · `import_mapping_*.dart` · `lib/services/csv/*` · `import_progress_layer.dart` · `test/csv_*_test.dart`

---

# G · 桌面扩展

## 11. Android 收支速览

### 做什么

桌面看今日/本月速览并深链回 App。仅 Android；仅这一种内容类型。

### 怎么跑

| 规格 | 布局与点击 |
|---|---|
| 小 | 圆点+「今日支出」（无眼睛）；底栏本月收支均分无竖线（标签 8）；**今日支出大数字**→金额隐私切换；其余→记支出；约 2×2 |
| 中 | 今日支出\|收入 +「+」记支出 + 近 7 日柱；**跟槽渲图**（ADR-062）：宽=槽宽、高=槽高，不锁 2:1、不分宽度桶；上下透明与浮卡按总高 `10:162:10` 比例始终画出；卡内今日/柱图按浮卡内比例；热区 weight 对齐；「+」热区勿固定 dp；满行×高 2 |

**小号本月金额：** `<1k` 为 `¥`+整数；`[1k,1w)` 为 `¥x.xxk`；`≥1w` 为 `¥x.xxw`（档内截断两位）。今日支出仍完整两位小数。见 `formatWidgetMoneyCompact`。

**热区（ADR-061；部分取代 024）：** 无眼睛图标。小号：今日支出大数字→隐私；其余→记支出。中号：今日支出/收入**金额行**→隐私；「+」→记支出；柱图→报表自定义近 7 日；标签与顶/底垫、间距等其余浮卡区→明细；上下透明边不可点。勿做左右半卡分记收支。小/中隐私开关相互独立。

仿毛玻璃 ~85% 不透明。隐藏金额 `****`，柱压等高点。刷新：保存/回前台/~30分/每日0:00；添加时进程在则立刻重渲。金额隐私切换走后台就地重渲；写 `glance_privacy_toggled_at` 后 3s 内跳过主进程全量重渲（防二次闪烁）。

渲图 → `home_widget` → RemoteViews（中号以 ADR-062 为准：跟槽 `W×H`，XML 写死 `fitCenter`，禁 `centerCrop` 裁透明边，禁运行时 `setScaleType`）。槽位：渲图宽 = `max(上报宽, minWidth 320, 设计宽 364, 屏宽÷格网列数×4格)`，高跟上报；options 未就绪保留上次槽；槽尺寸变化打一条 info（ADR-065，不做 options 全量 dump / onResume diag）；`WidgetSpec.resolveMediumLogicalSize()` 与隐私就地重渲共用。旧图保留至新图就绪。深链 `piggycount://`；关 Flutter 默认深链；与图标同 `MainActivity`（禁空 taskAffinity）。**桌面图标**冷启白猪；小组件经 `WidgetRelayActivity` 中转，冷/热均零启动页（冷启可接受短暂浅色等待）。

### 代码

`lib/widget/*` · `app_link_service.dart` · `Glance*WidgetProvider.kt` · `WidgetRefreshBridge.kt` · `WidgetLaunch.kt` · `WidgetRelayActivity.kt` · `widget_management_page.dart` · `drawable-nodpi/widget_preview_glance*.png`

---

# H · 系统与发布

## 12. 程序日志与导出

### 做什么

排障用运行记录；统一本机导出目录。

### 怎么跑

关于页入口（与使用教程同级）。关键节点 + 未捕获异常；48h + ≤2000 条。

**节点域：** 启动失败；AI/测连失败与未就绪；**AI 每次生产请求（tag `AI`：调用 provider+model；Vision 回退时切换服务商，ADR-053 / **072**）**；云同步；CSV；截图/分享/拍照选图失败；**截图关联窗状态跃迁**（tag `Screenshot`：关联窗检出 / 同路径忽略或不重置 / 非候选过滤 / 短观察开始与结论 / 删原短等 / 替换立刻入账 / 门闩通过或失败 / 候选取消；不含门闩心跳，ADR-065 / **068**）。普通记账成功不打点。禁写 Key/Secret/整份 CSV。临时联调 tag（如曾用的 `ShareProgress`）不得合入发布默认路径。

导出：Android `Download/PiggyCount/`；iOS 分享。教程本轮不介绍日志。教程在关于页内可展开章节。

### 代码

`logger_service.dart` · `program_log_page.dart` · `about_page.dart` · `usage_tutorial_page.dart` · `local_export_service.dart`

---

## 13. 品牌与启动资源

| 用途 | 资源 |
|---|---|
| 桌面 / 关于 | `assets/brand/app_icon.png`（~70% 猪；Adaptive 再 16% inset；须 `icon`+`roundIcon`） |
| 启动 | `splash_icon.png`（~66% 居中）；**勿**拿 app_icon 直接做 Android 12+ 圆裁；放大桌面猪时勿顺手再生启动图 |
| 明细顶栏 | `piggyCount` 小图标 |

生成：`flutter_launcher_icons` · `tool/gen_splash_icon.py` · `flutter_native_splash`。主题 `icon_preferred` 保证**桌面图标**冷启白猪。

---

## 14. 0.1.0 发布

### 范围

| 项 | 决定 |
|---|---|
| 版本 | `0.1.0+1` |
| 分发 | 公开 GitHub；Release 附 `arm64-v8a` APK；本机 `venv/APK` 留 split-per-abi 全套 |
| 平台 | Android 真机为主 |
| 签名 | debug/自签；keystore 不进 git |
| 包体 | `split-per-abi`；暂不开 R8 |

### 风险

1. Release 仍 debug 签名 → 换正式签须卸载重装  
2. S3 非 SigV4 → 用 WebDAV  
3. 同步先写云再 apply  
4. 截图自动 = 读图 + Vision 直存（默认关）  
5. 改金额/时间换指纹（不换身份；旧指纹当身份会裂账，见 ADR-044）  
6. 无 ProGuard，勿贸然 minify  
7. Schema v9 大库升级可能慢  
8. 双端 applicationId 字符串不一致  
9. 自动同步不可用  

### 验收（Android）

- [ ] `flutter test` / `analyze`；split-per-abi；关于页 0.1.0；冷启白猪  
- [ ] 账本 CRUD；记一笔全路径；日历；搜索批量  
- [ ] 报表再显与下钻；排行全页  
- [ ] 分类/标签清除与恢复；彩标/标签色  
- [ ] AI 测通绑定；扇形拍照/语音/图片；截图自动 / 分享入账  
- [ ] CSV 开关关/开；WebDAV 同步预览；未测通禁用  
- [ ] 小组件热区与深链；日志无 Key  

### 构建

```bash
flutter pub get && flutter test && flutter analyze
flutter build apk --release --split-per-abi
```

### 之后

正式签名、SigV4 或只推 WebDAV、minify、iOS 小组件、自动同步、商店策略。

---

## 附录 · 决策编号对照

> **陷阱：** `0020`=ADR-020；`ADR-021-….md` 带前缀；**039**=备注层，**0039**=启动只播种一次。

| 编号 | 主题 | 备注 |
|---|---|---|
| 001 | 分类两层树 | |
| 002 | 记一笔扇形 | |
| 003 | 明细顶栏/日历/搜索 | |
| 004 | 分类自定义图标 | |
| 005 | 报表再显刷新 | |
| 006 | 标签组 | |
| 007 | 我的分区与已测通 | 动作模型→041/042；门槛仍有效 |
| 008 | 分类彩标 | 环色见 033 |
| 009 / 032 | 多服务商；测通态 | |
| 010 | 教程；开关无副标题 | |
| 011 / 012 | 默认树；标签出厂；清除未使用 | |
| 013 / 016 | 选标弹层；备注旁相机；周期弹层 | |
| 014 / 022 | 程序日志；导出目录 | |
| 015 / 021 / 025 / 030 / 038 | 品牌与启动 | 资产分离 |
| 017 / 035 / 036 | 标签色；新鲜度；chip 横滑 | |
| 018 / 020 | 后台直存；确认复选 | |
| 019 | ~~半卡左右记一笔~~ | **024 取代** |
| 023–028 / 030 / 034 | 小组件 | 布局/渲图基线；热区 IA 以 **061** 为准；中号画布尺寸以 **062** 为准 |
| 029 | 统一账单行 | |
| 031 | 退役空默认组 | 落点→外部导入（0039） |
| 033 / 037 | 报表三卡；环 Top8；浮动球 | |
| 039 / 0039 / 040 | 备注层 / 播种一次 / 弹层限高 | 039≠0039 |
| 041 / 042 / 043 | 拆页；工作区合并；映射自动/忽略 | |
| 044 | 账单身份与指纹分离 | 身份 UUID；指纹去重；预览折合；墓碑 90 天 |
| 045 | 截图稳定期 | **部分废止见 068**；原安静等待模型 |
| 046 | 用户可见统计排除墓碑 | 报表/小组件/AI 只计存活；删除确认「删除后不可恢复」 |
| 047 | AI 分类消歧 | Prompt 主类分组 +「主类-子类」；匹配兼容裸名；展示仍裸名 |
| 048 | 截图替换关联窗 | **部分废止见 068**；原稳定期+关联窗双阶段 |
| 049 | 下线 AI 智能助手 | 报表球/对话/开关移除；扇形与后台直存保留 |
| 050 | 待核对账单 | 高亮仅前台；信封持久+红点+一键已读；screenshot/share；syncId；仅明细 |
| 051 | 记一笔时间选择 | 弃用系统表盘；Dialog 双输入 + 0–23 / 每 5 分快捷格 |
| 052 | 多引擎语音识别 | 废止「无大模型 ASR」；系统 / Vosk / Whisper / AI 直接记账；离线包 ModelScope 下载；确认门闩不变 |
| 053 | AI 请求与重试日志 | 每次生产调用 INFO（provider+model）；Vision 回退切换；测连不打点；同商 3s 已废（见 **072**） |
| 055 | 前台 Vision 服务商切换 | 每模型 1 次、失败即切；弹层展示失败原因与切换提示 |
| 054 | 后台直存前台服务 | FGS `dataSync`；分享先 FGS 再退后台；传输失败后台入队、resumed 重试 |
| 056 | 直存结果按账单笔数 | 成功/跳过/失败按候选分桶；整图未入账用「张」；点击看成功笔数 |
| 057 | 前台弹层未就绪引导 | 语音/图片确认弹层只弹层内「去设置」；不叠轻提示；后台通知仍独立 |
| 058 | 多图选图与多选分享 | 系统多选（无 App 闸门）；确认按图分组；上限 9 截取；Android `SEND_MULTIPLE` 同后台直存 |
| 059 | 智谱语音测连音频 | 测连用 1s 16-bit 静音 WAV（对齐 BeeCount）；空 data 触发 1210；静音空响应算成功；音频块在文本前 |
| 060 | 语音记账音频模式还原 | 仅 Android；关层条件还原；重新说不还原；mode 仍为我们留下的通信类才写回 |
| 061 | 收支速览热区 | 金额热区=隐私切换；去眼睛；中号「+」记支出、柱图报表近 7 日、其余浮卡区明细 |
| 062 | 中号跟槽渲图 | 渲图宽 max(上报,320,364,格网估宽)；单候选直取、多候选优先面积；options 未就绪保留上次槽；纵向 `10:162:10`；全量 options / onResume diag 已废（见 **065**） |
| 063 | 分享入账早期 FGS | Relay 即 FGS；去 notify delay；Dart startForegroundService；已收到最短 1s；见 `docs/adr/063-*.md` |
| 064 | 截图关联窗起算与补扫 | **部分废止见 068**；原自稳定期满起算 + 2min + ±15s 补扫 |
| 065 | 日志去掉临时排障面 | 删 `ShareProgress` / Widget options dump；截图 settle 仅状态跃迁；FGS/ShareRelay/语音音频只留失败日志；见 `docs/adr/065-*.md` |
| 066 | 分享 / FGS 去冗余 | 删旧单路径 API；start≡update；文案单源；分享不二次截断；MainActivity 直收 SEND 保留；见 `docs/adr/066-*.md` |
| 067 | 废止系统 ASR | 默认未启用；见 `docs/adr/067-*.md` |
| 068 | 截图单关联窗 | 废独立稳定期与 2min/±15s 补扫；15s 窗+短观察+删原短等；替换即门闩；见 `docs/adr/068-*.md` |
| 069 | 分享冷启早期进度必现 | `start` 先同 id 直发再 FGS；Relay `startForShareIngress` 等 startForeground（≤1.5s）再进主界面；见 `docs/adr/069-*.md` |
| 070 | 截图监听目录 | Android：首次开启发现→进目录页；目录∩关键词；空列表不注册 Observer+红字；重扫整表替换+确认；列表副标题展示用绝对路径；iOS 不变；见 `docs/adr/070-*.md` |
| 071 | 轻提示 PigToast | 白胶囊 Overlay 取代纯文案 SnackBar；需「去设置」改 Dialog；见 `docs/adr/071-*.md` / `docs/glossary.md` |
| 072 | 后台 Vision 每商一次 | 直存与前台对齐：每已测通商仅 1 次、失败即换商；取消同商 3s；判定与阻塞不变；见 `docs/adr/072-*.md` |
| 073 | 截图后台假死诊断 | 监听假死≠Observer 永久卸载；阻塞为设计路径；缓解含 resume 重绑+5min 补扫；见 `docs/adr/073-*.md` |
| 074 | 回前台水位线补扫 | `paused` 记 W；`resumed` 扫 W～now∩24h，无 W 回退 5min；不去重靠水位；见 `docs/adr/074-*.md` |
| 075 | 直存分享优先队列 | `share` > `screenshot`；不打断 inflight；等时 FGS 提示；段中途 flush 见 **076**；见 `docs/adr/075-*.md` |
| 076 | 直存通知 FGS 归属 | holders+相位；取消不误杀；补扫独立文案；整批空再「识别结果」；stop→result；见 `docs/adr/076-*.md` |
