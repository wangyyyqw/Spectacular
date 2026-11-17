import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

const _thumbnailWidth = 68.8;
const _thumbnailColors = [
  Color(0xffcd1234),
  Color(0xff1256cd),
  Color(0xff12cd56),
  Color(0xffac5621),
  Color(0xff5612ac),
  Color(0xff21ac56),
  Color(0xffac2156),
  Color(0xff2156ac),
];

class _StaticSource implements ReaderChapterSource {
  _StaticSource(this.page);
  final PageContent page;
  @override
  int get chapterCount => 1;
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [page];
}

Future<Uint8List> _png(Color color, {int width = 3, int height = 3}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

PageBlock _imagePayload(String url, double width, double height) => PageBlock(
  layout: TextLayoutResult(
    text: '',
    lines: const [],
    width: width,
    height: height,
    maxWidth: width,
  ),
  style: ComputedStyle({
    'width': '${width}px',
    'background-image': 'url($url)',
    'background-size': '100% 100%',
    'background-repeat': 'no-repeat',
  }),
);

PageBlock _inlineImageBlock(
  List<InlineBoxSpec> boxes,
  String text,
  double width,
) {
  final style = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'line-height': '1',
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: width,
      inlineBoxes: boxes,
    ),
    style: style,
    containingWidth: width,
    inlineImages: [
      for (final box in boxes)
        if ((box.payload as PageBlock).style!.backgroundImage != null)
          InlineImageSpec(
            offset: box.offset,
            url: (box.payload as PageBlock).style!.backgroundImage!,
          ),
    ],
  );
}

TextLayoutResult _boxLayout(double width, double height) => TextLayoutResult(
  text: '',
  lines: [
    LineBox(
      start: 0,
      end: 0,
      top: 0,
      height: height,
      baseline: height,
      width: width,
    ),
  ],
  width: width,
  height: height,
  maxWidth: width,
);

PageBlock _replacedImageBlock(String url) => PageBlock.styled(
  layout: _boxLayout(344, 90),
  style: _imagePayload(url, 140, 90).style!,
  containingWidth: 344,
  isReplaced: true,
);

PageBlock _cellImageBlock(String url) => PageBlock(
  layout: _boxLayout(344, 100),
  style: ComputedStyle({}),
  table: TableRenderSpec(
    cells: [
      TableCellRender(
        row: 0,
        rect: const Rect.fromLTWH(0, 0, 120, 100),
        layout: _boxLayout(120, 100),
        style: _imagePayload(url, 120, 100).style!,
      ),
    ],
    columnXs: const [0, 120],
    rowYs: const [0, 100],
    tableWidth: 120,
    flex: true,
  ),
);

PageBlock _containerImageBlock(String url) => PageBlock(
  layout: _boxLayout(344, 50),
  style: ComputedStyle({}),
  containers: [
    PageContainerFragment(
      container: PageContainer(
        style: _imagePayload(url, 100, 50).style!,
        left: 0,
        width: 100,
      ),
      startsHere: true,
      endsHere: true,
    ),
  ],
);

Future<Map<String, Uint8List>> _thumbnailAssets() async => {
  for (var index = 0; index < _thumbnailColors.length; index++)
    'image-$index.png': await _png(
      _thumbnailColors[index],
      width: 1200,
      height: 1800,
    ),
};

PageContent _thumbnailPage() {
  final boxes = [
    for (var index = 0; index < _thumbnailColors.length; index++)
      InlineBoxSpec(
        offset: index < 4 ? index : index + 1,
        width: _thumbnailWidth,
        height: _thumbnailWidth * 1.5,
        replacesPlaceholder: true,
        marginLeft: 3,
        marginRight: 3,
        payload: _imagePayload(
          'image-$index.png',
          _thumbnailWidth,
          _thumbnailWidth * 1.5,
        ),
      ),
  ];
  final block = _inlineImageBlock(
    boxes,
    '\uFFFC\uFFFC\uFFFC\uFFFC\n\uFFFC\uFFFC\uFFFC\uFFFC',
    344,
  );
  return Paginator(pageHeight: 600)
      .measureChapter(blocks: [block])
      .pages
      .single;
}

PageBlock _sharedInlineBlock() {
  final payload = _imagePayload('shared.png', 40, 60);
  final nested = _inlineImageBlock(
    [
      InlineBoxSpec(
        offset: 0,
        width: 160,
        height: 240,
        replacesPlaceholder: true,
        payload: payload,
      ),
    ],
    '\uFFFC',
    180,
  );
  return _inlineImageBlock(
    [
      for (final (index, width) in [40.0, 180.0, 24.0].indexed)
        InlineBoxSpec(
          offset: index,
          width: width,
          height: index == 1 ? 240 : width * 1.5,
          replacesPlaceholder: true,
          payload: index == 1 ? nested : payload,
        ),
    ],
    '\uFFFC\uFFFC\uFFFC',
    344,
  );
}

