import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart'
    show
        ReaderContentLayout,
        ReaderFormat,
        ReaderFormatOpener,
        ReaderOpenOptions,
        ReaderPublicationSource;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/extension.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认字节与文件入口独立排版并保留相同页面与 CFI', () async {
    const ReaderFormatOpener<EpubChapterSource> opener = EpubFormatOpener();
    final bytes = _textBook();
    final file = await _writeBook(bytes);
    final fromBytes = _track(await opener.openBytes(bytes));
    final fromFile = _track(await opener.openFile(file));
    expect(opener.format, ReaderFormat.epub);
    for (final source in [fromBytes, fromFile]) {
      expect(source.format, ReaderFormat.epub);
      expect(source.layout, ReaderContentLayout.reflowable);
      expect(source.baseContentWidth, 320);
      expect(source.baseContentHeight, 480);
      expect(source.baseStyle.fontSize, 16);
      expect(source.trimTextEdges, isTrue);
    }
    final bytePages = await fromBytes.loadChapter(0);
    final filePages = await fromFile.loadChapter(0);
    expect(bytePages.length, greaterThan(1));
    expect(fromBytes.chapterLayoutCount, 1);
    expect(fromFile.chapterLayoutCount, 1);
    expect(_pageShape(filePages), _pageShape(bytePages));
    for (final percent in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final cfi = fromBytes.cfiForReadingPercent(percent);
      expect(cfi, isNotNull);
      expect(fromFile.cfiForReadingPercent(percent), cfi);
      expect(
        fromFile.readingPercentForCfi(cfi),
        fromBytes.readingPercentForCfi(cfi),
      );
    }
  });

  test('公共参数进入实际布局，同内容版本的两个入口共享完成结果', () async {
    final bytes = _textBook();
    final file = await _writeBook(bytes);
    final style = ComputedStyle({'font-size': '19px', 'line-height': '1.5'});
    final options = ReaderOpenOptions(
      contentWidth: 240,
      contentHeight: 180,
      style: style,
      trimTextEdges: false,
      contentVersion: '统一打开参数版本',
    );
    const opener = EpubFormatOpener();
    final fromBytes = _track(await opener.openBytes(bytes, options: options));
    final bytePages = await fromBytes.loadChapter(0);
    _expectCustomLayout(fromBytes, bytePages, style);
    final fromFile = _track(await opener.openFile(file, options: options));
    final filePages = await fromFile.loadChapter(0);
    _expectCustomLayout(fromFile, filePages, style);
    expect(fromBytes.chapterLayoutCount, 1);
    expect(fromFile.chapterLayoutCount, 0);
    expect(filePages, same(bytePages));
    fromFile.setContentVersion('统一打开参数新版本');
    final refreshedPages = await fromFile.loadChapter(0);
    expect(fromFile.chapterLayoutCount, 1);
    expect(_pageShape(refreshedPages), _pageShape(bytePages));
  });

  test('固定页能力来自真实扩展元数据并选择可见单图布局', () async {
    final bytes = _fixedBook();
    final file = await _writeBook(bytes);
    const opener = EpubFormatOpener();
    const options = ReaderOpenOptions(contentWidth: 300, contentHeight: 420);
    final fromBytes = _track(await opener.openBytes(bytes, options: options));
    final fromFile = _track(await opener.openFile(file, options: options));
    final bytePages = await fromBytes.loadChapter(0);
    final filePages = await fromFile.loadChapter(0);
    _expectFixedPage(fromBytes, bytePages);
    _expectFixedPage(fromFile, filePages);
    expect(_pageShape(filePages), _pageShape(bytePages));
  });

  for (final verifyCrc in <bool?>[null, true, false]) {
    test('CRC 配置 $verifyCrc 保留字节和文件入口各自语义', () async {
      const probePath = 'OEBPS/crc-probe.bin';
      final probe = utf8.encode('保留内容，只破坏 CRC');
      final bytes = _wrongCrc(
        buildCssChapterBook(
          body: '<p>CRC 默认值验证。</p>',
          binaryFiles: {probePath: probe},
        ),
        probePath,
      );
      final file = await _writeBook(bytes);
      final opener = EpubFormatOpener(verifyCrc: verifyCrc);
      final fromBytes = _track(await opener.openBytes(bytes));
      final fromFile = _track(await opener.openFile(file));
      _expectCrcResult(fromBytes, probePath, probe, verifyCrc ?? true);
      _expectCrcResult(fromFile, probePath, probe, verifyCrc ?? false);
      expect(await fromBytes.loadChapter(0), isNotEmpty);
      expect(await fromFile.loadChapter(0), isNotEmpty);
    });
  }
}

