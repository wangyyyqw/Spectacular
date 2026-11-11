import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

Future<Map<String, PageBlockSlice>> _slices(EpubChapterSource source) async => {
  for (final page in await source.loadChapter(0))
    for (final slice in page.slices)
      if (slice.block.layout.text.isNotEmpty) slice.block.layout.text: slice,
};

void _expectChapterSpacing(
  Map<String, PageBlockSlice> slices,
  double size,
  double spacing,
) {
  final heading = slices['章号\n章节标题']!.block;
  final decoration = slices['Edition Text']!.block;
  final first = slices['普通正文一']!;
  final second = slices['普通正文二']!;
  expect(heading.style!.lineHeight, closeTo(size * .8 * 1.5, .001));
  expect(heading.style!.margin.bottom, 3);
  expect(decoration.style!.fontSize, closeTo(size * .5, .001));
  expect(decoration.spaceBefore, 3, reason: '标题 3px 与装饰段 0 折叠');
  expect(first.leadingExtent, closeTo(size * .5 * 4, .001));
  expect(first.block.spaceBefore, closeTo(size * .5 * 4, .001));
  expect(second.leadingExtent, spacing, reason: '后续普通正文段距仍取设置值');
  expect(second.block.spaceAfter, spacing);
  for (final slice in [first, second]) {
    expect(slice.block.style!.fontSize, size);
    expect(
      slice.block.layout.runs.map((run) => run.style.fontSize),
      everyElement(size),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('标题与装饰段保留作者留白，后续普通正文仍使用阅读器段距', () async {
    final source = await openCssChapter(
      body:
          '<h2><b>章号</b><br/>章节标题</h2>'
          '<p class="decoration">Edition Text</p>'
          '<p>普通正文一</p><p>普通正文二</p>',
      css:
          'p { font-size: 16px; margin: 1em 0; line-height: 130%; } '
          'h2 { font-size: .8em; line-height: 150%; margin: 0 0 3px; } '
          'h2 b { font-size: 1.2em; } '
          '.decoration { font-size: .5em; text-align: left; '
          'margin: 0 auto 4em; }',
      contentHeight: 800,
    );
    addTearDown(source.close);
    for (final size in [21.0, 25.0]) {
      for (final spacing in [0.0, 8.0]) {
        await source.applyOverrides(
          ReaderOverrides(
            fontSize: size,
            lineHeight: 1.3,
            paragraphSpacing: spacing,
          ),
        );
        _expectChapterSpacing(await _slices(source), size, spacing);
      }
    }
  });

  for (final (element, rule) in [
    ('<p class="note">局部段落</p>', '.note { margin: 12px 0 40px; }'),
    ('<p id="note">局部段落</p>', '#note { margin: 12px 0 40px; }'),
    ('<p style="margin: 12px 0 40px">局部段落</p>', ''),
  ]) {
    test('局部边距按 class、id 或行内来源保留：$element', () async {
      final source = await openCssChapter(
        body: '$element<p>后续正文</p>',
        css: 'p { margin: 20px 0; } $rule',
        overrides: const ReaderOverrides(fontSize: 21, paragraphSpacing: 0),
      );
      addTearDown(source.close);
      final slices = await _slices(source);
      expect(slices['局部段落']!.block.spaceBefore, 12);
      expect(slices['后续正文']!.leadingExtent, 40);
      expect(slices['后续正文']!.block.spaceAfter, 0);
    });
  }

  test('只声明段后一侧时，段前仍取阅读器设置，颜色类不豁免正文段距', () async {
    final source = await openCssChapter(
      body: '<p class="note">注解</p><p class="prose">普通正文</p>',
      css:
          'p { margin: 20px 0; } .note { margin-bottom: 40px; } '
          '.prose { color: #333; font-size: 1em; }',
      overrides: const ReaderOverrides(fontSize: 21, paragraphSpacing: 8),
    );
    addTearDown(source.close);
    final slices = await _slices(source);
    expect(slices['注解']!.block.spaceBefore, 8);
    expect(slices['普通正文']!.leadingExtent, 40);
    expect(slices['普通正文']!.block.spaceAfter, 8);
    expect(slices['普通正文']!.block.style!.fontSize, 21);
  });

  test('逻辑边距与多看边距别名沿用已解析的作者留白', () async {
    final source = await openCssChapter(
      body: '<p class="note">注解</p><p>普通正文</p>',
      css:
          'p { margin: 20px 0; } '
          '.note { margin-block-start: 12px; duokan-margin-after: 40px; }',
      overrides: const ReaderOverrides(paragraphSpacing: 0),
    );
    addTearDown(source.close);
    final slices = await _slices(source);
    expect(slices['注解']!.block.spaceBefore, 12);
    expect(slices['普通正文']!.leadingExtent, 40);
  });

  test('容器下所有 p 的通用边距和水平边距不豁免正文段距', () async {
    final source = await openCssChapter(
      body:
          '<div class="wrapper"><p class="prose">普通正文一</p>'
          '<p>普通正文二</p></div>',
      css:
          '.wrapper p { margin: 20px 0; } '
          '.prose { margin-left: 10px; font-size: 1em; }',
      overrides: const ReaderOverrides(fontSize: 21, paragraphSpacing: 0),
    );
    addTearDown(source.close);
    final slices = await _slices(source);
    for (final slice in slices.values) {
      expect(slice.block.spaceBefore, 0);
      expect(slice.block.spaceAfter, 0);
      expect(slice.block.style!.fontSize, 21);
    }
  });

  test('局部零边距和负边距仍按作者声明参与折叠', () async {
    final source = await openCssChapter(
      body: '<p class="note">注解</p><p>普通正文</p>',
      css: 'p { margin: 20px 0; } .note { margin: 0 0 -12px; }',
      overrides: const ReaderOverrides(paragraphSpacing: 8),
    );
    addTearDown(source.close);
    final slices = await _slices(source);
    expect(slices['注解']!.block.spaceBefore, 0);
    expect(slices['普通正文']!.block.spaceBefore, -4);
    expect(slices['普通正文']!.block.spaceAfter, 8);
  });

  test('边距采用级联胜出的值，未匹配的局部规则不改变正文段距', () async {
    final source = await openCssChapter(
      body:
          '<p id="note" class="note" style="margin-bottom: 18px">注解</p>'
          '<p class="prose">普通正文一</p><p>普通正文二</p>',
      css:
          'p { margin: 20px 0; } .note { margin-bottom: 60px; } '
          '#note { margin-bottom: 30px !important; } '
          '@media (min-width: 600px) { .prose { margin: 100px 0; } } '
          '.unmatched { margin: 100px 0; }',
      contentWidth: 300,
      overrides: const ReaderOverrides(paragraphSpacing: 8),
    );
    addTearDown(source.close);
    final slices = await _slices(source);
    expect(slices['普通正文一']!.leadingExtent, 30);
    expect(slices['普通正文二']!.leadingExtent, 8);
    expect(slices['普通正文二']!.block.spaceAfter, 8);
  });
}
