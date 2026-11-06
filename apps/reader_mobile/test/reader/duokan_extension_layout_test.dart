import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/extension.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

const String _imagePath = 'OEBPS/Images/p.png';
const String _slimImagePath = 'OEBPS/Images/p~slim.png';

/// 只构造图片文件头；布局断言不需要真正解码像素。
Uint8List _pngHeader(int width, int height) {
  final bytes = Uint8List(24);
  bytes.setAll(0, const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
  ]);
  ByteData.sublistView(bytes)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return bytes;
}

String _extensionXml(String layout, {int? pageWidth, int? pageHeight}) =>
    '''
<duokan-extension version="1.0">
  <display-options>
    <layout>$layout</layout>
    ${pageWidth == null ? '' : '<option name="page-width">$pageWidth</option>'}
    ${pageHeight == null ? '' : '<option name="page-height">$pageHeight</option>'}
  </display-options>
</duokan-extension>
''';

Future<EpubChapterSource> _openFixedLike({
  required String layout,
  required String body,
  String css = '',
  String itemrefAttributes = '',
  int? pageWidth,
  int? pageHeight,
  Map<String, List<int>> binaryFiles = const <String, List<int>>{},
  double contentWidth = 300,
  double contentHeight = 500,
  ReaderOverrides overrides = const ReaderOverrides(),
}) => openCssChapter(
  body: body,
  css: css,
  itemrefAttributes: itemrefAttributes,
  binaryFiles: <String, List<int>>{
    DuokanExtensionParser.path: utf8.encode(
      _extensionXml(layout, pageWidth: pageWidth, pageHeight: pageHeight),
    ),
    _imagePath: _pngHeader(300, 500),
    ...binaryFiles,
  },
  contentWidth: contentWidth,
  contentHeight: contentHeight,
  overrides: overrides,
);

String _visibleText(List<PageContent> pages) => pages
    .expand((page) => page.slices)
    .map((slice) => slice.block.layout.text)
    .join('\n');

