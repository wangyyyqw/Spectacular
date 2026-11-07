import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/layout/text_edges.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';

final _style = ComputedStyle({
  'font-family': 'Ahem',
  'font-size': '20px',
  'line-height': '2',
});

PageBlock _block(
  String text, {
  ComputedStyle? style,
  double before = 0,
  double after = 0,
}) => PageBlock(
  layout: TextLayoutEngine.layout(
    text: text,
    style: style ?? _style,
    maxWidth: 200,
  ),
  style: style ?? _style,
  spaceBefore: before,
  spaceAfter: after,
);

ChapterPagination _paginate(
  List<PageBlock> blocks, {
  double height = 100,
  bool trim = true,
}) => Paginator(
  pageHeight: height,
  tolerance: 0,
  trimTextEdges: trim,
).measureChapter(blocks: blocks);

Future<Uint8List> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 140),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 140);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _MeasuredEdgesBlock extends PageBlock {
  _MeasuredEdgesBlock(String text)
    : super(layout: _block(text).layout, style: _style);

  final measuredLines = <int>{};

  @override
  PageTextEdges textEdgesAt(int lineIndex) {
    measuredLines.add(lineIndex);
    return super.textEdgesAt(lineIndex);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('已能容纳的行不提前测量页尾，真正边界仍保留精确裁边', () {
    final block = _MeasuredEdgesBlock(List.filled(12, 'abc').join('\n'));
    final pages = _paginate([block], height: 140).pages;
    expect(pages, hasLength(3));
    expect(pages.map((page) => page.slices.single.endLine), [4, 8, 12]);
    expect(pages.map((page) => page.usedHeight), everyElement(140));
    expect(block.measuredLines, isNot(contains(1)));
    expect(block.measuredLines, isNot(contains(2)));
    expect(block.measuredLines, containsAll([0, 3, 4, 7, 8, 11]));
  });

  test('NaN 盒尾保留原比较行为，不以否定容纳判断额外收页', () {
    final first = _block('abc');
    final second = PageBlock(
      layout: first.layout,
      style: _style,
      declaredContentHeight: double.nan,
    );
    final pages = Paginator(pageHeight: 100)
        .measureChapter(blocks: [first, second])
        .pages;
    expect(pages, hasLength(1));
    expect(pages.single.slices, hasLength(2));
    expect(pages.single.usedHeight.isNaN, isTrue);
  });

  test('页首尾各回收十像素行高留白，页内基线距离不变', () {
    final block = _block('abc\ndef\nghi\njkl\nmno\npqr');
    final pagination = _paginate([block]);
    expect(pagination.pages.length, 2);
    for (final page in pagination.pages) {
      final slice = page.slices.single;
      expect(slice.endLine - slice.startLine, 3);
      expect(slice.leadingExtent, closeTo(-10, 0.01));
      expect(slice.trailingExtent, closeTo(-10, 0.01));
      expect(page.usedHeight, closeTo(100, 0.01));
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes[1].textTop! - boxes[0].textTop!, 40);
      expect(boxes[2].textTop! - boxes[1].textTop!, 40);
      expect(boxes.first.rect.top, closeTo(0, 0.01));
      expect(boxes.last.rect.bottom, closeTo(100, 0.01));
      expect(page.hitTest(const Offset(10, 1))?.lineIndex, slice.startLine);
      expect(page.hitTest(const Offset(10, 99))?.lineIndex, slice.endLine - 1);
    }
    expect(
      _paginate([block], trim: false).pages.length,
      3,
      reason: '默认 CSS 分页仍保留完整行盒',
    );
  });

  test('段前段后距离保留，中间块不回收行高留白', () {
    final blocks = [
      _block('abc', before: 7, after: 11),
      _block('def', before: 5, after: 9),
    ];
    final page = _paginate(blocks, height: 140).pages.single;
    expect(page.slices.first.leadingExtent, closeTo(-3, 0.01));
    expect(page.slices.first.trailingExtent, 0);
    expect(page.slices.last.leadingExtent, 11, reason: '相邻段距仍折叠');
    expect(page.slices.last.trailingExtent, closeTo(-1, 0.01));
    expect(page.usedHeight, closeTo(87, 0.01));
    expect(TextHitTester.lineBoxes(page).first.rect.top, closeTo(7, 0.01));
  });

  test('只有一行时同时回收首尾，normal 不新增裁边', () {
    expect(
      _paginate([_block('abc')]).pages.single.usedHeight,
      closeTo(20, 0.01),
    );
    final normal = _block(
      'abc',
      style: ComputedStyle({
        'font-family': 'Ahem',
        'font-size': '20px',
        'line-height': 'normal',
      }),
    );
    final page = _paginate([normal]).pages.single;
    expect(page.slices.single.leadingExtent, closeTo(0, 0.01));
    expect(page.slices.single.trailingExtent, closeTo(0, 0.01));
  });

  test('混合字号末行按自身字体盒计算，而不是固定字号比例', () {
    final small = ComputedStyle({'font-size': '0.5em'}, parent: _style);
    final block = PageBlock(
      layout: TextLayoutEngine.layout(
        text: 'abc\ndef',
        style: _style,
        maxWidth: 200,
        runs: [StyledRun(start: 4, end: 7, style: small)],
      ),
      style: _style,
    );
    final page = _paginate([block]).pages.single;
    final last = block.layout.lines.last;
    final edges = block.textEdgesAt(1);
    expect(page.slices.single.trailingExtent, -edges.bottom);
    expect(
      page.usedHeight,
      closeTo(block.height - block.textEdgesAt(0).top - edges.bottom, 0.01),
    );
    expect(edges.top + edges.bottom, closeTo(last.height - 10, 0.01));
  });

  test('背景、边框、阴影、图片和上下标不回收边界', () {
    for (final css in [
      {'background-color': '#eeeeee'},
      {'border': '1px solid black'},
      {'text-shadow': '1px 1px black'},
      {'padding': '2px'},
      {'height': '40px'},
    ]) {
      final decorated = _block(
        'abc',
        style: ComputedStyle(css, parent: _style),
      );
      expect(decorated.textEdgesAt(0).top, 0);
      expect(decorated.textEdgesAt(0).bottom, 0);
    }
    final normal = _block('abc');
    final image = PageBlock(
      layout: normal.layout,
      style: _style,
      inlineImages: [const InlineImageSpec(offset: 0, url: 'image.png')],
    );
    expect(image.textEdgesAt(0).top, 0);
    final shifted = PageBlock(
      layout: TextLayoutEngine.layout(
        text: 'abc',
        style: _style,
        maxWidth: 200,
        runs: [StyledRun(start: 0, end: 1, style: _style, baselineShift: -5)],
      ),
      style: _style,
    );
    expect(shifted.textEdgesAt(0).top, 0);
  });

  test('页索引往返重放裁边几何，与首次分页完全一致', () {
    final blocks = [_block('abc\ndef\nghi\njkl'), _block('mno\npqr')];
    final original = _paginate(blocks);
    final index = PageIndex.decode(PageIndex.from(original, blocks).encode())!;
    final replayed = PageIndex.apply(
      index,
      blocks,
      spineIndex: 0,
      trimTextEdges: true,
    )!;
    expect(replayed.length, original.pages.length);
    for (var i = 0; i < replayed.length; i++) {
      expect(
        replayed[i].usedHeight,
        closeTo(original.pages[i].usedHeight, 0.01),
      );
      final actual = TextHitTester.lineBoxes(replayed[i]);
      final expected = TextHitTester.lineBoxes(original.pages[i]);
      expect(actual.map((box) => box.rect), expected.map((box) => box.rect));
    }
    expect(
      PageIndex.apply(index, blocks, spineIndex: 0),
      isNull,
      reason: '裁边模式不匹配不能沿用旧几何',
    );
  });

  test('绘制像素与关闭首尾行高的整段参考一致，选区光标同步', () async {
    final page = _paginate([_block('abc\ndef\nghi')]).pages.single;
    final reference = TextPainter(
      text: TextSpan(
        text: 'abc\ndef\nghi',
        style: TextLayoutEngine.textStyleFor(_style),
      ),
      textDirection: TextDirection.ltr,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout(maxWidth: 200);
    addTearDown(reference.dispose);
    final actual = await _pixels(
      (canvas) =>
          PagePainter().paint(canvas, page, pageSize: const Size(200, 140)),
    );
    final expected = await _pixels(
      (canvas) => reference.paint(canvas, Offset.zero),
    );
    expect(actual, orderedEquals(expected));
    for (final box in TextHitTester.lineBoxes(page)) {
      final rect = TextHitTester.selectionRects(
        box,
        0,
        3,
      ).single.shift(box.rect.topLeft);
      final target = reference
          .getBoxesForSelection(
            TextSelection(
              baseOffset: box.blockTextOffset,
              extentOffset: box.blockTextOffset + 3,
            ),
          )
          .single
          .toRect();
      expect(rect.top, closeTo(target.top, 0.01));
      expect(rect.bottom, closeTo(target.bottom, 0.01));
      final caret =
          TextHitTester.caretOffset(box, const TextPosition(offset: 0)) +
          box.rect.topLeft;
      final referenceCaret = reference.getOffsetForCaret(
        TextPosition(offset: box.blockTextOffset),
        Rect.zero,
      );
      expect(caret.dx, closeTo(referenceCaret.dx, 0.01));
      expect(box.rect.top, greaterThanOrEqualTo(0));
      expect(box.rect.bottom, lessThanOrEqualTo(page.usedHeight));
    }
  });

  test('异步阅读分页使用相同边界', () async {
    final blocks = [_block('abc\ndef\nghi\njkl')];
    final expected = _paginate(blocks).pages;
    final actual = await Paginator(
      pageHeight: 100,
      tolerance: 0,
      trimTextEdges: true,
    ).paginate(blocks: blocks).toList();
    expect(
      actual.map((page) => page.usedHeight),
      expected.map((page) => page.usedHeight),
    );
    expect(
      actual.map((page) => page.slices.single.endLine),
      expected.map((page) => page.slices.single.endLine),
    );
  });
}
