import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/cjk_justify.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';

const _family = 'ProseSourceHan';

ComputedStyle _style([Map<String, String> extra = const {}]) => ComputedStyle({
  'font-family': _family,
  'font-size': '20px',
  'line-height': '1.6',
  'text-align': 'justify',
  'text-spacing-trim': 'trim-both',
  ...extra,
});

TextPainter _paintLine(
  TextLayoutResult layout,
  LineBox line,
  ComputedStyle style,
) => TextPainter(
  text: buildLineSpan(
    layout: layout,
    line: line,
    baseStyle: TextLayoutEngine.textStyleFor(style),
  ),
  textDirection: TextDirection.ltr,
)..layout();

void _expectWidths(TextLayoutResult layout, ComputedStyle style) {
  for (final line in layout.lines) {
    final painter = _paintLine(layout, line, style);
    final boxes = line.inlineBoxes.fold(
      0.0,
      (sum, box) => sum + box.spec.outerWidth,
    );
    expect(
      painter.width + boxes + line.ellipsisWidth + line.hyphenWidth,
      closeTo(line.advanceWidth, .5),
      reason: layout.text.substring(line.start, line.end),
    );
    if (line.justifyExtra > 0) {
      expect(line.advanceWidth + line.indent, closeTo(layout.maxWidth, .5));
    }
    painter.dispose();
  }
}

