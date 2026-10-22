# S1 行高 / 基线实验结果

> 实验日期：2026-10-22　执行人：Lead
> 对应方案：§15 / §79.3，落点 §61.1

## 1. 结论

**通过，但必须显式设置 `leadingDistribution: TextLeadingDistribution.even`。**

- `TextPainter` 的 `LineMetrics.height` 精确等于 `fontSize × lineHeight`（三组误差均为 0），可以直接作为 CSS 行框高度。
- 基线：设置 `TextLeadingDistribution.even` 后，按“原始字体 ascent/descent + 半行距”算出的预期基线与实际误差最大 **0.0000067px**，远小于 §79.3 的 0.5px 阈值。
- Flutter 默认的 `proportional` 分布不符合 CSS 半行距模型：三组误差最大 **4.745px**（28×2.0），另两组为 0.303px、1.427px；2/3 组超过 0.5px。
- 实现上不要用 `LineMetrics.ascent` 再减一次行距：它的 `ascent + descent` 已经等于行框高度，`baseline = top + LineMetrics.ascent` 即可。

## 2. 环境

| 项 | 值 |
|---|---|
| Flutter | 3.47.5 stable |
| Dart | 3.13.4 |
| 平台 | macOS x64 |
| 字体 | `SourceHanSerifSC-Regular.otf`（OFL），字号 16 / 20 / 28 |
| 段落 | 3 行，`\n` 强制换行，宽度 400 |
| 组 | 16×1.5、20×1.2、28×2.0 |
| 原始字体度量 | 用 `TextStyle(height: null)` 另测一次取得 ascent/descent |

## 3. 数据

| 组 | 行高 | 基线（even） | 期望基线 | even 误差 | proportional 误差 |
|---|---|---|---|---|---|
| 16×1.5 | 24.0 | 18.920 | 18.920 | 0.000000 | 0.303 |
| 16×1.5 | 24.0 | 42.920 | 42.920 | 0.000000 | 0.303 |
| 16×1.5 | 24.0 | 66.920 | 66.920 | 0.000000 | 0.303 |
| 20×1.2 | 24.0 | 20.650 | 20.650 | 0.000000 | 1.427 |
| 20×1.2 | 24.0 | 44.650 | 44.650 | 0.000000 | 1.427 |
| 20×1.2 | 24.0 | 68.650 | 68.650 | 0.000000 | 1.427 |
| 28×2.0 | 56.0 | 40.110 | 40.110 | 0.000001 | 4.745 |
| 28×2.0 | 56.0 | 96.110 | 96.110 | 0.000001 | 4.745 |
| 28×2.0 | 56.0 | 152.110 | 152.110 | 0.000007 | 4.745 |

汇总：

```
maxHeightError = 0.0
maxEvenBaselineError = 0.00000667572021484375
maxProportionalBaselineError = 4.744536399841309
```

说明：28×2.0 的第二行实际基线 96.110，与第一行 40.110 的差值正好 56，行距稳定；16×1.5 的 proportional 误差 0.303 是因为该字号下字体默认行高接近 1.5em，半行距几乎为 0。

## 4. 对 §61.1 的落地修正

原公式：

```
leading    = lineHeight - fontSizeAscent - fontSizeDescent
leadingTop = leading / 2
baseline   = top + leadingTop + ascent
```

在 Flutter 里要分两种度量：

- **原始字体度量**（`fontAscent` / `fontDescent`）：用 `height: null` 的测量取得；公式按上面写成立。
- **行框度量**（`LineMetrics.ascent` / `.descent`）：已经包含半行距，且 `ascent + descent == height`。此时应写成
  `baseline = top + LineMetrics.ascent`，不要再套 `leading / 2`。

实现约定：

1. 所有 `TextStyle` 显式设置 `leadingDistribution: TextLeadingDistribution.even`；
2. 行高直接取 `LineMetrics.height`，不要自算；
3. 基线直接取 `LineMetrics.baseline`，或按 `top + LineMetrics.ascent` 累加；
4. `LineMetrics` 的 ascent/descent 不要当字体原始度量复用（它们是行框值），字体原始度量另走 `height: null` 的辅助测量。

## 5. 验证与复现

```bash
cd 方案/spike/s4_kinsoku
flutter test test/s1_result_test.dart
```

产物：

- `方案/spike/s4_kinsoku/test/s1_result_test.dart`
- `方案/spike/s4_kinsoku/s1-result.json`

## 6. 残余风险

- 只测了 Source Han Serif SC 一款字体；不同字体的 ascent/descent 比例不同，但“`height` 精确、`even` 匹配 CSS”的结论应与字体无关。
- 只测了 3 组参数、3 行文本；未覆盖 ruby、上下标行内调整和竖排，这些会改变行框，需在 M4 单独验。
- 未在真机复测；`flutter test` 与设备同用 SkParagraph，风险主要在字体回退后的度量差异。
