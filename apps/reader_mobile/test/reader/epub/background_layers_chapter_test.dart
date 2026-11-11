import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/css_chapter_book.dart';
import '../../support/reader_pump.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0xFF0000FF);
const _redUrl = 'OEBPS/Images/red.png';
const _blueUrl = 'OEBPS/Images/blue.png';
const _pageSize = Size(200, 120);
const _textCss =
    'body, p { margin: 0; padding: 0; color: transparent; '
    'font: 16px/1 Ahem; }';
const _layerCss =
    'body { '
    'background-image: url(../Images/red.png), url(../Images/blue.png), '
    'conic-gradient(#00ff00, #00ff00); '
    'background-size: 25% 100%, 25% 100%, 100% 100%; '
    'background-repeat: no-repeat; '
    'background-position-x: 0%, 100%, 0%; background-position-y: 0%; }';

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List _withBodyStyle(Uint8List bytes, String style) {
  final archive = Archive();
  for (final entry in ZipDecoder().decodeBytes(bytes)) {
    if (entry.name != 'OEBPS/Text/c.xhtml') {
      archive.addFile(entry);
      continue;
    }
    final text = utf8
        .decode(entry.content)
        .replaceFirst('<body>', '<body style="$style">');
    final content = utf8.encode(text);
    archive.addFile(ArchiveFile(entry.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Future<EpubChapterSource> _openBook(
  Map<String, List<int>> images, {
  String css = _layerCss,
  String? bodyStyle,
  String? body,
}) async {
  var bytes = buildCssChapterBook(
    body: body ?? List.generate(20, (index) => '<p>正文 $index</p>').join(),
    css: '$_textCss $css',
    binaryFiles: images,
    identifier: 'urn:uuid:background-${css.hashCode}-${bodyStyle.hashCode}',
  );
  if (bodyStyle != null) bytes = _withBodyStyle(bytes, bodyStyle);
  final source = await EpubChapterSource.open(
    bytes,
    contentWidth: _pageSize.width,
    contentHeight: _pageSize.height,
    verifyCrc: false,
  );
  await source.applyOverrides(const ReaderOverrides());
  return source;
}

Future<void> _close(EpubChapterSource source) async {
  source.close();
  await source.preparationsStopped;
}

Future<ByteData> _paint(PageContent page, DecodedImageCache cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: cache.lookup)
      .paint(Canvas(recorder), page, pageSize: _pageSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 120);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Color _pixel(ByteData data, int x, int y) {
  final offset = (y * 200 + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, List<int>> images;
  setUpAll(() async {
    images = {_redUrl: await _png(_red), _blueUrl: await _png(_blue)};
  });

  test('真实 EPUB 多背景解析包内路径，完整层列表跨页保留并实际绘制', () async {
    final source = await _openBook(images);
    addTearDown(() => _close(source));
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final background = pages.first.background!;
    expect(background.imageUrl, _redUrl, reason: '旧单图入口仍可读取首层图片');
    expect(background.layers.map((layer) => layer.image), [
      _redUrl,
      _blueUrl,
      null,
    ]);
    expect(background.layers.last.gradient, isA<CssConicGradient>());
    expect(() => background.layers.clear(), throwsUnsupportedError);
    final cache = DecodedImageCache(loadBytes: source.readImageBytes);
    addTearDown(cache.clear);
    expect(await cache.prefetch([_redUrl, _blueUrl], displayWidth: 200), 2);
    for (final page in [pages.first, pages.last]) {
      expect(page.background, same(background));
      final pixels = await _paint(page, cache);
      expect(_pixel(pixels, 10, 110), _red);
      expect(_pixel(pixels, 100, 110), _green);
      expect(_pixel(pixels, 190, 110), _blue);
    }
  });

  test('body 内联多背景逐层按章节目录解析，none 层不占用图片资源', () async {
    final source = await _openBook(
      images,
      css: '',
      bodyStyle: 'background-image:none,url(../Images/red.png),url(../Images/blue.png)',
    );
    addTearDown(() => _close(source));
    final page = (await source.loadChapter(0)).first;
    expect(page.background!.layers.map((layer) => layer.image), [
      null,
      _redUrl,
      _blueUrl,
    ]);
    for (final url in [_redUrl, _blueUrl]) {
      expect(await source.readImageBytes(url), orderedEquals(images[url]!));
    }
  });

  test('重复计算的相同背景按值相等，轴单位或平铺变化可区分', () async {
    Future<PageBackground> background(String suffix) async {
      final source = await _openBook(images, css: '$_layerCss $suffix');
      addTearDown(() => _close(source));
      return (await source.loadChapter(0)).first.background!;
    }

    const position = 'body{background-position-x:10px}';
    final first = await background(position);
    final second = await background(position);
    expect(second, isNot(same(first)));
    expect(second, first);
    expect(second.hashCode, first.hashCode);
    expect(await background('body{background-position-x:10%}'), isNot(first));
    expect(
      await background('$position body{background-repeat:round space}'),
      isNot(first),
    );
  });

  for (final repeat in ['space no-repeat', 'round no-repeat']) {
    test('真实章节 $repeat 与 auto 高度在绘制中生效', () async {
      final source = await _openBook(
        images,
        css:
            'body { background-image: url(../Images/red.png), '
            'conic-gradient(blue, blue); '
            'background-size: 80px auto, cover; '
            'background-repeat: $repeat, no-repeat; '
            'background-position: 50% 100%, 0% 0%; }',
      );
      addTearDown(() => _close(source));
      final cache = DecodedImageCache(loadBytes: source.readImageBytes);
      addTearDown(cache.clear);
      await cache.load(_redUrl, displayWidth: 200);
      final page = (await source.loadChapter(0)).first;
      final pixels = await _paint(page, cache);
      final space = repeat.startsWith('space');
      expect(_pixel(pixels, 10, 45), space ? _red : _blue);
      expect(_pixel(pixels, 100, 110), space ? _blue : _red);
      expect(_pixel(pixels, 190, 110), _red);
    });
  }

  test('只有渐变背景的空章节仍生成可绘制页面', () async {
    final source = await _openBook(
      const {},
      css: 'body { background: conic-gradient(blue, blue); }',
      body: '',
    );
    addTearDown(() => _close(source));
    final page = (await source.loadChapter(0)).single;
    expect(page.background!.imageUrl, isNull);
    expect(page.background!.layers.single.gradient, isA<CssConicGradient>());
    final cache = DecodedImageCache(loadBytes: source.readImageBytes);
    addTearDown(cache.clear);
    final pixels = await _paint(page, cache);
    expect(_pixel(pixels, 10, 110), _blue);
    expect(_pixel(pixels, 190, 10), _blue);
  });

  testWidgets('阅读页自动预取全部整页背景图片并保护当前页面资源', (tester) async {
    final source = await _openBook(images);
    final cache = DecodedImageCache(loadBytes: source.readImageBytes);
    addTearDown(cache.clear);
    addTearDown(source.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: '整页多层背景预取',
          imageCache: cache,
          padding: EdgeInsets.zero,
          overrides: const ReaderOverrides(),
          showPageFooter: false,
          pageTurnMode: PageTurnMode.none,
        ),
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => cache.entryCount == 2,
      description: '整页双图片背景解码',
    );
    expect(cache.lookup(_redUrl), isNotNull);
    expect(cache.lookup(_blueUrl), isNotNull);
    expect(cache.protectedUrls, containsAll([_redUrl, _blueUrl]));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderTask(tester, _close(source));
  });

  test('布局缓存计入新层路径和渐变色标，并按对象身份去重', () {
    final path = '背景图片' * 2000;
    final image = CssBackgroundLayer(image: path);
    const gradient = CssBackgroundLayer(
      gradient: CssConicGradient(
        stops: [
          CssGradientStop(color: _red),
          CssGradientStop(color: _blue),
        ],
      ),
    );
    final single = _backgroundBytes([image]);
    final combined = _backgroundBytes([image, gradient]);
    final shared = _backgroundBytes([image, gradient, image, gradient]);
    expect(single, greaterThan(path.length * 2));
    expect(combined - single, greaterThan(100), reason: '渐变及色标参与容量预算');
    expect(shared - combined, lessThan(128), reason: '共享层仅增加引用槽，不重复累计载荷');
  });
}

int _backgroundBytes(List<CssBackgroundLayer> layers) => CompletedChapterLayout(
  key: '背景容量',
  spineIndex: 0,
  pages: const [],
  blocks: const [],
  fixedBlocks: const [],
  background: PageBackground(layers: layers),
  fontDependency: '',
).estimatedBytes;
