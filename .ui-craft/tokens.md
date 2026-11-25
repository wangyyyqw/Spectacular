# 颜色与控件约定

真源为 `apps/reader_mobile/lib/theme/app_theme_preset.dart`；组件样式由 `packages/reader_ui/lib/theme/reader_ui_style.dart` 统一。复用 Flutter `ColorScheme`，不建立第二套平行颜色系统。

| 用途 | 语义色 | 清蓝日间 | 清蓝夜间 |
|---|---|---|---|
| 页面与应用栏 | `surfaceContainerLowest` | `#F2F3F5` | `#000000` |
| 卡片、菜单、抽屉、弹窗 | `surface` | `#FFFFFF` | `#191919` |
| 输入框、普通控件底色 | `surfaceContainerLow` | `#F7F8FA` | `#232323` |
| 分隔线、弱轮廓 | `outlineVariant` | `#E2E4E8` | `#353538` |
| 必要的控件轮廓 | `outline` | `#858891` | `#85858D` |
| 主要文字 | `onSurface` | `#1D1D1F` | `#E4E4E7` |
| 辅助文字 | `onSurfaceVariant` | `#686B73` | `#A1A1AA` |
| 主要操作、开启、勾选、焦点 | `primary` | `#0A59F7` | `#7EA8FF` |
| 强调按钮文字 | `onPrimary` | `#FFFFFF` | `#101C33` |
| 选中项底色 | `primaryContainer` | `#EAF0FF` | `#172B4D` |
| 选中项文字 | `onPrimaryContainer` | `#174AB5` | `#C0D4FF` |
| 错误、危险操作 | `error` | `#B34338` | `#F0AAA0` |

- 正常文字使用不透明语义色；禁用控件沿用现有弱化规则。
- 蓝色用于主按钮、导入、当前导航、开启状态、选中标记和输入焦点。普通功能图标采用中性色。
- 提示气泡使用 `inverseSurface / onInverseSurface`，避免在深色界面上错误配对文字颜色。
- 阅读弹层使用宿主软件 `ColorScheme`；正文主题只参与墨水屏识别，不再覆盖软件色板。
- 沿用既有控件 / 卡片 / 面板圆角 12 / 20 / 24，应用正文 / 辅助文字 14 / 12，字体由 `AppFonts` 管理。
- Android 原生启动背景与默认预设的页面背景同步。增加其他预设时需明确原生启动阶段的默认回退，不能假定 Flutter 偏好已加载。

依据：[Flutter ColorScheme](https://api.flutter.dev/flutter/material/ColorScheme-class.html)、[Flutter 无障碍指南](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)。
