import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/image_gallery.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/gallery/reader_gallery_controls.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

TextLayoutResult _box(double height) => TextLayoutResult(
  text: '',
  lines: [
    LineBox(
      start: 0,
      end: 0,
      top: 0,
      height: height,
      baseline: height,
      width: 200,
    ),
  ],
  width: 200,
  height: height,
  maxWidth: 200,
);

PageGalleryFrame _frame(int spine, int index) {
  final cfi = 'epubcfi(/6/${spine * 2 + 2}!/4/2/${index * 2 + 2})';
  final url = 'image-$spine-$index';
  final block = PageBlock.styled(
    layout: _box(120),
    style: ComputedStyle({
      'width': '200px',
      'margin-left': '20px',
      'background-image': 'url($url)',
      'background-size': '100% 100%',
    }),
    containingWidth: 300,
    startCfi: cfi,
  );
  return PageGalleryFrame(
    cfi: cfi,
    imageUrl: url,
    content: Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single,
  );
}

PageContent _page(int spine) {
  final gallery = PageGallery(
    cfi: 'epubcfi(/6/${spine * 2 + 2}!/4/2)',
    frames: List.generate(spine == 1 ? 1 : 3, (index) => _frame(spine, index)),
    left: 20,
    width: 200,
    height: 144,
  );
  final block = PageBlock.styled(
    layout: _box(144),
    style: ComputedStyle({'width': '200px', 'margin-left': '20px'}),
    containingWidth: 300,
    startCfi: gallery.cfi,
    gallery: gallery,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: 0,
    slices: [
      PageBlockSlice(block: block, startLine: 0, endLine: 1, height: 144),
    ],
    usedHeight: 144,
    pageHeight: 400,
    topPadding: 20,
    background: PageBackground(
      imageUrl: 'background-$spine',
      size: const CssBackgroundSize.keyword(CssBackgroundSizeMode.cover),
    ),
  );
}

class _Source implements ReaderChapterSource {
  final pages = List.generate(3, _page);

  @override
  int get chapterCount => pages.length;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    pages[spineIndex],
  ];
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _advance(WidgetTester tester) async {
  for (var frame = 0; frame < 24; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<(ReaderSession, DecodedImageCache)> _show(
  WidgetTester tester,
  GlobalKey key, {
  PageTurnMode mode = PageTurnMode.cover,
  Future<void> Function(String url)? beforeLoad,
  ValueNotifier<Color>? background,
}) async {
  final assets = (await tester.runAsync(
    () async => [
      await _png(const Color(0xff00dd44)),
      await _png(const Color(0xff0033aa)),
    ],
  ))!;
  // 四张 RGBA 单像素图的预算，只容纳当前页和一个目标页的必需资源。
  final cache = DecodedImageCache(
    maxBytes: 16,
    loadBytes: (url) async {
      await beforeLoad?.call(url);
      return assets[url.startsWith('image-') ? 0 : 1];
    },
  );
  addTearDown(cache.clear);
  final source = _Source();
  final store = MemoryReaderProgressStore();
  await store.save('图片翻页回归', const ReaderProgress(spineIndex: 1, pageIndex: 0));
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: ValueListenableBuilder<Color>(
          valueListenable:
              background ?? const AlwaysStoppedAnimation(Colors.white),
          builder: (_, color, _) => ReaderPage(
            source: source,
            store: store,
            bookId: '图片翻页回归',
            imageCache: cache,
            background: color,
            pageTurnMode: mode,
            showPageFooter: false,
            onSessionReady: (value) => session = value,
          ),
        ),
      ),
    ),
  );
  await _advance(tester);
  return (session, cache);
}

void _expectAssets(DecodedImageCache cache, int spine) {
  expect(cache.lookup('image-$spine-0'), isNotNull, reason: '当前主图必须保留');
  expect(cache.lookup('background-$spine'), isNotNull, reason: '当前整页背景必须保留');
  expect(cache.byteCount, lessThanOrEqualTo(cache.maxBytes));
}

