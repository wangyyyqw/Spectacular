# S3 CJK 两端对齐（letterSpacing）实验结果

> 实验日期：2026-10-22　执行人：Lead
> 对应方案：§15 / §79.5，落点 §8.4

## 1. 结论

**通过，采用“按可分配间隙 + 单字符 SpanStyle”的 gap 方案。**

- 20 个全角字自然宽 320；目标 320 / 336 / 400 三组，整行 `ls = (target - 320) / 20` 时宽度误差均为 **0px**，满足 §79.5 的 <1px。
- 字框重叠检测最大值 **0**，字符没有互相压叠。
- **系统 `TextAlign.justify` 对纯中文不生效**：同一段文字设 `justify` 后宽度仍是 320，必须手工实现。
- 整行统一加 `letterSpacing` 会在末字后多留一个 `ls`；改成按 gap 索引逐字加 span 后，间距只落在字符之间，末字起点更靠右。补充实验见 §4。

## 2. 环境

| 项 | 值 |
|---|---|
| Flutter | 3.47.5 stable |
| Dart | 3.13.4 |
| 平台 | macOS x64 |
| 字体 | `SourceHanSerifSC-Regular.otf`（OFL） |
| 字号 | 16 |
| 文本 | `一二三四五六七八九十一二三四五六七八九十`（20 个全角字） |
| 测量 | `TextPainter.width`、`LineMetrics.width`、`getBoxesForSelection(tight)`、`getOffsetForCaret` |

## 3. 数据

| 目标宽 | 自然宽 | extra | ls | 实测宽 | 宽度误差 | 行数 | 最大字框重叠 |
|---|---|---|---|---|---|---|---|
| 320 | 320 | 0 | 0 | 320.0 | 0.0 | 1 | 0.0 |
| 336 | 320 | 16 | 0.8 | 336.0 | 0.0 | 1 | 0.0 |
| 400 | 320 | 80 | 4.0 | 400.0 | 0.0 | 1 | 0.0 |

`TextAlign.justify` 单独使用：宽度 320.0，行宽 [320.0]，与左对齐完全一致，未拉伸。

## 4. gap 方案与整行方案对比

阅微的 `adaptiveJustify` 不是整行加字距，而是先算出可分配间隙，再把间距逐个加到**间隙左侧字符**的单字符 `SpanStyle` 上。我们在同一环境补了对比实验（`test/s3_gap_result_test.dart`）：

| 文本 | 目标宽 | gap 数 | 整行方案末字起点 | gap 方案末字起点 | 两种方案行宽 |
|---|---|---|---|---|---|
| 纯中文 20 字 | 336 | 19 | 319.60 | 320.42 | 336.0 / 335.9999 |
| 纯中文 20 字 | 400 | 19 | 382.00 | 386.11 | 400.0 / 399.9999 |
| 中英混排 16 字 | 336 | 9 | 315.81 | 327.45 | 336.0 / 336.0 |
| 中英混排 16 字 | 400 | 9 | 377.81 | 395.00 | 400.0 / 399.9999 |

- gap 数：纯中文 `n-1`（19）；中英混排跳过 English 内部 6 个位置，剩 9 个。
- 两种方案的 `LineMetrics.width` 都等于目标宽（误差 <0.001px），但 gap 方案把最后一个 `ls` 从“末字之后”移到了字符之间，末字起点更靠右。
- 末字位置取 `getOffsetForCaret`，包含字形左侧 bearing，所以表中是相对比较，不是绝对右缘。
- 字框重叠仍为 0。

**两个实现细节保留：**

**① 尾部空隙。** 整行方案会在末字后多留一个 `ls`（本实验 0.8px / 4px）；gap 方案不再有这个问题。

**② 逐字 caret 间距不是严格等距。** 目标 400 时 caret 间距在 18～20 之间，目标 336 时在 16.4～16.8 之间。这是字形 advance、hinting 与 `getOffsetForCaret` 取整共同造成的，不代表视觉不齐；断言应使用“总宽误差 + 字框不重叠”，不要要求 caret 等距。

## 5. 对 §8.4 的落地

```dart
extra = maxWidth - lineWidth;
if (extra > 0 && 该行含 CJK && 不是末行/硬换行) {
  final gaps = <int>[
    for (var i = 0; i + 1 < text.length; i++)
      if (text[i] != '\n' &&
          text[i + 1] != '\n' &&
          !(isLatinWordPart(text[i]) && isLatinWordPart(text[i + 1])))
        i,
  ];
  if (gaps.isNotEmpty) {
    final ls = extra / gaps.length;
    for (final i in gaps) {
      // 只给“间隙左侧字符”加一个单字符 SpanStyle；
      // 覆盖式设置，必须把原有 letterSpacing 加回来
      spans[i] = SpanStyle(letterSpacing: baseLetterSpacing + ls);
    }
  }
}
```

- gap 定义：相邻字符之间；跳过换行；跳过两侧都是拉丁字母/数字的间隙（不拆英文单词内部）；
- 只给 gap 左侧字符加单字符 span，末字不额外加间距；
- 行宽核验用 `LineMetrics.width`，目标误差 <1px；
- 不检查 caret 等距，只检查 `getBoxesForSelection(..., tight)` 无重叠；
- 末行、硬换行不拉伸（本次只验证了单行，多行场景在 M1 分页器联调时补测）；
- 西文行仍走“拉伸词间空格”，不要给西文词内加字距。

## 6. 验证与复现

```bash
cd 方案/spike/s4_kinsoku
flutter test test/s3_result_test.dart
flutter test test/s3_gap_result_test.dart
```

产物：

- `方案/spike/s4_kinsoku/test/s3_result_test.dart`
- `方案/spike/s4_kinsoku/test/s3_gap_result_test.dart`
- `方案/spike/s4_kinsoku/s3-result.json`
- `方案/spike/s4_kinsoku/s3-gap-result.json`

## 7. 残余风险

- 中英混排只测了固定样本（English 一个词），行内样式切换、ruby/emphasis 的行宽与对齐尚未测。
- gap 方案在“拉丁词很多、可分配间隙很少”的行上会把 `ls` 拉得很大（本实验中英混排 400 宽时 9 个 gap，单 gap 约 22px）；需要在排版层限制单行最大拉伸量，超过阈值时回退为“不拉伸”或改为拉伸词间空格。
- 未在真机复测；设备字体回退可能改变自然宽，但 `ls` 按实测自然宽动态计算，方法本身不依赖字体。
