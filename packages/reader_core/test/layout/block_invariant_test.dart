import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

const _eps = 0.01;

ComputedStyle _style({
  double fontSize = 16,
  double marginTop = 0,
  double marginBottom = 0,
  String? display,
  String? position,
  String? floatValue,
  String? textAlign,
}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'margin-top': '${marginTop}px',
  'margin-bottom': '${marginBottom}px',
  'display': ?display,
  'position': ?position,
  'float': ?floatValue,
  'text-align': ?textAlign,
});

const _words = <String>[
  '中文文本内容',
  'English words here',
  '混排中文 English',
  '长一点的中文句子用于换行测试。',
  'a',
];

/// 随机但可复现的块树（最多四层）。
BlockFlow _randomTree(
  Random random,
  int depth, {
  required bool negativeMargins,
}) {
  double margin() => negativeMargins
      ? (random.nextInt(25) - 8).toDouble()
      : random.nextInt(17).toDouble();
  final style = _style(
    fontSize: <double>[12, 16, 20, 24][random.nextInt(4)],
    marginTop: margin(),
    marginBottom: margin(),
    display: <String?>[null, null, 'inline', 'table'][random.nextInt(4)],
    position: random.nextInt(10) == 0 ? 'absolute' : null,
    floatValue: random.nextInt(10) == 0
        ? (random.nextBool() ? 'left' : 'right')
        : null,
    textAlign: random.nextBool() ? 'justify' : null,
  );
  if (depth == 0) {
    final word = _words[random.nextInt(_words.length)];
    final text = List<String>.filled(random.nextInt(3) + 1, word).join();
    return createFlowBox(style: style, text: text);
  }
  final childCount = random.nextInt(3) + 1;
  return createFlowBox(
    style: style,
    children: [
      for (var i = 0; i < childCount; i++)
        _randomTree(random, depth - 1, negativeMargins: negativeMargins),
    ],
  );
}

/// §60.10 的尺寸与包含关系不变量。
void _checkInvariants(BlockFlow node, {required bool monotonicTops}) {
  final constraints = node.constraints!;
  final size = node.size;

  expect(size.width.isFinite, isTrue, reason: '宽度必须有限');
  expect(size.height.isFinite, isTrue, reason: '高度必须有限');
  expect(size.width, greaterThanOrEqualTo(0), reason: '宽度非负');
  expect(size.height, greaterThanOrEqualTo(0), reason: '高度非负');
  expect(
    size.width,
    lessThanOrEqualTo(constraints.maxWidth + _eps),
    reason: '宽度不越父约束',
  );

  if (node is TextFlowBlock) {
    final layout = node.layout;
    if (layout != null) {
      for (final line in layout.lines) {
        expect(line.offsetX, greaterThanOrEqualTo(-_eps), reason: '行偏移非负');
        expect(
          line.offsetX + line.width + line.justifyExtra,
          lessThanOrEqualTo(layout.maxWidth + _eps),
          reason: '行右缘不越行宽',
        );
      }
    }
  }

  if (node is ColumnFlowBlock) {
    final inFlow = node.children.where((child) => !child.isOutOfFlow).toList();
    expect(node.childTops.length, inFlow.length, reason: '顶位表覆盖全部流内子块');
    var previousTop = -_eps;
    for (var i = 0; i < inFlow.length; i++) {
      final child = inFlow[i];
      final top = node.childTops[i];
      expect(
        top + child.size.height,
        lessThanOrEqualTo(size.height + _eps),
        reason: '子块底边不越出父块内容高',
      );
      expect(
        child.size.width,
        lessThanOrEqualTo(size.width + _eps),
        reason: '子块宽度不越出父块宽',
      );
      if (monotonicTops) {
        expect(top, greaterThanOrEqualTo(-_eps), reason: '子块顶边不越出父块上边');
        expect(
          top,
          greaterThanOrEqualTo(previousTop),
          reason: '非负 margin 下顶位单调不减',
        );
      }
      previousTop = top;
    }
  }

  for (final child in node.children) {
    _checkInvariants(child, monotonicTops: monotonicTops);
  }
}

/// 分页结果的页高与切片不变量。
void _checkPagination(List<PageBlock> blocks, double pageHeight) {
  final pagination = Paginator(pageHeight: pageHeight)
      .measureChapter(blocks: blocks);
  final covered = <PageBlock, List<int>>{};

  for (final page in pagination.pages) {
    expect(page.slices, isNotEmpty, reason: '不产生零长度页');
    final available = pageHeight - page.topPadding;
    expect(
      page.usedHeight,
      lessThanOrEqualTo(available + 2.0 + _eps),
      reason: '页内容高不越界（2px 容差）',
    );
    var sliceSum = 0.0;
    for (final slice in page.slices) {
      expect(slice.startLine, lessThan(slice.endLine), reason: '切片至少一行');
      expect(
        slice.endLine,
        lessThanOrEqualTo(slice.block.layout.lineCount),
        reason: '切片行号不越块',
      );
      expect(slice.height, greaterThanOrEqualTo(0));
      expect(
        slice.height,
        lessThanOrEqualTo(slice.block.height + _eps),
        reason: 'drawFixHeight <= drawRealHeight',
      );
      // 切片高度等于可见行高之和。
      final lines = slice.lines.toList();
      final lineSum = lines.fold<double>(0, (sum, line) => sum + line.height);
      expect(slice.height, closeTo(lineSum, _eps), reason: '切片高度等于行高之和');
      sliceSum += slice.height;
      covered.putIfAbsent(slice.block, () => <int>[]).addAll(<int>[
        for (var i = slice.startLine; i < slice.endLine; i++) i,
      ]);
    }
    expect(sliceSum, closeTo(page.usedHeight, _eps), reason: '切片高度之和等于已用高度');
  }

  for (final block in blocks) {
    final lines = covered[block] ?? const <int>[];
    expect(lines.length, block.layout.lineCount, reason: '块的所有行恰好被切片覆盖一次');
    expect(lines, List<int>.generate(block.layout.lineCount, (i) => i));
  }
}