Uint8List _textBook() => buildCssChapterBook(
  body: List.generate(
    16,
    (index) => '<p id="p$index">第 $index 段。${'统一入口的中文 English 正文。' * 8}</p>',
  ).join(),
  css: 'body,p { margin:0; padding:0; }',
);

Uint8List _fixedBook() => buildCssChapterBook(
  body:
      '<p style="display:none">不参与固定页判定的隐藏正文。</p>'
      '<img id="page" src="../Images/page.png" width="80" height="100"/>',
  css: 'body { margin:0; }',
  binaryFiles: {
    'OEBPS/Images/page.png': base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
    ),
    DuokanExtensionParser.path: utf8.encode(
      '<duokan-extension version="1.0"><display-options>'
      '<layout>fixed-page</layout><option name="page-width">1200</option>'
      '<option name="page-height">1600</option>'
      '</display-options></duokan-extension>',
    ),
  },
);

Future<File> _writeBook(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('reader-opener-');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/book.epub').writeAsBytes(bytes);
}

EpubChapterSource _track(EpubChapterSource source) {
  addTearDown(() async {
    final ReaderPublicationSource publication = source;
    publication.close();
    await source.preparationsStopped;
  });
  return source;
}

void _expectCustomLayout(
  EpubChapterSource source,
  List<PageContent> pages,
  ComputedStyle style,
) {
  expect(source.baseContentWidth, 240);
  expect(source.baseContentHeight, 180);
  expect(source.baseStyle, same(style));
  expect(source.trimTextEdges, isFalse);
  expect(pages, isNotEmpty);
  for (final page in pages) {
    expect(page.pageHeight, 180);
    for (final slice in page.slices) {
      expect(slice.block.style?.fontSize, 19);
      expect(slice.block.layout.maxWidth, 240);
      expect(slice.textTopTrim, 0);
      expect(slice.textBottomTrim, 0);
    }
  }
}

void _expectFixedPage(EpubChapterSource source, List<PageContent> pages) {
  expect(source.document.extensionConfig.sourceFound, isTrue);
  expect(source.document.extensionConfig.aspectRatio, 0.75);
  expect(source.layout, ReaderContentLayout.fixedPages);
  expect(pages, hasLength(1));
  final block = pages.single.slices.single.block;
  expect(block.layout.width, 300);
  expect(block.layout.height, 420);
  expect(block.style?.backgroundImage, 'OEBPS/Images/page.png');
  expect(
    [block.bleedLeft, block.bleedRight, block.bleedTop, block.bleedBottom],
    [true, true, true, true],
  );
  final imageCfi = source.document
      .parseDocument(0)
      .elementById('page')!
      .cfi
      .serialize();
  expect(block.startCfi, imageCfi);
  expect(source.cfiForReadingPercent(0.5), imageCfi);
}

List<Map<String, Object?>> _pageShape(List<PageContent> pages) => [
  for (final page in pages)
    {
      'spineIndex': page.spineIndex,
      'pageIndex': page.pageIndex,
      'usedHeight': page.usedHeight,
      'pageHeight': page.pageHeight,
      'topPadding': page.topPadding,
      'slices': [
        for (final slice in page.slices)
          {
            'text': slice.block.layout.text,
            'startCfi': slice.block.startCfi,
            'endCfi': slice.block.endCfi,
            'startLine': slice.startLine,
            'endLine': slice.endLine,
            'height': slice.height,
            'style': slice.block.style?.values,
            'lines': [
              for (final line in slice.lines)
                [line.start, line.end, line.top, line.height, line.width],
            ],
          },
      ],
    },
];

void _expectCrcResult(
  EpubChapterSource source,
  String path,
  List<int> bytes,
  bool verify,
) {
  final archive = source.document.archive;
  expect(archive.readBytes(path), verify ? isNull : bytes);
  expect(
    archive.diagnostics.any(
      (message) =>
          message.startsWith('E_ZIP_ENTRY_TRUNCATED') && message.contains(path),
    ),
    verify,
  );
}

Uint8List _wrongCrc(Uint8List original, String path) {
  final bytes = Uint8List.fromList(original);
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset + 46 <= bytes.length; offset += 1) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
    final nameLength = data.getUint16(offset + 28, Endian.little);
    if (offset + 46 + nameLength > bytes.length) continue;
    final name = utf8.decode(
      bytes.sublist(offset + 46, offset + 46 + nameLength),
      allowMalformed: true,
    );
    if (name != path) continue;
    final localOffset = data.getUint32(offset + 42, Endian.little);
    final wrongCrc = data.getUint32(offset + 16, Endian.little) ^ 1;
    data.setUint32(offset + 16, wrongCrc, Endian.little);
    data.setUint32(localOffset + 14, wrongCrc, Endian.little);
    return bytes;
  }
  throw StateError('测试归档缺少 CRC 样本条目：$path');
}
