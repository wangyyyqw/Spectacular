# S7 图片解码宽度（targetWidth）实验结果

> 实验日期：2026-10-22　执行人：Lead
> 对应方案：§15 / §79.6，落点 §50.3

## 1. 结论

**通过。`instantiateImageCodec(targetWidth:)` 会按目标宽等比降采样，可用于图片内存优化。**

- 原始 1000×500 PNG：无 targetWidth 时解码为 1000×500。
- `targetWidth: 500` → 500×250；`targetWidth: 200` → 200×100，宽高保持原比例。
- 理论解码内存从 2,000,000B 降到 500,000B（500 宽时），为原始 25%。
- 结论只覆盖 macOS 桌面引擎；Android/iOS 需在真机任务（P3-08 / M2 验收）复核，若平台行为不同再回退为手动缩放。

## 2. 环境

| 项 | 值 |
|---|---|
| Flutter | 3.47.5 stable |
| Dart | 3.13.4 |
| 平台 | macOS 26.7.1（arm64 / Rosetta） |
| 测试 | `方案/spike/s7_image/test/s7_image_test.dart` |
| 图像 | 测试内用 `PictureRecorder` 生成 1000×500 纯色 PNG |

## 3. 数据

| 用例 | targetWidth | 解码宽×高 | 理论内存 |
|---|---:|---|---:|
| 原始 | 未设置 | 1000×500 | 2,000,000B |
| 降采样 | 500 | 500×250 | 500,000B |
| 降采样 | 200 | 200×100 | 80,000B |

## 4. 复现

```bash
cd 方案/spike/s7_image
flutter test
```

期望输出包含：

```
S7 target500 width=500 height=250
S7 target200 width=200 height=100
```

## 5. 对实现的影响

- 图片解码统一传 `targetWidth = ceil(显示宽 × devicePixelRatio)`，避免整图解码。
- 缓存键需包含目标宽（不同 DPR/版式下宽度不同）。
- 大图预览走单独解码路径，不复用正文的低分辨率缓存。
