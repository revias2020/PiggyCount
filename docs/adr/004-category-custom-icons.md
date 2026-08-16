# ADR-004：分类自定义图标

- 状态：Accepted（grilling 2026-08-16）
- 背景：编辑分类选图标时需要支持用户自上传图片；布局对齐参考图（图标网格开头虚线框「＋」）；实现参考 BeeCount 自定义图标，但按产品裁剪范围。

## 决策（grilling 锁定）

1. **绑定方式**：自定义图标**仅绑定当前分类**（非跨分类共享图库）。`＋` 只负责为当前分类上传；不在网格里展示「历史上传列表」。
2. **裁剪**：相册选图后**强制 1:1** 裁剪，再压缩存盘（约 96×96 PNG）。
3. **导入导出**：分类导出改为 **zip**：内含与 BeeCount 对齐的分类清单（CSV，字段兼容 `categories.yaml`）+ `custom_icons/` 图片；导入继续支持本应用 zip、BeeCount zip / `categories.yaml`，并落盘自定义图标。
4. **删除图库**：不做共享图库删除（随 1 否决）；换 Material / 删分类时清理该分类对应文件。
5. **选图来源**：**仅相册**（不做拍照）。

## 数据

- `categories.icon_type`：`material` | `custom`（默认 `material`）
- `categories.custom_icon_path`：相对路径，如 `custom_icons/{categoryId}_{ts}.png`
- 文件目录：`ApplicationDocumentsDirectory/custom_icons/`

## 后果

- 分类管理编辑弹层图标网格首位为虚线「＋」；选 Material 则切回 `material` 并清路径。
- 渲染层凡展示分类图标处需识别 `iconType == custom` 走本地图。
- 分类「导出」产出 zip（不再是单 CSV）；导入逻辑扩展写入图标文件。
