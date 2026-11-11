import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

Future<List<PageBlock>> _blocks(EpubChapterSource source) async =>
    (await source.loadChapter(0))
        .expand((page) => page.slices.map((slice) => slice.block))
        .toSet()
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('prose_flow_song')..addFont(
          rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
        ))
        .load();
  });

  test('普通 p 和叶子 div 默认两端对齐及统一压缩，默认不伪造作者来源', () async {
    final source = await openCssChapter(
      body:
          '<p>普通正文，<b>加粗文字</b>不会关闭段落排版。</p>'
          '<div>叶子正文，<span>行内文字</span>同样适用。</div>',
    );
    final blocks = await _blocks(source);
    expect(blocks, hasLength(2));
    for (final block in blocks) {
      expect(block.style!.textAlign, CssTextAlign.justify);
      expect(block.style!.textSpacingTrim, CssTextSpacingTrim.trimAll);
      expect(block.style!.declaredTextProperties, isEmpty);
      for (final run in block.layout.runs) {
        expect(run.style.textSpacingTrim, CssTextSpacingTrim.trimAll);
      }
    }
  });

  test('body 与 div 祖先的左中右对齐经盒属性传导仍受保护', () async {
    for (final (name, expected) in [
      ('left', CssTextAlign.left),
      ('center', CssTextAlign.center),
      ('right', CssTextAlign.right),
    ]) {
      final source = await openCssChapter(
        body: '<div class="outer"><div><p>嵌套正文，不能覆盖祖先对齐。</p></div></div>',
        css: 'body { text-align: $name; } .outer { padding: 4px; }',
      );
      final block = (await _blocks(source)).single;
      expect(block.style!.textAlign, expected);
      expect(block.style!.declaredTextProperties, contains('text-align'));
    }
    final source = await openCssChapter(
      body: '<div style="text-align:right"><p>容器作者对齐。</p></div>',
    );
    expect((await _blocks(source)).single.style!.textAlign, CssTextAlign.right);
  });

  test('正文默认逐字压缩孤立和连续标点，行内样式不改变规则', () async {
    final source = await openCssChapter(
      body: '<p>（甲）<span style="color:red">，</span>乙！丙“丁”戊？</p>',
      css: 'body { font-family:prose_flow_song; font-size:20px; }',
    );
    final block = (await _blocks(source)).single;
    final line = block.layout.lines.single;
    expect(line.spacing!.glyphs.keys, [0, 2, 3, 5, 7, 9, 11]);
    for (final glyph in line.spacing!.glyphs.values) {
      expect(glyph.halfWidth, isTrue);
      final reduction = [0, 2, 3, 11].contains(glyph.offset) ? 8 : 4;
      expect(glyph.reduction, closeTo(reduction, .05));
    }
    _expectFlowGeometry(
      TextHitTester.lineBoxes((await source.loadChapter(0)).single).single,
    );
  });

  test('作者 inherit、unset、initial 及显式关闭挤压保留来源', () async {
    for (final keyword in ['inherit', 'unset', 'initial']) {
      final source = await openCssChapter(
        body: '<p>作者明确指定默认值，不能误判为未声明。</p>',
        css: 'p { text-align: $keyword; text-spacing-trim: space-all; }',
      );
      final block = (await _blocks(source)).single;
      expect(block.style!.textAlign, isNot(CssTextAlign.justify));
      expect(block.style!.textSpacingTrim, CssTextSpacingTrim.normal);
      expect(
        block.style!.declaredTextProperties,
        containsAll(['text-align', 'text-spacing-trim']),
      );
      expect(
        block.layout.lines.every((line) => line.spacing!.glyphs.isEmpty),
        isTrue,
      );
    }
    final source = await openCssChapter(
      body: '<div><p>祖先关闭挤压。</p></div>',
      css: 'body { text-spacing-trim: space-all; }',
    );
    expect(
      (await _blocks(source)).single.style!.textSpacingTrim,
      CssTextSpacingTrim.normal,
    );
  });

  test('阅读器显式对齐继续高于作者，行内字号和颜色不丢失', () async {
    final source = await openCssChapter(
      body:
          '<p>前文<span style="font-size:24px;color:#cc2200">高亮》，</span>后文。</p>',
      css: 'body { text-align: right; }',
      overrides: const ReaderOverrides(textAlign: CssTextAlign.center),
    );
    final block = (await _blocks(source)).single;
    expect(block.style!.textAlign, CssTextAlign.center);
    final highlighted = block.layout.runs.where(
      (run) => run.style.color == const Color(0xFFCC2200),
    );
    expect(highlighted, isNotEmpty);
    expect(highlighted.every((run) => run.style.fontSize == 24), isTrue);
  });

  test('标题、列表、题注、导航、代码和诗歌不新增正文默认', () async {
    for (final body in [
      '<h2>目标文字。</h2>',
      '<ul><li><p>目标文字。</p></li></ul>',
      '<figure><figcaption><p>目标文字。</p></figcaption></figure>',
      '<nav><p>目标文字。</p></nav>',
      '<pre><p>目标文字。</p></pre>',
      '<div epub:type="z3998:poem"><p>目标文字。</p></div>',
      '<div class="verse"><p>目标文字。</p></div>',
      '<div style="column-count:2"><p>目标文字。</p></div>',
      '<div style="display:flex"><p>目标文字。</p></div>',
      '<p>目标文字。<br/>保留换行。</p>',
    ]) {
      final source = await openCssChapter(body: body);
      for (final block in await _blocks(source)) {
        expect(
          block.style!.textAlign,
          isNot(CssTextAlign.justify),
          reason: body,
        );
        expect(
          block.style!.textSpacingTrim,
          isNot(CssTextSpacingTrim.trimAll),
          reason: body,
        );
      }
    }
  });

  test('保留空白、竖排、RTL、绝对定位与非叶子正文不新增默认', () async {
    for (final css in [
      'white-space:pre-wrap',
      'white-space:pre-line',
      'writing-mode:vertical-rl',
      'direction:rtl',
      'position:absolute',
      'float:right',
      'column-count:2',
    ]) {
      final source = await openCssChapter(
        body: '<p>特殊布局文字。</p>',
        css: 'p {$css}',
      );
      for (final block in await _blocks(source)) {
        expect(
          block.style!.textAlign,
          isNot(CssTextAlign.justify),
          reason: css,
        );
        expect(
          block.style!.textSpacingTrim,
          isNot(CssTextSpacingTrim.trimAll),
          reason: css,
        );
      }
    }
    final source = await openCssChapter(
      body: '<div>直接文字。<p>子段落文字。</p>尾部文字。</div>',
    );
    final blocks = await _blocks(source);
    final child = blocks.firstWhere((block) => block.layout.text == '子段落文字。');
    expect(child.style!.textAlign, CssTextAlign.justify);
    for (final block in blocks.where((block) => block != child)) {
      expect(block.style!.textAlign, isNot(CssTextAlign.justify));
    }
  });

  test('重排保留原文与同位置 CFI，颜色主题不触发重排', () async {
    final text = '（正文），「中西文 EPUB 混排」，不改变原文。' * 12;
    final source = await openCssChapter(
      body: '<p>$text</p>',
      contentWidth: 240,
    );
    final first = (await _blocks(source)).single;
    final cfi = cfiWithCharOffset(first.startCfi!, 17);
    await source.applyContentSize(width: 130, height: 500);
    final reflowed = (await _blocks(source)).single;
    expect(reflowed.layout.text, text);
    expect(cfiWithCharOffset(reflowed.startCfi!, 17), cfi);
    expect(reflowed.layout.lineCount, greaterThan(first.layout.lineCount));
    final changes = source.invalidationLog.length;
    await source.applyOverrides(
      const ReaderOverrides(
        textColor: Color(0xFFFFFFFF),
        backgroundColor: Color(0xFF000000),
      ),
    );
    final recolored = (await _blocks(source)).single;
    expect(identical(recolored.layout, reflowed.layout), isTrue);
    expect(source.invalidationLog.length, changes);
  });

  test('浮动绕排与跨页保留真实字号、间距、原子盒及注音边界', () async {
    const unit = '（甲乙），「丙丁》」。中西文 EPUB 混排；';
    final source = await openCssChapter(
      body:
          '<div class="float">浮动</div><p>（前文）'
          '<span class="big">大字》，</span>「后文」'
          '<ruby>》，<rt>注音</rt></ruby>'
          '<span class="box"></span>「盒后」${unit * 10}</p>',
      css:
          'body { margin:0; font-family:prose_flow_song; font-size:20px; } '
          'p { margin:0; line-height:1.6; } '
          '.float { float:left; width:70px; height:64px; } '
          '.big { font-size:26px; color:#cc2200; } '
          '.box { display:inline-block; width:18px; height:20px; }',
      contentWidth: 240,
      contentHeight: 180,
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final boxes = [for (final page in pages) ...TextHitTester.lineBoxes(page)]
        .where((box) => box.slice.block.floatSide == null)
        .toList();
    expect(boxes.first.rect.left, greaterThanOrEqualTo(70));
    expect(
      boxes.map((box) => box.text).join(),
      '（前文）大字》，「后文」》，「盒后」${unit * 10}',
    );
    final blocks = boxes.map((box) => box.slice.block).toSet();
    expect(
      blocks
          .expand((block) => block.layout.lines)
          .expand((line) => line.inlineBoxes),
      isNotEmpty,
    );
    expect(
      blocks.expand((block) => block.rubies ?? const <RubyAnnotation>[]),
      isNotEmpty,
    );
    for (final box in boxes) {
      _expectFlowGeometry(box);
    }
  });
}

void _expectFlowGeometry(PageLineBox box) {
  final block = box.slice.block;
  final line = block.layout.lines[box.lineIndex];
  expect(line.spacing, isNotNull);
  final painter = TextPainter(
    text: buildLineSpan(
      layout: block.layout,
      line: line,
      baseStyle: TextLayoutEngine.textStyleFor(block.style!),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final boxesWidth = line.inlineBoxes.fold(
    0.0,
    (sum, placement) => sum + placement.spec.outerWidth,
  );
  expect(painter.width + boxesWidth, closeTo(line.advanceWidth, .5));
  for (final ruby in block.rubies ?? const <RubyAnnotation>[]) {
    for (var offset = ruby.start; offset < ruby.end; offset++) {
      expect(line.spacing!.glyphs.containsKey(offset - line.start), isFalse);
    }
  }
  painter.dispose();
}
