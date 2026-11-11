import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

const _introBody =
    '<p>普通正文</p>'
    '<div class="intro"><p class="title"><span>内容简介</span></p></div>'
    '<p class="summary">简介正文</p>'
    '<p class="summary" style="font-size: .6em; text-align: right;">'
    '—— By Venzos</p>';
const _introCss =
    'body { font-size: 16px; } p { line-height: 130%; } '
    '.title { font-size: .8em; text-align: center; margin-bottom: 3em; } '
    '.summary { font-size: .8em; margin: 1em 10%; }';

Future<Map<String, PageBlock>> _textBlocks(EpubChapterSource source) async => {
  for (final page in await source.loadChapter(0))
    for (final slice in page.slices)
      if (slice.block.layout.text.isNotEmpty)
        slice.block.layout.text: slice.block,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('简介标题、正文和署名按各自比例缩放，普通正文基准保持不变', () async {
    final source = await openCssChapter(body: _introBody, css: _introCss);
    addTearDown(source.close);
    for (final readerSize in [21.0, 25.0]) {
      await source.applyOverrides(
        ReaderOverrides(fontSize: readerSize, lineHeight: 1.3),
      );
      final blocks = await _textBlocks(source);
      final expected = {
        '普通正文': readerSize,
        '内容简介': readerSize * .8,
        '简介正文': readerSize * .8,
        '—— By Venzos': readerSize * .6,
      };
      for (final entry in expected.entries) {
        final block = blocks[entry.key]!;
        expect(block.style!.fontSize, closeTo(entry.value, .001));
        expect(
          block.layout.runs.map((run) => run.style.fontSize),
          everyElement(closeTo(entry.value, .001)),
          reason: '${entry.key}的实际测量与绘制使用同一字号',
        );
      }
    }
  });

  test('未设置阅读器字号时，简介继续使用原书字号', () async {
    final source = await openCssChapter(body: _introBody, css: _introCss);
    addTearDown(source.close);
    final blocks = await _textBlocks(source);
    expect(blocks['普通正文']!.style!.fontSize, 16);
    expect(blocks['内容简介']!.style!.fontSize, closeTo(12.8, .001));
    expect(blocks['简介正文']!.style!.fontSize, closeTo(12.8, .001));
    expect(blocks['—— By Venzos']!.style!.fontSize, closeTo(9.6, .001));
  });

  test('块级 br 不拆散标题，相对字号和 em 边距一起缩放', () async {
    final source = await openCssChapter(
      body:
          '<p class="section">/<br class="break"/>作者简介</p>'
          '<p class="name">村上春树</p>',
      css:
          'body { font-size: 16px; } '
          '.section { font-size: 1.29167em; line-height: 1.8em; '
          'margin: .8em 0 .6em; } '
          '.break { display: block; } '
          '.name { line-height: 1.8em; margin: 1em 0; }',
      overrides: const ReaderOverrides(
        fontSize: 21,
        lineHeight: 1.3,
        paragraphSpacing: 0,
      ),
    );
    addTearDown(source.close);
    final blocks = await _textBlocks(source);
    final title = blocks['/\n作者简介']!;
    final name = blocks['村上春树']!;
    final titleSize = 21 * 1.29167;
    expect(title.style!.fontSize, closeTo(titleSize, .001));
    expect(title.style!.lineHeight, closeTo(titleSize * 1.3, .001));
    expect(title.style!.margin.top, closeTo(titleSize * .8, .001));
    expect(title.style!.margin.bottom, closeTo(titleSize * .6, .001));
    expect(name.spaceBefore, closeTo(titleSize * .6, .001));
  });

  for (final declaration in ['.8em', '.8rem', '80%']) {
    test('class、id 和内联声明的 $declaration 均相对阅读器字号生效', () async {
      final source = await openCssChapter(
        body:
            '<p>普通正文</p><p class="scaled">类选择器</p>'
            '<p id="scaled">标识选择器</p>'
            '<p style="font-size: $declaration;">内联声明</p>',
        css:
            'body { font-size: 16px; } p { font-size: .75em; } '
            '.scaled, #scaled { font-size: $declaration; }',
        overrides: const ReaderOverrides(fontSize: 21),
      );
      addTearDown(source.close);
      final blocks = await _textBlocks(source);
      expect(blocks['普通正文']!.style!.fontSize, 21);
      for (final text in ['类选择器', '标识选择器', '内联声明']) {
        expect(blocks[text]!.style!.fontSize, closeTo(16.8, .001));
      }
    });
  }

  test('font 简写和内联覆盖采用级联胜出的相对字号', () async {
    final source = await openCssChapter(
      body:
          '<p class="scaled">简写</p>'
          '<p class="scaled" style="font-size: .8em;">内联覆盖</p>',
      css: '.scaled { font: italic .6em/1.3 serif; }',
      overrides: const ReaderOverrides(fontSize: 21),
    );
    addTearDown(source.close);
    final blocks = await _textBlocks(source);
    expect(blocks['简写']!.style!.fontSize, closeTo(12.6, .001));
    expect(blocks['简写']!.style!.italic, isTrue);
    expect(blocks['内联覆盖']!.style!.fontSize, closeTo(16.8, .001));
  });

  test('行内相对字号继承缩放后的父段落，阅读器行高与对齐继续生效', () async {
    final source = await openCssChapter(
      body: '<p class="scaled">正文<span style="font-size: .5em;">注</span></p>',
      css: '.scaled { font-size: .8em; line-height: 130%; }',
      overrides: const ReaderOverrides(
        fontSize: 21,
        lineHeight: 1.8,
        textAlign: CssTextAlign.right,
      ),
    );
    addTearDown(source.close);
    final block = (await _textBlocks(source))['正文注']!;
    expect(block.style!.fontSize, closeTo(16.8, .001));
    expect(block.style!.lineHeight, closeTo(16.8 * 1.8, .001));
    expect(block.style!.textAlign, CssTextAlign.right);
    expect(block.layout.runs.last.style.fontSize, closeTo(8.4, .001));
  });

  test('rem 以阅读器字号为基准，不受作者父容器缩小影响或放大作者盒', () async {
    final source = await openCssChapter(
      body: '<div class="box"><h2>标题</h2><p class="scaled">说明</p></div>',
      css:
          '.box { font-size: .5em; border: 1em solid #000; padding: .5em; } '
          'h2, .scaled { font-size: .8rem; }',
      overrides: const ReaderOverrides(fontSize: 21),
    );
    addTearDown(source.close);
    final blocks = await _textBlocks(source);
    expect(blocks['标题']!.style!.fontSize, closeTo(16.8, .001));
    expect(blocks['说明']!.style!.fontSize, closeTo(16.8, .001));
    final container = blocks['说明']!.containers.single.container.style;
    expect(container.fontSize, 8);
    expect(container.borders.left.width, 8);
    expect(container.padding.left, 4);
  });

  test('行内 rem 使用阅读器根字号，嵌套 em 继续相对最终父字号', () async {
    final source = await openCssChapter(
      body:
          '<p class="scaled">正文<span class="note">注'
          '<span style="font-size: .5em;">小</span></span></p>',
      css: '.scaled { font-size: .8em; } .note { font: .5REM/1.3 serif; }',
    );
    addTearDown(source.close);
    for (final readerSize in [21.0, 25.0]) {
      await source.applyOverrides(ReaderOverrides(fontSize: readerSize));
      final block = (await _textBlocks(source))['正文注小']!;
      final note = block.layout.runs.firstWhere((run) => run.start == 2);
      final nested = block.layout.runs.firstWhere((run) => run.start == 3);
      expect(block.style!.fontSize, closeTo(readerSize * .8, .001));
      expect(note.style.fontSize, closeTo(readerSize * .5, .001));
      expect(nested.style.fontSize, closeTo(readerSize * .5 * .5, .001));
    }
  });

  test('行内列表标记不把相对字号段落的测量恢复为满字号', () async {
    final source = await openCssChapter(
      body: '<ol><li class="scaled">列表正文</li></ol>',
      css:
          '.scaled { font-size: .8em; list-style-position: inside; '
          'text-indent: 0; }',
      overrides: const ReaderOverrides(fontSize: 21, lineHeight: 1.3),
    );
    addTearDown(source.close);
    final block = (await _textBlocks(source))['列表正文']!;
    expect(block.listMarker, '1.');
    expect(block.style!.fontSize, closeTo(16.8, .001));
    expect(block.layout.runs, isNotEmpty);
    expect(
      block.layout.runs.map((run) => run.style.fontSize),
      everyElement(closeTo(16.8, .001)),
    );
  });
}
