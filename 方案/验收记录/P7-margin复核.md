# P7-24 margin 塌陷复核（MarginStrut 对照）

> 任务：P7-24 ｜ 日期：2026-10-24
> 对照物：Reeden `MarginStrut` 模型（`参考/reeden/reports/140-epub-layout.md`）与 CSS 2.2 §8.3.1
> 基线：P2-08 margin 折叠实现 + `margin_collapse_test`（13 例）
> 结论：**发现并修复 1 处真实偏差（空块穿透折叠）**；三类边界两处已覆盖、一处随 P3 落地；P2-09 钳制语义在重构中保持。

## 1. 三类边界复核结果

| MarginStrut 边界 | 本项目现状 | 复核结论 |
|---|---|---|
| 相邻负 margin | `margin_collapse_test` ▸ 正负 margin 相加；负负 margin 取更负值 | ✅ 已覆盖；本轮补「负 margin 相邻对折叠后基线推进与边界包含」显式断言（gap=-10、第二块上移、总高 24-10+24） |
| 浮动容器内块 | 浮动未实现（P3-12） | ⏸ 登记 P3-12：浮动容器内的 margin 折叠随浮动带落地时补用例（P7-06 矩阵 B12 缺口已在案） |
| 首/末子元素穿透折叠 | ▸ 首块上 margin 逸出并与容器 margin 折叠；末块下 margin 逸出；嵌套块 margin 逐层逸出；空容器的 margin 保持自身值 | ✅ 已覆盖 |

## 2. 本轮发现与修复：空块穿透折叠

**现象（检测结果实测）**：零高空容器夹在两块之间时，引擎按「独立间隙」计算——gap1=collapse(4,10)=10、gap2=collapse(30,6)=30，总间距 40；CSS 2.2 要求穿透折叠为单间隙 collapse(4,10,30,6)=30。

**修复（`block_flow.dart` ColumnFlowBlock.onLayout）**：

1. `BlockFlow` 新增 `verticalInsets`（自身垂直 padding+border），自塌陷判定 = 高度 0 且 `verticalInsets == 0`（排除有内边距/边框的空壳容器）；
2. 自塌陷子块**不推进流**（cursor/remaining 不动），其上下 margin 与前块下 margin 合并后向前携带——兄弟间隙变为单折叠值；
3. 首块自塌陷时向上逸出进容器顶 margin（携带清零），末块自塌陷向下逸出进容器底 margin（`firstEffectiveTop`/`lastEffectiveBottom` 取合并值）；
4. **P2-09 钳制保持**：页根容器的首块逸出负 margin 钳制（§60.7）改为作用于合并后的逸出值（自塌陷链同样钳制），`first_margin_clamp_test` 9 例不回退。

**验证**：新断言 `childTops[2] == 24+30`、`height == 78`；全套 585 例通过；5 本样本样式快照无漂移（真实样本无「零高兄弟容器」形态）。

## 3. 与 Reeden MarginStrut 的结构对照

| MarginStrut 职责 | 本项目对应 |
|---|---|
| 折叠方向判定（正正取大/负负取小/正负相加） | `collapseMargins`（P2-08，语义一致） |
| 自塌陷穿透 | **本轮补齐**（此前按独立间隙，偏差已修） |
| 与容器 margin 的逸出合并 | `_collapsedMargin`（首/末逸出 + 本轮自塌陷链扩展） |
| body 首元素负 margin 钳制 | `clampFirstElementNegativeTopMargin`（P2-09，保持并扩展到链值） |

## 4. 验证

```bash
cd packages/reader_core
flutter analyze        # No issues
flutter test           # 585 例通过（margin_collapse 13 + first_margin_clamp 9 + block_invariant 全绿）
```
