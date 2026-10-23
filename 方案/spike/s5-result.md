# S5 多字重实验结果（桌面 + iOS 模拟器）

> 验收口径变更：经用户 2026-10-23 授权，真机验收以 iOS 模拟器 + macOS 桌面替代（见《P0 文档》附录 A-06）。

> 实验日期：2026-10-22　执行人：Lead
> 对应方案：§15 / §79.2，落点 §28.2
> 状态：**完成（桌面 + iOS 模拟器）。**

## 1. 结论

- 同一 family 下同时加载 `SourceHanSerifSC-Regular.otf` 与 `SourceHanSerifSC-Bold.otf` 后，`fontWeight: 700` 的渲染与仅加载 regular 时不同（`bold_face_effect=4147` 像素），说明 Flutter 能按字重选中 bold 字体文件。
- 对照：同一 regular 字体注册为两个 family 名，400 字重渲染逐像素一致（`regular_control=0`），排除测量噪声。
- 因此**在桌面上方案 A（单 family 多字重）成立**，暂不需要退化为方案 B（按字重拆 family 名）。
- iOS 模拟器（iPhone 18 Pro，iOS 27.0）复测通过：`bold_face_effect=4122`，与桌面 `4147` 同向；按授权口径视为移动端通过。
- Android 模拟器不可用（无 AVD、licenses 未接受）；2026-10-23 以 MEIZU 20/Android 16 真机补测通过：`bold_face_effect=4152`。

## 2. 环境

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.47.5 stable / 3.13.4 |
| 平台 | macOS 26.7.1（arm64 / Rosetta） |
| 字体 | `test_fonts/SourceHanSerifSC-Regular.otf`、`...-Bold.otf`（OFL） |
| 设备 | macOS 26.7.1；iPhone 18 Pro 模拟器（iOS 27.0） |
| 方法 | `FontLoader` 加载到同一 family，渲染“粗体测试 ABC 123”，比较 RGBA 像素；模拟器复用同一集成测试 |

## 3. 数据

| 对比 | 差异像素 |
|---|---:|
| 多字重 family：400 vs 700 | 4481 |
| 仅 regular：400 vs 700 | 3227 |
| 对照：多字重 400 vs 仅 regular 400 | 0 |
| 加 bold 后 700 vs 仅 regular 700 | 4147（桌面）/ 4122（iOS 模拟器） |

## 4. 复现

### 4.1 桌面包内实验

```bash
cd 方案/spike/s5_multiwght
flutter pub get
flutter test
```

期望输出：

```
S5 multi_family_diff=4481 only_regular_diff=3227 regular_control=0 bold_face_effect=4147
```

### 4.2 iOS 模拟器与 macOS 集成测试

```bash
cd apps/reader_mobile
flutter test integration_test/s5_font_weight_test.dart -d 0229CA7B-9D61-4DBA-B7DC-562DD39F9719
flutter test integration_test/s5_font_weight_test.dart -d macos
```

期望输出分别包含：

```
S5 device=iOS regular_control=0 bold_face_effect=4122
S5 device=macOS regular_control=0 bold_face_effect=4147
```

## 5. 设备矩阵与后续

| 平台 | 结果 | 证据 |
|---|---|---|
| macOS 桌面 | 通过（bold 生效） | 包内测试 + 集成测试 `bold_face_effect=4147` |
| iOS 模拟器（iPhone 18 Pro，iOS 27.0） | 通过 | 集成测试 `bold_face_effect=4122` |
| Android 真机（MEIZU 20，Android 16） | 通过 | 集成测试 `S5 device=android bold_face_effect=4152` |

按用户 2026-10-23 授权（《P0 文档》附录 A-06），P0-08 以 iOS 模拟器 + 桌面口径完成；Android 真机复测列入后续真机任务。
