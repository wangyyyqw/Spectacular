import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = File('assets/fonts/SourceHanSerifCN-Regular.otf')
      .readAsBytesSync();
  const selected = ReaderOverrides(fontFamily: 'user_policy');
  const css = '''
    @font-face { font-family: embedded; src: url('../Fonts/book.otf'); }
    @font-face { font-family: localfont; src: local('宋体'); }
    @font-face { font-family: absent; src: url('../Fonts/absent.otf'); }
    .embedded { font-family: embedded, serif; }
    .short { font: italic 21px/1.4 embedded, serif; }
    .variable { --book-font: embedded, serif; font-family: var(--book-font); }
    .local { font-family: localfont; }
    .absent { font-family: absent; }
    .generated::before { content: '前缀'; font-family: embedded; }
    h1 { font-family: embedded; font-size: 30px; }
    td { font-family: embedded; font-size: 13px; }
  ''';
  const body = '''
    <h1>内嵌标题</h1><p>默认正文</p>
    <p class="embedded">内嵌正文<span>继承内嵌</span><span style="font-family: sans-serif">外部字体</span></p>
    <p class="short">简写内嵌</p><p class="local">系统引用</p><p class="absent">缺失字库</p>
    <p class="variable">变量内嵌<span>变量继承</span></p>
    <p class="generated">生成正文</p>
    <table><tr><td>内嵌表格<span style="font-family: sans-serif">外部格内字体</span></td></tr></table>
    <p>混合<span style="font-family: embedded">内嵌行内</span>结束</p>
  ''';
  Future<List<PageBlock>> load(EpubChapterSource source) async => [
    for (final page in await source.loadChapter(0))
      for (final slice in page.slices) slice.block,
  ];
  PageBlock paragraph(List<PageBlock> blocks, String text) =>
      blocks.firstWhere((block) => block.layout.text.contains(text));
  String? runFamily(PageBlock block, String text) {
    final offset = block.layout.text.indexOf(text);
    return block.layout.runs
        .firstWhere((run) => run.start <= offset && run.end > offset)
        .style
        .fontFamily;
  }

  test('默认保留标题、简写、继承、行内、伪元素和表格的内嵌字体', () async {
    final source = await openCssChapter(
      body: body,
      css: css,
      overrides: selected,
      binaryFiles: {'OEBPS/Fonts/book.otf': bytes},
    );
    addTearDown(source.close);
    final blocks = await load(source);
    for (final text in ['默认正文', '系统引用', '缺失字库', '生成正文']) {
      expect(paragraph(blocks, text).style!.fontFamily, 'user_policy');
    }
    for (final text in ['内嵌标题', '内嵌正文', '简写内嵌', '变量内嵌']) {
      expect(paragraph(blocks, text).style!.fontFamily, startsWith('bi_'));
    }
    expect(paragraph(blocks, '简写内嵌').style!.fontSize, 21);
    expect(paragraph(blocks, '内嵌标题').style!.fontSize, 30);
    final embedded = paragraph(blocks, '内嵌正文');
    expect(runFamily(embedded, '继承内嵌'), startsWith('bi_'));
    expect(runFamily(embedded, '外部字体'), 'user_policy');
    expect(paragraph(blocks, '变量内嵌').style!.fontFamilies.last, 'serif');
    expect(runFamily(paragraph(blocks, '变量内嵌'), '变量继承'), startsWith('bi_'));
    expect(runFamily(paragraph(blocks, '混合'), '内嵌行内'), startsWith('bi_'));
    expect(runFamily(paragraph(blocks, '生成正文'), '前缀'), startsWith('bi_'));
    final cell = blocks.firstWhere((b) => b.table != null).table!.cells.first;
    expect(cell.style.fontFamily, startsWith('bi_'));
    expect(cell.style.fontSize, 13);
    final offset = cell.layout.text.indexOf('外部格内字体');
    expect(
      cell.layout.runs
          .firstWhere((r) => r.start <= offset && r.end > offset)
          .style
          .fontFamily,
      'user_policy',
    );
  });
  test('强制模式统一字族，关闭后恢复内嵌字体并保留字号', () async {
    final source = await openCssChapter(
      body: body,
      css: css,
      overrides: selected,
      binaryFiles: {'OEBPS/Fonts/book.otf': bytes},
    );
    addTearDown(source.close);
    await load(source);
    await source.applyOverrides(selected.copyWith(overrideEmbeddedFonts: true));
    final forced = await load(source);
    for (final block in forced) {
      if (block.layout.text.isNotEmpty) {
        expect(block.style!.fontFamily, 'user_policy');
        expect(
          block.layout.runs.every((r) => r.style.fontFamily == 'user_policy'),
          isTrue,
        );
      }
      for (final cell in block.table?.cells ?? const <TableCellRender>[]) {
        expect(cell.style.fontFamily, 'user_policy');
        expect(
          cell.layout.runs.every((r) => r.style.fontFamily == 'user_policy'),
          isTrue,
        );
        expect(cell.style.fontSize, 13);
      }
    }
    expect(paragraph(forced, '内嵌标题').style!.fontSize, 30);
    await source.applyOverrides(selected);
    final restored = await load(source);
    expect(paragraph(restored, '内嵌标题').style!.fontFamily, startsWith('bi_'));
    expect(runFamily(paragraph(restored, '混合'), '内嵌行内'), startsWith('bi_'));
  });

  test('损坏的内嵌字体不能阻止默认自定义字体替换', () async {
    final source = await openCssChapter(
      body: '<p style="font-family: broken">损坏字库</p>',
      css: '@font-face {font-family: broken; src: url("../Fonts/broken.otf");}',
      binaryFiles: {
        'OEBPS/Fonts/broken.otf': [0, 1, 2, 3],
      },
      overrides: selected,
    );
    addTearDown(source.close);
    expect(
      paragraph(await load(source), '损坏字库').style!.fontFamily,
      'user_policy',
    );
  });
}