List<String?> _cfis(List<PageContent> pages) => [
  for (final page in pages)
    for (final slice in page.slices) slice.block.startCfi,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixed-page 单图带尺寸仍一页 contain，四边出血且忽略正文设置', () async {
    final source = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body:
          '<img src="../Images/p.png" width="100" height="200"/>'
          '<img src="../Images/ignored.png" style="display:none"/>'
          '<span>隐藏标题</span>',
      css:
          'body { padding: 40px; font-size: 30px; line-height: 3; } '
          'span { display: none; } img { width: 80px; height: 60px; }',
      overrides: const ReaderOverrides(
        fontSize: 32,
        lineHeight: 2.5,
        padding: CssEdges(left: 24, top: 90, right: 18, bottom: 16),
      ),
    );
    await source.applyContentSize(width: 300, height: 500, topInset: 90);

    final pages = await source.loadChapter(0);
    expect(pages, hasLength(1));
    final page = pages.single;
    expect(page.slices, hasLength(1));
    final block = page.slices.single.block;
    expect(block.style!.backgroundImage, _imagePath);
    expect(
      block.style!.backgroundSize.mode,
      CssBackgroundSizeMode.contain,
      reason: '固定版默认 contain 不裁切',
    );
    expect(block.style!.backgroundPosition.x.value, closeTo(50, 0.01));
    expect(block.style!.backgroundPosition.y.value, closeTo(50, 0.01));
    expect(block.bleedLeft, isTrue);
    expect(block.bleedRight, isTrue);
    expect(block.bleedTop, isTrue);
    expect(block.bleedBottom, isTrue);
    expect(block.layout.width, closeTo(300, 0.01));
    expect(block.layout.height, closeTo(500, 0.01));
    expect(block.style!.fontSize, 16, reason: '固定页不消费正文字号');
    expect(page.usedHeight, closeTo(500, 0.01));
    expect(source.layoutWarningFor(0), isNull);
  });

  test('fixed-page fullscreen 用 cover，fitwindow 用 contain 且优先', () async {
    final fullscreen = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body: '<img src="../Images/p.png"/>',
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
    );
    final coverBlock = (await fullscreen.loadChapter(0))
        .single
        .slices
        .single
        .block;
    expect(coverBlock.style!.backgroundSize.mode, CssBackgroundSizeMode.cover);

    final fitWindow = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body: '<img src="../Images/p.png"/>',
      itemrefAttributes: ' properties="duokan-page-fitwindow"',
    );
    final containBlock = (await fitWindow.loadChapter(0))
        .single
        .slices
        .single
        .block;
    expect(
      containBlock.style!.backgroundSize.mode,
      CssBackgroundSizeMode.contain,
    );

    final both = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body: '<img src="../Images/p.png"/>',
      itemrefAttributes:
          ' properties="duokan-page-fullscreen duokan-page-fitwindow"',
    );
    final bothBlock = (await both.loadChapter(0)).single.slices.single.block;
    expect(
      bothBlock.style!.backgroundSize.mode,
      CssBackgroundSizeMode.contain,
      reason: 'fitwindow 与 fullscreen 同时出现时 fitwindow 优先',
    );
  });

  test('comics-frame 2 与 transverse-comic 3 的单图章走一页 contain', () async {
    for (final layout in <EpubLayoutType>[
      EpubLayoutType.comicsFrame,
      EpubLayoutType.transverseComic,
    ]) {
      final source = await _openFixedLike(
        layout: layout.token,
        body:
            '<img src="../Images/p.png" width="120" height="180"/>'
            '<span style="display:none">说明</span>',
      );
      final pages = await source.loadChapter(0);
      expect(pages, hasLength(1), reason: layout.token);
      final block = pages.single.slices.single.block;
      expect(
        block.style!.backgroundSize.mode,
        CssBackgroundSizeMode.contain,
        reason: layout.token,
      );
      expect(source.layoutWarningFor(0), isNull, reason: layout.token);
    }
  });

  test('多图或含正文记录诊断并保留原有排版', () async {
    final withText = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body:
          '<p>正文必须保留</p><img src="../Images/p.png"/>'
          '<img src="../Images/p.png"/>',
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
    );
    final pages = await withText.loadChapter(0);
    expect(
      withText.layoutWarningFor(0),
      startsWith('E_DUOKAN_FIXED_LAYOUT_UNSUPPORTED:'),
    );
    expect(_visibleText(pages), contains('正文必须保留'));
    expect(
      pages.expand((page) => page.slices).length,
      greaterThan(1),
      reason: '多元素章节不能压成单图整页',
    );

    final warning = withText.layoutWarningFor(0);
    withText.clearPaginationCache();
    await withText.loadChapter(0);
    expect(withText.layoutWarningFor(0), warning, reason: '缓存重排不重复诊断');
    await withText.applyOverrides(const ReaderOverrides(fontSize: 24));
    await withText.loadChapter(0);
    expect(withText.layoutWarningFor(0), warning, reason: '设置变化不重复诊断');
  });

  test('纵向漫画记录诊断且不启用漫画单页适配', () async {
    final source = await _openFixedLike(
      layout: EpubLayoutType.verticalComic.token,
      body: '<img src="../Images/p.png" width="120" height="180"/>',
    );
    await source.loadChapter(0);
    expect(
      source.layoutWarningFor(0),
      startsWith('E_DUOKAN_VERTICAL_COMIC_UNSUPPORTED:'),
    );
    expect(
      source.document.extensionConfig.layout,
      EpubLayoutType.verticalComic,
    );
  });

  test('图片缺失记录诊断并回退，正文不丢', () async {
    final source = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body:
          '<p>缺图旁的正文</p>'
          '<img src="../Images/missing.png"/>',
    );
    final pages = await source.loadChapter(0);
    expect(source.layoutWarningFor(0), startsWith('E_DUOKAN_IMAGE_MISSING:'));
    expect(_visibleText(pages), contains('缺图旁的正文'));
  });

  test('扩展页宽高参与 ~slim 选择，未声明时仍按视口比例', () async {
    final assets = <String, List<int>>{
      _imagePath: _pngHeader(300, 500),
      _slimImagePath: _pngHeader(200, 500),
    };
    final fixedRatio = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body: '<img src="../Images/p.png"/>',
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
      pageWidth: 200,
      pageHeight: 500,
      binaryFiles: assets,
    );
    final fixedBlock = (await fixedRatio.loadChapter(0))
        .single
        .slices
        .single
        .block;
    expect(
      fixedBlock.style!.backgroundImage,
      _slimImagePath,
      reason: '扩展页比例 0.4，slim 图 0.4 比原图 0.6 更接近',
    );

    final viewportRatio = await _openFixedLike(
      layout: EpubLayoutType.fixedPage.token,
      body: '<img src="../Images/p.png"/>',
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
      binaryFiles: assets,
    );
    final viewportBlock = (await viewportRatio.loadChapter(0))
        .single
        .slices
        .single
        .block;
    expect(
      viewportBlock.style!.backgroundImage,
      _imagePath,
      reason: '页宽高缺失时沿用视口比例 0.6，原图更接近',
    );
  });

  test('带扩展 XML 的 reflow 与无扩展版本页数、文本顺序和 CFI 一致', () async {
    final body = List.generate(
      40,
      (index) => '<p>第${index + 1}段用于验证普通重排不受扩展元数据影响。</p>',
    ).join();
    const css = 'p { margin: 0 0 8px; font-size: 18px; line-height: 1.6; }';
    final plain = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 260,
      contentHeight: 220,
    );
    final extended = await openCssChapter(
      body: body,
      css: css,
      binaryFiles: <String, List<int>>{
        DuokanExtensionParser.path: utf8.encode(
          _extensionXml(
            EpubLayoutType.reflow.token,
            pageWidth: 1200,
            pageHeight: 1800,
          ),
        ),
      },
      contentWidth: 260,
      contentHeight: 220,
    );

    final plainPages = await plain.loadChapter(0);
    final extendedPages = await extended.loadChapter(0);
    expect(extendedPages.length, plainPages.length);
    expect(_visibleText(extendedPages), _visibleText(plainPages));
    expect(_cfis(extendedPages), _cfis(plainPages));
    expect(plain.layoutWarningFor(0), isNull);
    expect(extended.layoutWarningFor(0), isNull);
  });
}
