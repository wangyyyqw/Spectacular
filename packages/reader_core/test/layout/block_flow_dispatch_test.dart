import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';

ComputedStyle _style({
  String? position,
  String? floatValue,
  String? display,
  double fontSize = 16,
}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'position': ?position,
  'float': ?floatValue,
  'display': ?display,
});

const _wide = LayoutConstraints(maxWidth: 320, maxHeight: 480);

Iterable<BlockFlow> _walk(BlockFlow root) sync* {
  yield root;
  for (final child in root.children) {
    yield* _walk(child);
  }
}

String _positionCss(CssPosition value) => switch (value) {
  CssPosition.static => 'static',
  CssPosition.relative => 'relative',
  CssPosition.absolute => 'absolute',
  CssPosition.fixed => 'fixed',
  CssPosition.sticky => 'sticky',
};

String _floatCss(CssFloat value) => switch (value) {
  CssFloat.none => 'none',
  CssFloat.left => 'left',
  CssFloat.right => 'right',
};

String _displayCss(CssDisplay value) => switch (value) {
  CssDisplay.block => 'block',
  CssDisplay.inline => 'inline',
  CssDisplay.inlineBlock => 'inline-block',
  CssDisplay.table => 'table',
  CssDisplay.tableRow => 'table-row',
  CssDisplay.tableCell => 'table-cell',
  CssDisplay.flex => 'flex',
  CssDisplay.listItem => 'list-item',
  CssDisplay.none => 'none',
};