Future<void> _loadFonts() async {
  final loader = FontLoader(_family);
  for (final weight in ['Regular', 'Bold']) {
    final bytes = await File(
      '../../apps/reader_mobile/assets/fonts/SourceHanSerifCN-$weight.otf',
    ).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  test('按原始宽度压缩：行内 20%，相邻及行首行尾 40%，不叠加', () {
    final style = _style({'text-spacing-trim': 'trim-all'});
    for (final (text, reductions, width) in [
      ('，甲，乙，', {0: 8, 2: 4, 4: 8}, 80),
      ('甲，，乙', {1: 8, 2: 8}, 64),
      ('甲，，，乙', {1: 8, 2: 8, 3: 8}, 76),
      ('，，甲', {0: 8, 1: 8}, 44),
      ('甲！乙？丙“丁”戊‘己’', {1: 4, 3: 4, 5: 4, 7: 4, 9: 4, 11: 8}, 212),
      ('，', {0: 8}, 12),
    ]) {
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: 400,
      );
      final spacing = layout.lines.single.spacing!;
      expect(spacing.glyphs.keys, reductions.keys);
      for (final entry in reductions.entries) {
        expect(spacing.glyphs[entry.key]!.halfWidth, isTrue);
        expect(spacing.glyphs[entry.key]!.reduction, closeTo(entry.value, .05));
      }
      expect(layout.lines.single.width, closeTo(width, .05));
      expect(layout.text, text);
      _expectWidths(layout, style);
    }
  });

  test('软换行按实际行尾压缩 40%，问叹号的新增收缩参与断行', () {
    final style = _style({
      'text-spacing-trim': 'trim-all',
      'text-align': 'left',
    });
    final layout = TextLayoutEngine.layout(
      text: '甲乙丙！丁戊己？庚辛壬。',
      style: style,
      maxWidth: 72,
    );
    expect(layout.lines.map((line) => line.end), [4, 8, 12]);
    for (final line in layout.lines) {
      expect(line.spacing!.glyphs[3]!.reduction, closeTo(8, .05));
      expect(line.width, closeTo(72, .05));
      expect(line.spacing!.endTrim, closeTo(4, .05));
    }
    _expectWidths(layout, style);
  });

  test('统一压缩参与断行，非末行不重新拉宽标点，绘制和命中同步', () {
    final style = _style({'text-spacing-trim': 'trim-all'});
    final layout = TextLayoutEngine.layout(
      text: '甲乙，丙丁，戊己。庚辛，壬癸。',
      style: style,
      maxWidth: 115,
    );
    expect(layout.lines.first.end, 6);
    expect(layout.lines.first.width, closeTo(108, .05));
    expect(layout.lines.first.justifyExtra, greaterThan(0));
    _expectWidths(layout, style);
    final pages = Paginator(pageHeight: 64)
        .measureChapter(
          blocks: [PageBlock(layout: layout, style: style)],
        )
        .pages;
    for (final page in pages) {
      _expectPunctuationHits(page, style);
    }
  });

  test('统一压缩逐 run 尊重字体特性、字号及注音边界', () {
    final style = _style({'text-spacing-trim': 'trim-all'});
    final large = ComputedStyle({'font-size': '30px'}, parent: style);
    final disabled = ComputedStyle({
      'font-feature-settings': '"halt" 0',
    }, parent: style);
    final layout = TextLayoutEngine.layout(
      text: '甲，乙，丙，丁，戊。',
      style: style,
      maxWidth: 400,
      runs: [
        StyledRun(start: 1, end: 2, style: large),
        StyledRun(start: 3, end: 4, style: disabled),
      ],
      rubies: const [RubyAnnotation(start: 5, end: 6, text: '注')],
    );
    final glyphs = layout.lines.single.spacing!.glyphs;
    expect(glyphs[1]!.reduction, closeTo(6, .05));
    expect(glyphs.containsKey(3), isFalse);
    expect(glyphs.containsKey(5), isFalse);
    expect(glyphs[7]!.reduction, closeTo(4, .05));
    _expectWidths(layout, style);
  });

  test('统一压缩在不支持 halt 的字体下保留原宽，不用负字距碰撞字形', () {
    final style = _style({
      'font-family': 'Ahem',
      'text-spacing-trim': 'trim-all',
    });
    final layout = TextLayoutEngine.layout(
      text: '甲，，乙！',
      style: style,
      maxWidth: 400,
    );
    expect(layout.lines.single.spacing!.glyphs, isEmpty);
    expect(layout.lines.single.width, closeTo(100, .05));
    _expectWidths(layout, style);
  });

  test('真实思源宋体使用 halt，行边和相邻组合不改变原文', () {
    const text = '（《中文》）。';
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 400,
    );
    final spacing = layout.lines.single.spacing!;
    expect(spacing.startTrim, closeTo(10, .05));
    expect(spacing.endTrim, closeTo(10, .05));
    expect(spacing.glyphs.values.every((glyph) => glyph.halfWidth), isTrue);
    expect(spacing.lockedGaps, containsAll([0, 4, 5]));
    expect(layout.text, text);
    _expectWidths(layout, style);
    expect(() => spacing.glyphs.clear(), throwsUnsupportedError);
  });

  test('先用行尾挤压断行，再两端对齐，不借用下一行的标点', () {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '甲乙丙，丁戊己。',
      style: style,
      maxWidth: 70,
    );
    expect(layout.lines.first.end, 4);
    expect(layout.lines.first.width, closeTo(70, .05));
    expect(layout.lines.last.justifyExtra, 0);
    _expectWidths(layout, style);
  });

  test('开标点挤压影响行首占宽，space-first 保留段落第一行', () {
    const text = '（甲乙丙丁戊己庚';
    final both = _style();
    final first = _style({'text-spacing-trim': 'space-first'});
    final trimmed = TextLayoutEngine.layout(
      text: text,
      style: both,
      maxWidth: 70,
    );
    final preserved = TextLayoutEngine.layout(
      text: text,
      style: first,
      maxWidth: 70,
    );
    expect(trimmed.lines.first.end, 4);
    expect(preserved.lines.first.end, 3);
    expect(preserved.lines.first.spacing!.startTrim, 0);
    _expectWidths(trimmed, both);
    _expectWidths(preserved, first);
  });

  test('混合字号、粗体、颜色逐标点测量，不整段关闭挤压', () {
    const text = '甲》，「乙。';
    final style = _style();
    final large = ComputedStyle({
      'font-size': '30px',
      'font-weight': 'bold',
      'color': 'red',
    }, parent: style);
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 400,
      runs: [StyledRun(start: 1, end: 3, style: large)],
    );
    final spacing = layout.lines.single.spacing!;
    expect(spacing.glyphs[1]!.reduction, closeTo(15, .05));
    expect(spacing.glyphs[3]!.reduction, closeTo(10, .05));
    expect(layout.runs.single.style.color, const Color(0xFFFF0000));
    _expectWidths(layout, style);
  });

  test('关闭挤压和显式 halt 均不被重复覆盖', () {
    for (final setting in ['space-all', 'trim-both']) {
      final style = _style({
        'text-spacing-trim': setting,
        'font-feature-settings': '"halt" 1',
      });
      final layout = TextLayoutEngine.layout(
        text: '（甲）。，',
        style: style,
        maxWidth: 400,
      );
      expect(layout.lines.single.spacing!.glyphs, isEmpty);
      _expectWidths(layout, style);
    }
    final style = _style({'text-spacing-trim': 'space-all'});
    final layout = TextLayoutEngine.layout(
      text: '（甲）。，',
      style: style,
      maxWidth: 400,
    );
    expect(layout.lines.single.width, closeTo(100, .05));
  });

  test('闭开组合尊重目标 run 显式 halt，不转而二次挤压另一侧', () {
    final style = _style();
    for (final value in ['0', '1']) {
      final opening = ComputedStyle({
        'font-feature-settings': '"halt" $value',
      }, parent: style);
      final layout = TextLayoutEngine.layout(
        text: '甲」，「乙',
        style: style,
        maxWidth: 400,
        runs: [StyledRun(start: 3, end: 4, style: opening)],
      );
      expect(layout.lines.single.spacing!.glyphs.keys, [1]);
      _expectWidths(layout, style);
    }
  });

  test('无 halt 字体只保留旧的闭标点相邻兼容，不新增行边或开开挤压', () {
    final style = _style({'font-family': 'Ahem'});
    final layout = TextLayoutEngine.layout(
      text: '（《甲》）。',
      style: style,
      maxWidth: 400,
    );
    final spacing = layout.lines.single.spacing!;
    expect((spacing.startTrim, spacing.endTrim), (0.0, 0.0));
    expect(spacing.glyphs.keys, [3, 4]);
    expect(layout.lines.single.width, 100);
    _expectWidths(layout, style);
  });

  test('已压紧的组合不再被两端对齐拉开', () {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '甲乙》，「丙丁戊己庚辛壬癸',
      style: style,
      maxWidth: 133,
    );
    expect(layout.lines.first.justifyExtra, greaterThan(0));
    for (final line in layout.lines) {
      expect(
        line.spacing!.justifyGaps.toSet().intersection(
          line.spacing!.lockedGaps,
        ),
        isEmpty,
      );
    }
    _expectWidths(layout, style);
  });

  test('缩进、窄屏、末行、硬换行和西文词间对齐共用几何', () {
    for (final text in [
      '甲乙丙丁戊己庚辛壬癸。甲乙丙丁。',
      '中文排版 EPUB reader 混排测试。更多正文。',
      'one two three four five six',
      '甲乙\n丙丁戊己庚辛壬癸。',
      'English',
    ]) {
      final style = _style({'text-indent': '1em'});
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: 123,
      );
      for (final line in layout.lines.where(
        (line) => line.isLastLine || line.isHardBreak,
      )) {
        expect(line.justifyExtra, 0);
      }
      _expectWidths(layout, style);
    }
  });

  test('字簇间分配不拆组合字符、emoji 或英文词内', () {
    const text = '甲a\u0301👩‍👩‍👦乙英文 EPUB';
    final boundaries = <int>{};
    var offset = 0;
    for (final cluster in text.characters) {
      boundaries.add(offset);
      offset += cluster.length;
    }
    expect(cjkJustifyGapOffsets(text).every(boundaries.contains), isTrue);
    expect(cjkJustifyGapOffsets('中文 EPUB 混排'), isNot(contains(4)));
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '$text$text',
      style: style,
      maxWidth: 233,
    );
    _expectWidths(layout, style);
  });

  test('不跨注音和原子盒挤压，盒前后命中仍为原文坐标', () {
    const text = '甲》，「乙丙丁戊己庚';
    final style = _style();
    final ruby = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 133,
      rubies: const [RubyAnnotation(start: 2, end: 4, text: '注音')],
    );
    expect(ruby.lines.first.spacing!.glyphs.containsKey(1), isFalse);
    expect(
      ruby.lines.first.spacing!.justifyGaps,
      isNot(anyOf(contains(1), contains(2), contains(3))),
    );
    final boxed = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 233,
      inlineBoxes: const [InlineBoxSpec(offset: 2, width: 25, height: 25)],
    );
    expect(boxed.lines.first.spacing!.glyphs.containsKey(1), isFalse);
    _expectWidths(ruby, style);
    _expectWidths(boxed, style);
  });

  test('标点附近光标、命中、选区消费同一字形位置', () {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '（甲乙》，「丙丁戊己庚辛',
      style: style,
      maxWidth: 153,
    );
    final page = Paginator(pageHeight: 400)
        .measureChapter(
          blocks: [PageBlock(layout: layout, style: style)],
        )
        .pages
        .single;
    final box = TextHitTester.lineBoxes(page).first;
    final line = layout.lines.first;
    final painter = _paintLine(layout, line, style);
    for (var i = 0; i < box.text.length; i++) {
      final position = TextPosition(offset: i);
      expect(
        TextHitTester.caretOffset(box, position).dx,
        closeTo(painter.getOffsetForCaret(position, Rect.zero).dx, .01),
      );
      final selected = TextHitTester.selectionRects(box, i, i + 1).single;
      final painted = painter
          .getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + 1),
          )
          .single;
      expect(selected.left, closeTo(painted.left, .01));
      expect(selected.right, closeTo(painted.right, .01));
      final hit = TextHitTester.hitTest(
        page,
        Offset(box.rect.left + painted.left + .1, box.rect.center.dy),
      )!;
      expect(hit.charOffset, i);
    }
    painter.dispose();
  });

  test('折叠行尾空格保留原文偏移，跨页光标锚到同一可见边缘', () {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '正文 word ' * 30,
      style: style,
      maxWidth: 153,
    );
    final pages = Paginator(pageHeight: 96)
        .measureChapter(
          blocks: [PageBlock(layout: layout, style: style)],
        )
        .pages;
    var checked = 0;
    for (final page in pages) {
      for (final box in TextHitTester.lineBoxes(page)) {
        final line = layout.lines[box.lineIndex];
        final trailing = line.spacing!.trailingSpaceStart;
        if (trailing == null) continue;
        for (var offset = trailing; offset <= box.text.length; offset++) {
          final caret = TextHitTester.caretOffset(
            box,
            TextPosition(offset: offset),
          );
          expect(caret.dx, closeTo(line.advanceWidth, .5));
          expect(caret.dy.isFinite, isTrue);
        }
        checked++;
      }
    }
    expect(checked, greaterThan(1));
  });

  test('上下标边界不挤压，但同一上下标区间内部仍可挤压', () {
    final style = _style();
    final small = ComputedStyle({'font-size': '12px'}, parent: style);
    final layout = TextLayoutEngine.layout(
      text: '甲》，。「乙丙丁戊己',
      style: style,
      maxWidth: 137,
      runs: [StyledRun(start: 2, end: 4, style: small, baselineShift: -6)],
    );
    expect(layout.lines.first.spacing!.glyphs.containsKey(1), isFalse);
    expect(layout.lines.first.spacing!.glyphs[2]!.reduction, closeTo(6, .05));
    _expectWidths(layout, style);
  });

  test('连续标点、窄行及硬换行不跨行借宽，字簇边界始终完整', () {
    final style = _style({'text-align': 'left'});
    for (final text in [
      '甲乙》，「（丙丁）》。戊己庚辛',
      '\n（甲乙）\n\n「丙丁」。\n戊己',
      '（甲a\u0301乙👩‍👩‍👦丙）。，丁戊',
    ]) {
      final boundaries = <int>{0};
      for (final cluster in text.characters) {
        boundaries.add(boundaries.last + cluster.length);
      }
      for (final width in [43.0, 70.0, 93.0, 133.0]) {
        final layout = TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: width,
        );
        for (final line in layout.lines) {
          expect(boundaries, contains(line.start));
          expect(boundaries, contains(line.end));
          if (line.end < text.length) {
            expect(
              line.spacing!.glyphs.values.every(
                (glyph) => glyph.offset + glyph.length <= line.end - line.start,
              ),
              isTrue,
            );
          }
        }
        _expectWidths(layout, style);
      }
    }
  });

  test('非目标标点与半角符号不新增挤压，组合标点不拆字簇', () {
    for (final text in ['！？……——!?()', '（\u0301甲）\u0301。\u0301']) {
      final style = _style();
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: 400,
      );
      expect(layout.lines.single.spacing!.glyphs, isEmpty);
      _expectWidths(layout, style);
    }
    expect(cjkJustifyGapOffsets('甲\u302a乙'), isNot(contains(1)));
    expect(cjkJustifyGapOffsets('甲ｶﾞ乙'), isNot(contains(1)));
  });

  test('断词插入测量断点与省略号截断后仍使用原文字簇坐标', () {
    const text = '甲乙》，「English demonstration continuation」丙丁戊';
    for (final extra in [
      {'word-break': 'break-all'},
      {'hyphens': 'auto'},
      {
        'white-space': 'nowrap',
        'overflow': 'hidden',
        'text-overflow': 'ellipsis',
      },
    ]) {
      final style = _style(extra);
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: 143,
        runs: [
          StyledRun(
            start: 5,
            end: 40,
            style: ComputedStyle({'color': 'red'}, parent: style),
          ),
        ],
      );
      expect(layout.text, text);
      _expectWidths(layout, style);
    }
  });

  test('长段局部探测与短段断行前缀一致，不改变禁则断点', () {
    const unit = '（甲乙），「丙丁》」。中西文 EPUB 混排；';
    final style = _style();
    final short = TextLayoutEngine.layout(
      text: unit * 8,
      style: style,
      maxWidth: 153,
    );
    final long = TextLayoutEngine.layout(
      text: unit * 80,
      style: style,
      maxWidth: 153,
    );
    for (var i = 0; i < short.lines.length - 2; i++) {
      expect(long.lines[i].end, short.lines[i].end);
      expect(long.lines[i].width, closeTo(short.lines[i].width, .01));
    }
    _expectWidths(long, style);
  });

  test('复用单行探测时不同候选宽度不泄漏，保留原有合法断点', () {
    const text = '（甲乙丙，丁）。「戊己庚」，（辛壬癸）这是窄行正文；英文 reader 保持完整。';
    final expected = {
      61.0: [3, 5, 8, 11, 14, 17, 20, 23, 26, 29, 34, 38, 41],
      83.0: [5, 10, 14, 19, 23, 27, 29, 36, 39, 41],
      101.0: [5, 11, 17, 22, 27, 36, 41],
      149.0: [8, 16, 23, 29, 39, 41],
    };
    final style = _style();
    for (final entry in expected.entries) {
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: entry.key,
      );
      expect(layout.lines.map((line) => line.end), entry.value);
      expect(layout.text, text);
      _expectWidths(layout, style);
    }
  });

  test('缩进仅探测首行时保留长段尾部、硬换行与间距', () {
    const unit = '（甲乙），「丙丁》」。中西文 EPUB 混排；';
    for (final indent in ['40px', '-20px']) {
      final style = _style({'text-indent': indent});
      final short = TextLayoutEngine.layout(
        text: '$unit\n${unit * 4}',
        style: style,
        maxWidth: 153,
      );
      final long = TextLayoutEngine.layout(
        text: '$unit\n${unit * 40}',
        style: style,
        maxWidth: 153,
      );
      for (var i = 0; i < short.lines.length - 2; i++) {
        expect(long.lines[i].end, short.lines[i].end);
        expect(long.lines[i].width, closeTo(short.lines[i].width, .01));
      }
      expect(long.lines.last.end, long.text.length);
      expect(long.lines.where((line) => line.isHardBreak), hasLength(1));
      _expectWidths(long, style);
    }
  });

  test('混合字号悬挂只使用已挤压后的句读宽，缩放不重复放大对齐余量', () {
    final style = _style({'hanging-punctuation': 'allow-end'});
    final large = ComputedStyle({'font-size': '30px'}, parent: style);
    final hanging = TextLayoutEngine.layout(
      text: '甲乙丙，丁戊己',
      style: style,
      maxWidth: 80,
      runs: [StyledRun(start: 3, end: 4, style: large)],
    );
    final line = hanging.lines.first;
    expect(line.end, 4);
    expect(line.advanceWidth, closeTo(95, .05));
    final painted = _paintLine(hanging, line, style);
    expect(painted.width, closeTo(line.advanceWidth, .5));
    painted.dispose();
    final normal = _style();
    final scaled = TextLayoutEngine.layout(
      text: '甲乙丙，丁戊己庚辛壬癸',
      style: normal,
      maxWidth: 153,
      textScaleFactor: 1.3,
    );
    for (final line in scaled.lines) {
      final painter = TextPainter(
        text: buildLineSpan(
          layout: scaled,
          line: line,
          baseStyle: TextLayoutEngine.textStyleFor(normal),
        ),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(1.3),
      )..layout();
      expect(painter.width, closeTo(line.advanceWidth, .5));
      painter.dispose();
    }
  });

  test('多列复制和跨页切片保留不可变间距，文本拼接不变', () {
    final style = _style({'column-count': '2', 'column-gap': '20px'});
    final text = '（甲乙），「丙丁》」。中西文 EPUB 混排；' * 20;
    final original = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 143,
    );
    final blockLayout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 306,
    );
    final pages = Paginator(pageHeight: 160)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: blockLayout,
              style: style,
              containingWidth: 306,
            ),
          ],
        )
        .pages;
    final copied = <LineBox>[];
    final content = StringBuffer();
    for (final page in pages) {
      for (final slice in page.slices) {
        final layout = slice.block.layout;
        _expectWidths(layout, style);
        for (final line in layout.lines.sublist(
          slice.startLine,
          slice.endLine,
        )) {
          copied.add(line);
          content.write(layout.text.substring(line.start, line.end));
        }
      }
    }
    expect(content.toString(), text);
    expect(copied.length, original.lines.length);
    for (var i = 0; i < copied.length; i++) {
      expect(
        copied[i].spacing!.fingerprint,
        original.lines[i].spacing!.fingerprint,
      );
    }
  });

  test('多列重排保留图片、原子盒和注音的挤压边界', () {
    final style = _style({'column-count': '2', 'column-gap': '20px'});
    final text = '甲》，\uFFFC「乙丙丁戊己庚辛壬癸' * 3;
    const boxes = [
      InlineBoxSpec(
        offset: 4,
        width: 25,
        height: 25,
        replacesPlaceholder: true,
      ),
      InlineBoxSpec(offset: 8, width: 22, height: 25),
    ];
    const rubies = [RubyAnnotation(start: 1, end: 4, text: '注音')];
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 306,
      inlineBoxes: boxes,
      rubies: rubies,
    );
    final page = Paginator(pageHeight: 1000)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 306,
              rubies: rubies,
            ),
          ],
        )
        .pages
        .single;
    final column = page.slices.first.block;
    expect(
      column.layout.lines.expand((line) => line.inlineBoxes),
      hasLength(2),
    );
    expect(column.rubies, hasLength(1));
    expect(column.layout.lines.first.spacing!.glyphs.containsKey(1), isFalse);
    for (final slice in page.slices) {
      _expectWidths(slice.block.layout, style);
    }
  });

  test('布局缓存区分挤压策略与注音边界，不因主题颜色变化重新排版', () {
    final cache = TextLayoutCache();
    final style = _style();
    const text = '甲》，「乙丙丁戊己庚';
    final plain = cache.layout(text: text, style: style, maxWidth: 153);
    final ruby = cache.layout(
      text: text,
      style: style,
      maxWidth: 153,
      rubies: const [RubyAnnotation(start: 2, end: 4, text: '注音')],
    );
    final off = cache.layout(
      text: text,
      maxWidth: 153,
      style: _style({'text-spacing-trim': 'space-all'}),
    );
    expect(identical(ruby, plain), isFalse);
    expect(identical(off, plain), isFalse);
    expect(ruby.lines.first.spacing!.glyphs.containsKey(1), isFalse);
    final recolored = cache.layout(
      text: text,
      maxWidth: 153,
      style: _style({'color': 'red'}),
    );
    expect(identical(recolored, plain), isTrue);
    expect(cache.hits, 1);
    expect(cache.misses, 3);
  });

  test('思源宋体 halt 只改变留白，真实标点墨迹尺寸不变', () async {
    for (final char in ['（', '）', '。', '，', '「', '」', '！', '？', '“', '”']) {
      final normal = await _inkBounds(char, false);
      final trimmed = await _inkBounds(char, true);
      expect(trimmed.width, normal.width, reason: char);
      expect(trimmed.height, normal.height, reason: char);
    }
  });

  test('20% 与 40% 压缩只补回留白，不缩放标点墨迹', () async {
    for (final char in ['，', '（', '）', '！', '？', '“', '”']) {
      final normal = await _inkBounds(char, false);
      for (final letterSpacing in [3.2, 9.6]) {
        final compressed = await _inkBounds(char, true, letterSpacing);
        expect(compressed.width, closeTo(normal.width, 1), reason: char);
        expect(compressed.height, closeTo(normal.height, 1), reason: char);
      }
    }
  });
}