List<PageBlock> _chapterBlocks(Random random) {
  final blocks = <PageBlock>[];
  final count = random.nextInt(4) + 1;
  for (var i = 0; i < count; i++) {
    final style = _style(
      fontSize: <double>[16, 20][random.nextInt(2)],
      textAlign: random.nextBool() ? 'justify' : null,
    );
    blocks.add(
      PageBlock(
        layout: TextLayoutEngine.layout(
          text: List<String>.filled(
            random.nextInt(6) + 1,
            _words[random.nextInt(_words.length)],
          ).join(),
          style: style,
          maxWidth: 180,
        ),
        style: style,
      ),
    );
  }
  return blocks;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('随机块树满足尺寸与包含不变量', () {
    for (var seed = 1; seed <= 3; seed++) {
      final random = Random(seed);
      for (var i = 0; i < 8; i++) {
        final tree = _randomTree(
          random,
          random.nextInt(4),
          negativeMargins: false,
        );
        tree.measure(
          LayoutConstraints(maxWidth: (80 + random.nextInt(241)).toDouble()),
        );
        _checkInvariants(tree, monotonicTops: true);
      }
    }
  });

  test('负 margin 样本仍满足边界包含（允许子块上移重叠）', () {
    for (var seed = 1; seed <= 2; seed++) {
      final random = Random(seed);
      for (var i = 0; i < 6; i++) {
        final tree = _randomTree(
          random,
          random.nextInt(4),
          negativeMargins: true,
        );
        tree.measure(
          LayoutConstraints(maxWidth: (80 + random.nextInt(241)).toDouble()),
        );
        _checkInvariants(tree, monotonicTops: false);
      }
    }
  });

  test('空块与隐藏块尺寸为 0 且有限', () {
    final emptyText = createFlowBox(style: _style(), text: '');
    final emptyContainer = createFlowBox(style: _style(), children: []);
    final hidden = createFlowBox(
      style: _style(display: 'none'),
      text: '文本',
    );

    for (final block in [emptyText, emptyContainer, hidden]) {
      block.measure(const LayoutConstraints(maxWidth: 200));
      expect(block.size, Size.zero);
    }
  });

  test('页高不越界且切片覆盖完整', () {
    for (var seed = 1; seed <= 3; seed++) {
      final random = Random(seed);
      final blocks = _chapterBlocks(random);
      for (final pageHeight in <double>[48, 96, 200]) {
        _checkPagination(blocks, pageHeight);
      }
    }
  });

  test('跨页切片高度不超过块高度', () {
    final style = _style();
    final block = PageBlock(
      layout: TextLayoutEngine.layout(
        text: 'a\nb\nc\nd\ne',
        style: style,
        maxWidth: 180,
      ),
      style: style,
    );
    final pagination = Paginator(pageHeight: 48)
        .measureChapter(blocks: [block]);

    expect(pagination.pages.length, greaterThan(1));
    for (final page in pagination.pages) {
      for (final slice in page.slices) {
        expect(slice.height, lessThanOrEqualTo(block.height + _eps));
        expect(slice.continuesAfter, slice.endLine < 5);
        expect(slice.continuesBefore, slice.startLine > 0);
      }
    }
  });

  test('极端字号与超负 margin 下尺寸仍有限非负', () {
    final first = createFlowBox(style: _style(fontSize: 120), text: '中文');
    final second = createFlowBox(
      style: _style(fontSize: 12, marginTop: -400),
      text: 'a',
    );
    final root = ColumnFlowBlock([first, second]);
    root.measure(const LayoutConstraints(maxWidth: 300));

    // 超负 margin 会把后续块顶到父块上边之外，包含不变量按 CSS 语义不适用，
    // 这里只要求尺寸有限非负、宽度不越约束。
    expect(root.size.width.isFinite, isTrue);
    expect(root.size.height.isFinite, isTrue);
    expect(root.size.width, greaterThanOrEqualTo(0));
    expect(root.size.height, greaterThanOrEqualTo(0));
    expect(root.size.width, lessThanOrEqualTo(300 + _eps));
    expect(root.childTops[1], lessThan(0));
  });

  test('单行高于整页时强制放一行（显式例外）', () {
    final style = _style(fontSize: 200);
    final block = PageBlock(
      layout: TextLayoutEngine.layout(text: '大字', style: style, maxWidth: 600),
      style: style,
    );
    final pagination = Paginator(pageHeight: 10)
        .measureChapter(blocks: [block]);

    expect(pagination.pages, hasLength(1));
    final page = pagination.pages.single;
    expect(page.slices.single.height, greaterThan(10), reason: '强制整行放下');
    expect(page.slices.single.endLine, 1);
  });
}
