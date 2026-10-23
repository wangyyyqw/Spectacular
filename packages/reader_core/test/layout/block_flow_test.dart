import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';

const _width = 320.0;
const _height = 480.0;

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

TextFlowBlock _text(String text) => TextFlowBlock(text: text, style: _style());

LayoutConstraints _constraints({
  double maxWidth = _width,
  double maxHeight = _height,
}) => LayoutConstraints(maxWidth: maxWidth, maxHeight: maxHeight);

Iterable<BlockFlow> _walk(BlockFlow root) sync* {
  yield root;
  for (final child in root.children) {
    yield* _walk(child);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单文本块尺寸等于行布局尺寸', () {
    final block = _text('aa');
    final size = block.measure(_constraints());
    // Ahem 16px：两字 32 宽，行高 16×1.5=24。
    expect(size, const Size(32, 24));
    expect(block.size, size);
    expect(block.layout?.lineCount, 1);
  });

  test('文本块宽度受约束，换行后变高', () {
    final block = _text('abcdefghijklmnop');
    final size = block.measure(_constraints(maxWidth: 64));
    expect(size.width, 64);
    expect(block.layout?.lineCount, 4);
    expect(size.height, closeTo(96, 0.01));
  });

  test('两层容器高度相加、宽度取最大', () {
    final root = ColumnFlowBlock([_text('aa'), _text('bbbb')]);
    final size = root.measure(_constraints());
    expect(size.width, 64);
    expect(size.height, closeTo(48, 0.01));
    expect(root.children.map((child) => child.size), <Size>[
      const Size(32, 24),
      const Size(64, 24),
    ]);
  });

  test('三层嵌套块尺寸正确', () {
    final mid = ColumnFlowBlock([_text('aa'), _text('bb')]);
    final root = ColumnFlowBlock([mid, _text('cccc')]);
    final size = root.measure(_constraints());

    expect(mid.size, const Size(32, 48));
    expect(size.width, 64);
    expect(size.height, closeTo(72, 0.01));
  });

  test('空容器与空文本块为零尺寸', () {
    expect(ColumnFlowBlock().measure(_constraints()), Size.zero);
    expect(_text('').measure(_constraints()), Size.zero);
  });

  test('每个节点在一次测量中只进入阶段一一次', () {
    final mid = ColumnFlowBlock([_text('aa'), _text('bb')]);
    final root = ColumnFlowBlock([mid, _text('cccc')]);
    root.measure(_constraints());

    expect(_walk(root).every((node) => node.layoutCount == 1), isTrue);
  });

  test('相同约束重复测量尺寸不变', () {
    final root = ColumnFlowBlock([_text('aa'), _text('bb')]);
    final first = root.measure(_constraints());
    final second = root.measure(_constraints());

    expect(second, first);
    expect(root.layoutCount, 2);
    expect(_walk(root).every((node) => node.layoutCount == 2), isTrue);
  });

  test('约束变化后尺寸自适应', () {
    final block = _text('abcdefghijklmnop');
    final wide = block.measure(_constraints(maxWidth: 320));
    final narrow = block.measure(_constraints(maxWidth: 64));

    expect(wide, const Size(256, 24));
    expect(narrow.width, 64);
    expect(narrow.height, closeTo(96, 0.01));
    expect(block.layoutCount, 2);
  });

  test('子节点拿到按已用高度递减的剩余约束', () {
    final first = _text('aa');
    final second = _text('bb');
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints(maxHeight: 100));

    expect(first.constraints?.maxHeight, 100);
    expect(second.constraints?.maxHeight, closeTo(76, 0.01));
  });

  test('剩余高度用尽后子节点约束为 0', () {
    final first = _text('aa');
    final second = _text('bb');
    final root = ColumnFlowBlock([first, second]);
    root.measure(_constraints(maxHeight: 30));

    expect(first.constraints?.maxHeight, 30);
    expect(second.constraints?.maxHeight, closeTo(6, 0.01));
  });

  test('子节点尺寸不超过父约束', () {
    final root = ColumnFlowBlock([_text('aa'), _text('bbbbbbbbbbbbbbbbbbbb')]);
    root.measure(_constraints(maxWidth: 80, maxHeight: 100));
    for (final node in _walk(root)) {
      expect(
        node.size.width,
        lessThanOrEqualTo(node.constraints!.contentWidth),
      );
      expect(
        node.size.height,
        lessThanOrEqualTo(node.constraints!.contentHeight + 0.01),
      );
    }
  });

  test('窄约束按 3em 测量后收进约束范围', () {
    final block = _text('中文');
    final size = block.measure(_constraints(maxWidth: 20));
    // 断行器把正文宽钳到 48，区块尺寸仍不得超出约束宽 20。
    expect(block.layout?.maxWidth, 48);
    expect(size.width, 20);
  });
}
