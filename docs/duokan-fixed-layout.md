# 多看固定版与漫画兼容

本文说明 Spectacular 对多看一眼扩展语义的安全吸收范围。目标是提升真实
EPUB 的可读性，不追求与多看客户端像素级一致。

## 扩展入口

- 仅读取 `META-INF/duokan-extension.xml` 的 `display-options/layout`、
  `page-width` 与 `page-height`。
- 布局映射：`reflow`、`fixed-page`、`comics-frame`、
  `transverse-comic`、`vertical-comic`。
- 缺失扩展文件时按 `reflow` 打开；损坏 XML、错误根元素、未知布局或非法
  尺寸只写入可恢复警告，不阻止书籍打开，也不改变可读性分级。
- OPF `itemref` 的 `properties` 由核心解析器保留，宿主据此识别
  `duokan-page-fullscreen`、`duokan-page-fitwindow` 与
  `page-spread-left/right`。

## 支持矩阵

| 布局 | 当前行为 |
| --- | --- |
| `reflow` | 完全沿用原有满屏图、全屏页与普通分页路径 |
| `fixed-page` | 单图无正文章节渲染为单页图 |
| `comics-frame` / `transverse-comic` | 单图无正文章节渲染为单页图 |
| `vertical-comic` | 仅识别并记录诊断，回退原有可读路径 |

单页图规则：

- 默认 `contain`，上下左右居中，不裁切。
- `duokan-page-fullscreen` 使用 `cover`。
- `duokan-page-fitwindow` 优先使用 `contain`；与 fullscreen 同时出现时
  fitwindow 优先。
- 图片页四边出血，跳过阅读器页边距、正文字号、页眉和页脚设置。
- 扩展提供合法页宽高时，按其比例在 `~slim` 全屏图变体中选择更接近的
  一张；缺失时沿用视口比例。

## 诊断与回退

诊断按章只保留首个原因，缓存命中和设置变化不会重复生成：

- `E_DUOKAN_EXTENSION_XML`：扩展 XML 损坏或根元素错误。
- `E_DUOKAN_EXTENSION_VALUE`：布局、页宽或页高取值非法。
- `E_DUOKAN_FIXED_LAYOUT_UNSUPPORTED`：多图、含正文等非“单图单页”内容。
- `E_DUOKAN_IMAGE_MISSING`：唯一图片无法解析为包内资源。
- `E_DUOKAN_VERTICAL_COMIC_UNSUPPORTED`：纵向漫画尚未实现。

不支持内容回退到原有全屏或重排路径，并确保正文优先可读。固定版 v1 不
尝试设计多元素画布缩放。

## 非目标

- 不接入 WebView、多看 `.so` 或非标准 CSS 行为。
- 不实现 `PageBreak.xml`、`DKE_Patch`、双页跨页、方向锁与脚注外观。
- 不实现 `vertical-comic` 连续纵向滚动。
- 不修改数据库、书库格式或普通重排缓存结构。
