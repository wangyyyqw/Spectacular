import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';

const _constraints = LayoutConstraints(maxWidth: 320, maxHeight: 480);

/// 一行 Ahem 文本块：高 24，宽 32。
TextFlowBlock _text(String text, {double top = 0, double bottom = 0}) =>
    TextFlowBlock(
      text: text,
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
        'margin-top': '${top}px',
        'margin-bottom': '${bottom}px',
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('钳制规则只在 body 首元素且为负时生效', () {
    expect(
      clampFirstElementNegativeTopMargin(-12, isBodyFirstElement: true),
      0,
    );
    expect(
      clampFirstElementNegativeTopMargin(-12, isBodyFirstElement: false),
      -12,
    );
    expect(
      clampFirstElementNegativeTopMargin(16, isBodyFirstElement: true),
      16,
    );
    expect(clampFirstElementNegativeTopMargin(0, isBodyFirstElement: true), 0);
  });

  test('body 首块负 margin 被钳制，首行不越界', () {
    final root = ColumnFlowBlock.body([_text('aa', top: -12)]);
    root.measure(_constraints);

    expect(root.margin.top, 0, reason: '首块负 margin 钳到 0');
    expect(root.childTops.single, 0);
    expect(root.size.height, closeTo(24, 0.01));
  });

  test('非 body 容器保留首块负 margin', () {
    final root = ColumnFlowBlock([_text('aa', top: -12)]);
    root.measure(_constraints);

    expect(root.margin.top, -12);
    expect(root.childTops.single, 0);
    expect(root.size.height, closeTo(24, 0.01));
  });

  test('body 首块正 margin 不钳制', () {
    final root = ColumnFlowBlock.body([_text('aa', top: 16)]);
    root.measure(_constraints);

    expect(root.margin.top, 16);
    expect(root.size.height, closeTo(24, 0.01));
  });

  test('body 后续块的负 margin 不钳制，仍参与折叠', () {
    final first = _text('aa', bottom: 20);
    final second = _text('bb', top: -8);
    final root = ColumnFlowBlock.body([first, second]);
    root.measure(_constraints);

    expect(root.childTops[1], closeTo(36, 0.01), reason: '24 + (20-8)');
    expect(root.size.height, closeTo(60, 0.01));
  });

  test('内层负 margin 逸出后被 body 钳制', () {
    final inner = ColumnFlowBlock([_text('aa', top: -12)]);
    expect(inner.margin.top, 0, reason: '尚未测量');

    final outer = ColumnFlowBlock.body([inner]);
    outer.measure(_constraints);

    expect(inner.margin.top, -12, reason: '内层不是 body，保留负值');
    expect(outer.margin.top, 0, reason: 'body 把它钳回 0');
    expect(outer.size.height, closeTo(24, 0.01));
  });

  test('body 自身正 margin 与钳制后的首块 margin 折叠', () {
    final root = ColumnFlowBlock.body([
      _text('aa', top: -12),
    ], const CssEdges(top: 6, right: 0, bottom: 0, left: 0));
    root.measure(_constraints);

    expect(root.margin.top, 6, reason: 'max(6, 钳制后的 0)');
  });

  test('body 首行位置与内容高度不含负 margin', () {
    final root = ColumnFlowBlock.body([
      _text('aa', top: -20, bottom: 4),
      _text('bb', top: 8, bottom: 4),
    ]);
    root.measure(_constraints);

    expect(root.childTops.every((top) => top >= 0), isTrue);
    expect(root.childTops[1], closeTo(32, 0.01), reason: '24 + max(4,8)');
    expect(root.size.height, closeTo(56, 0.01));
    expect(root.margin.top, 0);
    expect(root.margin.bottom, 4, reason: '末块下 margin 逸出不钳制');
  });

  test('空 body 保持自身 margin', () {
    final root = ColumnFlowBlock.body(
      const <BlockFlow>[],
      const CssEdges(top: -3, right: 0, bottom: 5, left: 0),
    );
    root.measure(_constraints);

    expect(root.size, Size.zero);
    expect(root.margin.top, -3, reason: '没有首块可钳制');
    expect(root.margin.bottom, 5);
  });
}
