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

  test('相邻 margin 折叠规则', () {
    expect(collapseMargins(20, 8), 20, reason: '正正取大');
    expect(collapseMargins(8, 20), 20);
    expect(collapseMargins(-10, -6), -10, reason: '负负取小');
    expect(collapseMargins(20, -8), 12, reason: '正负相加');
    expect(collapseMargins(-8, 20), 12);
    expect(collapseMargins(0, 0), 0);
    expect(collapseMargins(0, 12), 12);
    expect(collapseMargins(0, -12), -12);
  });

  test('相邻正 margin 取较大值', () {
    final first = _text('aa', bottom: 20);
    final second = _text('bb', top: 8);
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints);

    expect(root.childTops[0], closeTo(0, 0.01));
    expect(root.childTops[1], closeTo(44, 0.01));
    expect(root.size.height, closeTo(68, 0.01));
  });

  test('相邻正 margin 交换顺序仍取较大值', () {
    final first = _text('aa', bottom: 8);
    final second = _text('bb', top: 20);
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints);

    expect(root.childTops[1], closeTo(44, 0.01));
    expect(root.size.height, closeTo(68, 0.01));
  });

  test('正负 margin 相加', () {
    final first = _text('aa', bottom: 20);
    final second = _text('bb', top: -8);
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints);

    expect(root.childTops[1], closeTo(36, 0.01), reason: '24 + (20-8)');
    expect(root.size.height, closeTo(60, 0.01));
  });

  test('负负 margin 取更负值', () {
    final first = _text('aa', bottom: -10);
    final second = _text('bb', top: -6);
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints);

    expect(root.childTops[1], closeTo(14, 0.01), reason: '24 - 10');
    expect(root.size.height, closeTo(38, 0.01));
  });

  test('三块连续时每个间隙独立折叠', () {
    final a = _text('aa', bottom: 20);
    final b = _text('bb', top: 8, bottom: -6);
    final c = _text('cc', top: 4);
    final root = ColumnFlowBlock([a, b, c]);
    root.measure(_constraints);

    expect(root.childTops[0], closeTo(0, 0.01));
    expect(root.childTops[1], closeTo(44, 0.01), reason: '24 + max(20,8)');
    expect(root.childTops[2], closeTo(66, 0.01), reason: '68 + (-6+4)');
    expect(root.size.height, closeTo(90, 0.01));
  });

  test('首块上 margin 逸出并与容器 margin 折叠', () {
    final child = _text('aa', top: 16);
    final root = ColumnFlowBlock([
      child,
    ], const CssEdges(top: 10, right: 0, bottom: 0, left: 0));
    root.measure(_constraints);

    expect(root.childTops.single, 0, reason: '首块上 margin 不占容器内容高度');
    expect(root.size.height, closeTo(24, 0.01));
    expect(root.margin.top, 16, reason: 'max(容器 10, 首块 16)');
  });

  test('末块下 margin 逸出', () {
    final child = _text('aa', bottom: 12);
    final root = ColumnFlowBlock([child]);
    root.measure(_constraints);

    expect(root.size.height, closeTo(24, 0.01));
    expect(root.margin.bottom, 12);
  });

  test('嵌套块 margin 逐层逸出', () {
    final innerText = _text('aa', top: 8, bottom: 8);
    final inner = ColumnFlowBlock([
      innerText,
    ], const CssEdges(top: 4, right: 0, bottom: 4, left: 0));
    final following = _text('bb', top: 2);
    final outer = ColumnFlowBlock([inner, following]);
    outer.measure(_constraints);

    expect(inner.size.height, closeTo(24, 0.01), reason: '子块 margin 逸出');
    expect(inner.margin.top, 8, reason: 'max(4, 8)');
    expect(inner.margin.bottom, 8, reason: 'max(4, 8)');
    expect(outer.childTops[1], closeTo(32, 0.01), reason: '24 + max(8,2)');
    expect(outer.size.height, closeTo(56, 0.01));
  });

  test('空容器的 margin 保持自身值', () {
    final empty = ColumnFlowBlock(
      const <BlockFlow>[],
      const CssEdges(top: 5, right: 0, bottom: 7, left: 0),
    );
    empty.measure(_constraints);

    expect(empty.size, Size.zero);
    expect(empty.margin.top, 5);
    expect(empty.margin.bottom, 7);
  });

  test('基线推进等于前块高度加折叠间距', () {
    final first = _text('aa', bottom: 20);
    final second = _text('bb', top: 8);
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints);

    final advance = root.childTops[1] - root.childTops[0];
    expect(advance, closeTo(24 + 20, 0.01));
  });
}