Future<void> _expectPaper(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  final pixels = (await tester.runAsync(image.toByteData))!.buffer
      .asUint8List();
  image.dispose();
  final colors = <int>{};
  for (var offset = 0; offset < pixels.length; offset += 4) {
    colors.add(
      pixels[offset] << 16 | pixels[offset + 1] << 8 | pixels[offset + 2],
    );
  }
  expect(colors, contains(0x00dd44), reason: '实际纸面必须显示主图');
  expect(colors, contains(0x0033aa), reason: '实际纸面必须显示整页背景');
}

void main() {
  testWidgets('相邻画廊预热和缓存快照往返不丢当前主图或背景', (tester) async {
    final key = GlobalKey();
    final (session, cache) = await _show(tester, key);
    _expectAssets(cache, 1);
    await _expectPaper(tester, key);
    final view = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    expect(view.snapshotCount, 3);
    view.controller.request(true);
    await _advance(tester);
    expect(session.page!.spineIndex, 2);
    _expectAssets(cache, 2);
    await _expectPaper(tester, key);
    view.controller.request(false);
    await _advance(tester);
    expect(session.page!.spineIndex, 1);
    _expectAssets(cache, 1);
    await _expectPaper(tester, key);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
  ]) {
    testWidgets('画廊原图被淘汰后${mode.label}不等解码且落页不闪白', (tester) async {
      final key = GlobalKey();
      final gate = Completer<void>();
      final background = ValueNotifier<Color>(Colors.white);
      var blocked = false;
      addTearDown(background.dispose);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final (session, cache) = await _show(
        tester,
        key,
        mode: mode,
        beforeLoad: (_) => blocked ? gate.future : Future<void>.value(),
        background: background,
      );
      final view = tester.state<PageTurnViewState>(find.byType(PageTurnView));
      expect(view.snapshotCount, 3);
      // 四个无关资源挤出画廊主图与背景，保留已经生成的完整页面快照。
      cache.protectedUrls = const {};
      await tester.runAsync(
        () => cache.prefetch([
          'extra-0',
          'extra-1',
          'extra-2',
          'extra-3',
        ], displayWidth: 1),
      );
      expect(cache.lookup('image-2-0'), isNull);
      blocked = true;
      view.controller.request(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(view.controller.phase, PageTurnPhase.settling);
      await tester.pumpAndSettle();
      expect(session.page!.spineIndex, 2);
      expect(
        find.byKey(const ValueKey('page-turn-static-snapshot')),
        findsOneWidget,
      );
      await _expectPaper(tester, key);

      // 宿主绘制版本在原图重解码期间刷新，快照仍应接住完整背景与主图。
      background.value = const Color(0xffdddddd);
      await tester.pump();
      await _expectPaper(tester, key);
      gate.complete();
      await _advance(tester);
      _expectAssets(cache, 2);
      await _expectPaper(tester, key);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('画廊切帧后正文往返保留选择且不在动画中绘制静态画廊', (tester) async {
    final key = GlobalKey();
    final (session, _) = await _show(
      tester,
      key,
      mode: PageTurnMode.simulationBessel,
    );
    final view = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    view.controller.request(true);
    await _advance(tester);
    final gallery = tester.widget<ReaderGalleryControls>(
      find.byType(ReaderGalleryControls),
    );
    gallery.onChanged(1);
    await _advance(tester);
    expect(
      tester
          .widget<ReaderGalleryControls>(find.byType(ReaderGalleryControls))
          .index,
      1,
    );
    for (final next in [false, true]) {
      view.controller.request(next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byType(ReaderGalleryControls),
        findsNothing,
        reason: '仿真动画只合成快照，静态画廊不再重复绘制',
      );
      await _advance(tester);
    }
    expect(session.page!.spineIndex, 2);
    expect(
      tester
          .widget<ReaderGalleryControls>(find.byType(ReaderGalleryControls))
          .index,
      1,
    );
    await _expectPaper(tester, key);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