FlowBranch _expectedBranch(
  CssDisplay display,
  CssPosition position,
  CssFloat cssFloat,
) {
  if (position == CssPosition.absolute || position == CssPosition.fixed) {
    return FlowBranch.absolute;
  }
  if (cssFloat != CssFloat.none) {
    return FlowBranch.float;
  }
  if (display == CssDisplay.table ||
      display == CssDisplay.tableRow ||
      display == CssDisplay.tableCell) {
    return FlowBranch.table;
  }
  if (display == CssDisplay.none) {
    return FlowBranch.none;
  }
  if (display == CssDisplay.inline || display == CssDisplay.inlineBlock) {
    return FlowBranch.inline;
  }
  return FlowBranch.block;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('绝对定位优先于浮动与表格', () {
    final style = _style(
      position: 'absolute',
      floatValue: 'left',
      display: 'table',
    );
    expect(resolveFlowBranch(style), FlowBranch.absolute);
  });

  test('fixed 也走绝对定位分支', () {
    expect(resolveFlowBranch(_style(position: 'fixed')), FlowBranch.absolute);
  });

  test('浮动先于表格判定', () {
    final left = _style(floatValue: 'left', display: 'table');
    expect(resolveFlowBranch(left), FlowBranch.float);
    expect(resolveFlowBranch(_style(floatValue: 'right')), FlowBranch.float);
  });

  test('表格与表格行/单元格走表格分支', () {
    for (final display in ['table', 'table-row', 'table-cell']) {
      expect(
        resolveFlowBranch(_style(display: display)),
        FlowBranch.table,
        reason: display,
      );
    }
  });

  test('display: none 不参与测量', () {
    expect(resolveFlowBranch(_style(display: 'none')), FlowBranch.none);
  });

  test('行内与行内块走行内分支', () {
    expect(resolveFlowBranch(_style(display: 'inline')), FlowBranch.inline);
    expect(
      resolveFlowBranch(_style(display: 'inline-block')),
      FlowBranch.inline,
    );
  });

  test('未支持 display 兜底为块级', () {
    expect(resolveFlowBranch(_style(display: 'flex')), FlowBranch.block);
    expect(resolveFlowBranch(_style(display: 'list-item')), FlowBranch.block);
  });

  test('所有枚举组合都有唯一分支且与创建盒一致', () {
    for (final display in CssDisplay.values) {
      for (final position in CssPosition.values) {
        for (final cssFloat in CssFloat.values) {
          final style = _style(
            position: _positionCss(position),
            floatValue: _floatCss(cssFloat),
            display: _displayCss(display),
          );
          final branch = resolveFlowBranch(style);
          expect(
            branch,
            _expectedBranch(display, position, cssFloat),
            reason: '$display/$position/$cssFloat',
          );
          final box = createFlowBox(style: style, text: 'a');
          expect(box.branch, branch);
          box.measure(_wide);
          if (branch == FlowBranch.none) {
            expect(box.size, Size.zero);
          }
        }
      }
    }
  });

  test('混合样本每个节点走对分支', () {
    final absoluteText = createFlowBox(
      style: _style(position: 'absolute'),
      text: 'aa',
    );
    final floatText = createFlowBox(
      style: _style(floatValue: 'left'),
      text: 'bbbb',
    );
    final tableText = createFlowBox(
      style: _style(display: 'table'),
      text: 'cc',
    );
    final inlineText = createFlowBox(
      style: _style(display: 'inline'),
      text: 'dd',
    );
    final blockText = createFlowBox(style: _style(), text: 'eeee');
    final hiddenText = createFlowBox(
      style: _style(display: 'none'),
      text: 'ff',
    );

    final root = ColumnFlowBlock([
      absoluteText,
      floatText,
      tableText,
      inlineText,
      blockText,
      hiddenText,
    ]);
    root.measure(_wide);

    expect(absoluteText.branch, FlowBranch.absolute);
    expect(floatText.branch, FlowBranch.float);
    expect(tableText.branch, FlowBranch.table);
    expect(inlineText.branch, FlowBranch.inline);
    expect(blockText.branch, FlowBranch.block);
    expect(hiddenText.branch, FlowBranch.none);

    // 流内只有 table + inline + block：24 × 3。
    expect(root.size.height, closeTo(72, 0.01));
    expect(root.size.width, closeTo(64, 0.01));
    // 有浮动的树允许绕排收窄重测（P3-13，有界 ≤3 且确定性）；无浮动的
    // 树仍严格单次测量（block_flow_test 不变量）。
    expect(_walk(root).every((node) => node.layoutCount <= 3), isTrue);
  });

  test('绝对定位按容器宽测量但不推进容器高度', () {
    final absolute = createFlowBox(
      style: _style(position: 'absolute'),
      text: 'abcdefghijklmnop',
    );
    final root = ColumnFlowBlock([absolute]);
    root.measure(_wide);

    expect(absolute.size.width, closeTo(256, 0.01));
    expect(root.size.height, 0);
  });

  test('浮动宽度按内容收缩，不撑满容器', () {
    final float = createFlowBox(
      style: _style(floatValue: 'right'),
      text: 'ab',
    );
    float.measure(_wide);
    expect(float.size.width, closeTo(32, 0.01));
    expect(float.size.height, closeTo(24, 0.01));
  });

  test('行内容器宽高取子节点最大值', () {
    final inline = InlineFlowBlock([
      createFlowBox(style: _style(), text: 'aa'),
      createFlowBox(style: _style(), text: 'bbbb'),
    ]);
    final size = inline.measure(_wide);
    expect(size.width, closeTo(64, 0.01));
    expect(size.height, closeTo(24, 0.01));
  });

  test('display: none 的子节点不被测量', () {
    final hidden = createFlowBox(
      style: _style(display: 'none'),
      text: 'aa',
    );
    final root = ColumnFlowBlock([hidden]);
    root.measure(_wide);

    expect(hidden.size, Size.zero);
    expect(hidden.children, isEmpty);
    expect(root.size.height, 0);
  });

  test('表格在流内参与高度', () {
    final table = createFlowBox(
      style: _style(display: 'table'),
      text: 'aa',
    );
    final root = ColumnFlowBlock([table]);
    final size = root.measure(_wide);
    expect(size.height, closeTo(24, 0.01));
    expect(table.isOutOfFlow, isFalse);
  });

  test('浮动与绝对定位标记为脱离流', () {
    final float = createFlowBox(
      style: _style(floatValue: 'left'),
      text: 'a',
    );
    final absolute = createFlowBox(
      style: _style(position: 'absolute'),
      text: 'a',
    );
    final block = createFlowBox(style: _style(), text: 'a');

    expect(float.isOutOfFlow, isTrue);
    expect(absolute.isOutOfFlow, isTrue);
    expect(block.isOutOfFlow, isFalse);
  });
}