PageBlock _ordinaryBackgroundBlock() {
  final style = ComputedStyle({
    'font-size': '16px',
    'background-image': 'url(unknown.png)',
    'background-size': '100% 100%',
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: '普通背景', style: style, maxWidth: 344),
    style: style,
    containingWidth: 344,
  );
}

PageContent _overflowInlineImagePage() {
  final style = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'line-height': '180px',
    'width': '80px',
    'overflow': 'visible',
  });
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(text: '\uFFFC', style: style, maxWidth: 80),
    style: style,
    containingWidth: 344,
    inlineImages: const [
      InlineImageSpec(offset: 0, url: 'overflow.png', width: 160, height: 60),
    ],
  );
  return Paginator(pageHeight: 600)
      .measureChapter(blocks: [block])
      .pages
      .single;
}

PageContent _sharedImagePage() => Paginator(pageHeight: 600)
    .measureChapter(
      blocks: [
        _sharedInlineBlock(),
        _replacedImageBlock('shared.png'),
        _cellImageBlock('shared.png'),
        _containerImageBlock('shared.png'),
        _ordinaryBackgroundBlock(),
      ],
    )
    .pages
    .single;

Future<void> _showImagePage(
  WidgetTester tester,
  PageContent page,
  DecodedImageCache cache,
  GlobalKey key, {
  required int expectedImages,
}) async {
  tester.view.physicalSize = const Size(900, 1500);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(cache.clear);
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: ReaderPage(
          source: _StaticSource(page),
          store: MemoryReaderProgressStore(),
          bookId: '图片尺寸回归',
          imageCache: cache,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          overrides: const ReaderOverrides(
            padding: CssEdges(top: 0, right: 8, bottom: 0, left: 8),
          ),
          showPageFooter: false,
          pageTurnMode: PageTurnMode.none,
        ),
      ),
    ),
  );
  await _waitForPageImages(tester, cache, expectedImages);
}

