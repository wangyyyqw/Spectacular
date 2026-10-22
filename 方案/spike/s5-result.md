# S5 多字重实验结果（桌面部分）

> 实验日期：2026-10-22　执行人：Lead
> 对应方案：§15 / §79.2，落点 §28.2
> 状态：**桌面通过；真机部分未测，P0-08 尚未完成。**

## 1. 结论（仅 macOS 桌面）

- 同一 family 下同时加载 `SourceHanSerifSC-Regular.otf` 与 `SourceHanSerifSC-Bold.otf` 后，`fontWeight: 700` 的渲染与仅加载 regular 时不同（`bold_face_effect=4147` 像素），说明 Flutter 能按字重选中 bold 字体文件。
- 对照：同一 regular 字体注册为两个 family 名，400 字重渲染逐像素一致（`regular_control=0`），排除测量噪声。
- 因此**在桌面上方案 A（单 family 多字重）成立**，暂不需要退化为方案 B（按字重拆 family 名）。
- 真机（Android/iOS）尚未测试：P0-08 要求“真机与桌面各测一次”，当前无物理设备，因此该任务不计完成。

## 2. 环境

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.47.5 stable / 3.13.4 |
| 平台 | macOS 26.7.1（arm64 / Rosetta） |
| 字体 | `test_fonts/SourceHanSerifSC-Regular.otf`、`...-Bold.otf`（OFL） |
| 方法 | `FontLoader` 加载到同一 family，渲染“粗体测试 ABC 123”，比较 RGBA 像素 |

## 3. 数据

| 对比 | 差异像素 |
|---|---:|
| 多字重 family：400 vs 700 | 4481 |
| 仅 regular：400 vs 700 | 3227 |
| 对照：多字重 400 vs 仅 regular 400 | 0 |
| 加 bold 后 700 vs 仅 regular 700 | 4147 |

## 4. 复现

```bash
cd 方案/spike/s5_multiwght
flutter pub get
flutter test
```

期望输出：

```
S5 multi_family_diff=4481 only_regular_diff=3227 regular_control=0 bold_face_effect=4147
```

## 5. 待办

- Android 与 iOS 真机各复测一次，确认 `fontWeight` 选中行为一致；结果补入本文件后，P0-08 才能勾选。
- 真机若表现为合成粗体或未选中，按技术方案 §28.2 方案 B（按字重拆 family 名 + 样式层映射）处理。
