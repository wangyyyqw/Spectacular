import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';

import 'support/css_chapter_book.dart';

/// 书内字体正式管线：作者声明保留组合族，测量与绘制使用独立 face 的原生族。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 用 app 自带字体改名塞进书内，避免依赖系统字体。
  final fontFile = File('assets/fonts/MoyuSerif-Regular.otf');
  final skip = fontFile.existsSync() ? null : '缺少内置字体文件，跳过';

  test('书内 @font-face 字族被改写成引擎族名（块样式 + 行内 run）', () async {
    final fontBytes = fontFile.readAsBytesSync();
    final source = await openCssChapter(
      body:
          '<p class="bulk">书内字体段落</p>'
          '<p style="font-family: mm, serif">内联字体段落</p>'
          '<p class="inline">行内<span class="mm">书内字体</span>结束</p>',
      css:
          '@font-face { font-family: "mm"; '
          'src: url("../Fonts/mm.otf"); } '
          '.bulk, .mm { font-family: "mm", serif; }',
      binaryFiles: <String, List<int>>{'OEBPS/Fonts/mm.otf': fontBytes},
      contentWidth: 300,
      contentHeight: 500,
    );
    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList();

    final bulk = blocks.firstWhere(
      (block) => block.layout.text.startsWith('书内字体段落'),
    );
    final engineFamily = bulk.style!.fontFamily;
    expect(engineFamily, isNotNull);
    expect(
      engineFamily,
      startsWith('bi_'),
      reason: '块字体族应改写成 BookFontLoader 的引擎族名',
    );
    expect(bulk.style!.fontFamilies.first, endsWith('_mm'));
    // 回退链保留：serif 原样跟在后面。
    expect(bulk.style!.fontFamilies.last, 'serif');

    // 块级 style 属性（内联声明源）同样要改写。
    final inlineDecl = blocks.firstWhere(
      (block) => block.layout.text.startsWith('内联字体段落'),
    );
    expect(inlineDecl.style!.fontFamily, startsWith('bi_'));
    expect(inlineDecl.style!.fontFamilies.first, endsWith('_mm'));
    expect(inlineDecl.style!.fontFamilies.last, 'serif');

    final inline = blocks.firstWhere(
      (block) => block.layout.text.contains('行内'),
    );
    final spanStart = inline.layout.text.indexOf('书内字体');
    final inlineRun = inline.layout.runs.firstWhere(
      (run) => run.start <= spanStart && run.end > spanStart,
    );
    expect(
      inlineRun.style.fontFamily,
      startsWith('bi_'),
      reason: '行内 style 的 font-family 同样要改写',
    );
    expect(inlineRun.style.fontFamily, engineFamily);
    expect(inlineRun.style.fontFamilies.single, startsWith('bi_face_'));
  }, skip: skip);

  test('并发章节请求共同等待字体注册，不先缓存回退字体的排版', () async {
    final source = await openCssChapter(
      body: '<p>并发读取仍使用书内字体</p>',
      css:
          '@font-face { font-family: "concurrent"; '
          'src: url("../Fonts/c.otf"); } p { font-family: "concurrent", serif; }',
      binaryFiles: {'OEBPS/Fonts/c.otf': fontFile.readAsBytesSync()},
    );
    final results = await Future.wait([
      source.loadChapter(0),
      source.loadChapter(0),
      source.loadChapter(0),
    ]);
    for (final pages in results) {
      final block = pages.first.slices.first.block;
      expect(block.style!.fontFamily, startsWith('bi_'));
      expect(block.style!.fontFamilies.first, endsWith('_concurrent'));
      expect(
        block.layout.height,
        results.first.first.slices.first.block.layout.height,
      );
    }
  }, skip: skip);

  test('local-only 书籍字族映射到可用内置字族', () async {
    for (final family in <String>['zw', 'DK-SONGTI']) {
      final source = await openCssChapter(
        body: '<p class="book-font">缺字回退</p>',
        css:
            '@font-face { font-family: "$family"; '
            'src: local("宋体"), local("DK-SONGTI"); } '
            '.book-font { font-family: "$family", serif; }',
      );
      final block = (await source.loadChapter(0))
          .expand((page) => page.slices)
          .firstWhere((slice) => slice.block.layout.text == '缺字回退')
          .block;
      expect(
        block.style!.fontFamily,
        FontFamilyAliases.song,
        reason: '$family 的 local-only 来源应复用内置宋体',
      );
      expect(block.style!.fontFamilies.last, 'serif');
    }
  });

  test('无内置字库的楷体按字形回退到内置宋体', () async {
    final source = await openCssChapter(
      body: '<p class="book-font">制作说明</p>',
      css: '.book-font { font-family: "楷体"; }',
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .firstWhere((slice) => slice.block.layout.text == '制作说明')
        .block;
    expect(block.style!.fontFamily, '楷体');
    expect(block.layout.runs, isNotEmpty);
    expect(
      block.layout.runs.every(
        (run) => run.style.fontFamily == FontFamilyAliases.song,
      ),
      isTrue,
      reason: '未注册的楷体主族须逐字落到内置宋体',
    );
  });
}