Future<void> _waitForPageImages(
  WidgetTester tester,
  DecodedImageCache cache,
  int expectedImages,
) async {
  for (
    var frame = 0;
    frame < 50 && cache.entryCount < expectedImages;
    frame++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}

Future<Uint8List> _pagePixels(WidgetTester tester, GlobalKey key) async {
  final image =
      (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImageSync();
  try {
    return (await tester.runAsync(image.toByteData))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

int _colorPixels(Uint8List pixels, Color color) {
  final rgb = color.toARGB32() & 0xffffff;
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if ((pixels[i] << 16 | pixels[i + 1] << 8 | pixels[i + 2]) == rgb) {
      count++;
    }
  }
  return count;
}

void main() {
  testWidgets('低预算阅读页按行内盒宽解码并绘制两排全部缩略图', (tester) async {
    final assets = (await tester.runAsync(_thumbnailAssets))!;
    // 按整页宽解码只能存下一张；实际缩略图的八张解码图均能留在预算内。
    final cache = DecodedImageCache(
      loadBytes: (url) async => assets[url],
      maxBytes: 6 << 20,
    );
    final key = GlobalKey();
    await _showImagePage(
      tester,
      _thumbnailPage(),
      cache,
      key,
      expectedImages: _thumbnailColors.length,
    );
    expect(cache.protectedUrls, assets.keys.toSet());
    expect(cache.entryCount, _thumbnailColors.length);
    expect(cache.byteCount, lessThanOrEqualTo(cache.maxBytes));
    final pixels = await _pagePixels(tester, key);
    for (var index = 0; index < _thumbnailColors.length; index++) {
      expect(
        cache.lookup('image-$index.png')?.width,
        (_thumbnailWidth * tester.view.devicePixelRatio).ceil(),
      );
      expect(
        _colorPixels(pixels, _thumbnailColors[index]),
        greaterThan(100),
        reason: '第 ${index + 1} 张缩略图应绘制真实像素',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('嵌套盒和容器共用图片时按最大用途解码，普通背景仍用页宽', (tester) async {
    const color = Color(0xffcd5634);
    final bytes = (await tester.runAsync(
      () => _png(color, width: 1200, height: 1800),
    ))!;
    final cache = DecodedImageCache(loadBytes: (_) async => bytes);
    final key = GlobalKey();
    await _showImagePage(
      tester,
      _sharedImagePage(),
      cache,
      key,
      expectedImages: 2,
    );
    expect(cache.entryCount, 2);
    expect(cache.lookup('shared.png')?.width, 400);
    expect(cache.lookup('unknown.png')?.width, 860);
    expect(
      _colorPixels(await _pagePixels(tester, key), color),
      greaterThan(30000),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('遗留行内图片溢出窄父盒时按实际图片宽度解码', (tester) async {
    const color = Color(0xffcd5634);
    final bytes = (await tester.runAsync(
      () => _png(color, width: 1200, height: 450),
    ))!;
    final cache = DecodedImageCache(loadBytes: (_) async => bytes);
    final key = GlobalKey();
    await _showImagePage(
      tester,
      _overflowInlineImagePage(),
      cache,
      key,
      expectedImages: 1,
    );
    expect(cache.lookup('overflow.png')?.width, 400);
    expect(_colorPixels(await _pagePixels(tester, key), color), 160 * 60);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('阅读页加载并绘制行背景图，解码宽度使用完整行宽', (tester) async {
    const color = Color(0xffcd5634);
    final bytes = (await tester.runAsync(
      () => _png(color, width: 1200, height: 600),
    ))!;
    final rowBackground = TableRowBackground(
      rect: const Rect.fromLTWH(0, 0, 300, 60),
      style: _imagePayload('row.png', 300, 60).style!,
    );
    final page = Paginator(pageHeight: 600)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: _boxLayout(300, 60),
              style: ComputedStyle({}),
              table: TableRenderSpec(
                cells: [
                  for (var column = 0; column < 2; column++)
                    TableCellRender(
                      row: 0,
                      rect: Rect.fromLTWH(column * 150, 0, 150, 60),
                      layout: _boxLayout(150, 60),
                      style: ComputedStyle({}),
                      rowBackground: rowBackground,
                    ),
                ],
                columnXs: const [0, 150, 300],
                rowYs: const [0, 60],
                tableWidth: 300,
              ),
            ),
          ],
        )
        .pages
        .single;
    final cache = DecodedImageCache(
      loadBytes: (url) async => url == 'row.png' ? bytes : null,
    );
    final key = GlobalKey();
    await _showImagePage(tester, page, cache, key, expectedImages: 1);
    expect(cache.protectedUrls, {'row.png'});
    expect(
      cache.lookup('row.png')?.width,
      (300 * tester.view.devicePixelRatio).ceil(),
    );
    expect(
      _colorPixels(await _pagePixels(tester, key), color),
      greaterThan(17000),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('阅读页应加载边框图及所有背景层', (tester) async {
    final style = ComputedStyle({
      'font-size': '16px',
      'border': '10px solid transparent',
      'border-image': 'url(border.png) 10 stretch',
      'background-image': 'url(front.png), url(back.png)',
    });
    expect(style.borderImage?.url, 'border.png');
    expect(style.backgroundLayers, hasLength(2));
    final layout = TextLayoutEngine.layout(
      text: '图片预取审计',
      style: style,
      maxWidth: 300,
    );
    final page = Paginator(pageHeight: 600)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 300,
            ),
          ],
        )
        .pages
        .single;
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    addTearDown(cache.clear);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _StaticSource(page),
          store: MemoryReaderProgressStore(),
          bookId: '图片预取',
          imageCache: cache,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requested, containsAll(['front.png', 'back.png', 'border.png']));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('实际阅读页绘制全部背景层和边框图像素', (tester) async {
    const colors = <String, Color>{
      'front.png': Color(0xffcd1234),
      'back.png': Color(0xff1256cd),
      'border.png': Color(0xff12cd56),
    };
    final assets = (await tester.runAsync(
      () async => <String, Uint8List>{
        for (final entry in colors.entries) entry.key: await _png(entry.value),
      },
    ))!;
    final style = ComputedStyle({
      'font-size': '16px',
      'border': '10px solid transparent',
      'border-image': 'url(border.png) 1 stretch',
      'background-image': 'url(front.png), url(back.png)',
      'background-size': '20px 20px, 100% 100%',
      'background-repeat': 'no-repeat',
    });
    final page = Paginator(pageHeight: 600)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: TextLayoutEngine.layout(
                text: '背景层与边框图',
                style: style,
                maxWidth: 300,
              ),
              style: style,
              containingWidth: 300,
            ),
          ],
        )
        .pages
        .single;
    final cache = DecodedImageCache(loadBytes: (url) async => assets[url]);
    addTearDown(cache.clear);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: ReaderPage(
            source: _StaticSource(page),
            store: MemoryReaderProgressStore(),
            bookId: '图片绘制',
            imageCache: cache,
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final url in assets.keys) {
        await cache.load(url, displayWidth: 300);
      }
    });
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final image =
        (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImageSync();
    final pixels = (await tester.runAsync(image.toByteData))!.buffer
        .asUint8List();
    image.dispose();
    for (final entry in colors.entries) {
      final rgb = entry.value.toARGB32() & 0xffffff;
      var count = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if ((pixels[i] << 16 | pixels[i + 1] << 8 | pixels[i + 2]) == rgb) {
          count++;
        }
      }
      expect(count, greaterThan(20), reason: '${entry.key} 应进入真实绘制');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