void _expectPunctuationHits(PageContent page, ComputedStyle style) {
  for (final box in TextHitTester.lineBoxes(page)) {
    final layout = box.slice.block.layout;
    final line = layout.lines[box.lineIndex];
    final painter = _paintLine(layout, line, style);
    for (final glyph in line.spacing!.glyphs.values) {
      final rect = painter
          .getBoxesForSelection(
            TextSelection(
              baseOffset: glyph.offset,
              extentOffset: glyph.offset + 1,
            ),
          )
          .single;
      final hit = TextHitTester.hitTest(
        page,
        Offset(box.rect.left + rect.left + .1, box.rect.center.dy),
      );
      expect(hit?.charOffset, glyph.offset);
      final selected = TextHitTester.selectionRects(
        box,
        glyph.offset,
        glyph.offset + 1,
      ).single;
      expect(selected.width, closeTo(rect.right - rect.left, .01));
      expect(selected.width, closeTo(style.fontSize - glyph.reduction, .05));
    }
    expect(
      line.spacing!.justifyGaps.toSet().intersection(line.spacing!.lockedGaps),
      isEmpty,
    );
    painter.dispose();
  }
}

Future<Rect> _inkBounds(String char, bool halt, [double letterSpacing = 0]) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  final painter = TextPainter(
    text: TextSpan(
      text: char,
      style: TextStyle(
        fontFamily: _family,
        fontSize: 32,
        color: const Color(0xFF000000),
        letterSpacing: letterSpacing,
        fontFeatures: [if (halt) const FontFeature.enable('halt')],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, const Offset(40, 20));
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 160);
  final data = (await image.toByteData())!;
  var left = 200, top = 160, right = 0, bottom = 0;
  for (var y = 0; y < 160; y++) {
    for (var x = 0; x < 200; x++) {
      if (data.getUint8((y * 200 + x) * 4 + 3) == 0) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  image.dispose();
  picture.dispose();
  painter.dispose();
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right.toDouble(),
    bottom.toDouble(),
  );
}
