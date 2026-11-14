import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/layout/image_gallery.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/gallery/reader_gallery_controls.dart';
import 'package:reader_ui/image_preview_page.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../../reader_core/test/layout/image_gallery_fixture.dart';

const _timeout = Duration(seconds: 30);
typedef _Fixture = ({_PreparedSource source, DecodedImageCache cache});

/// 直接交接正式 EPUB 的分页结果，控件假时钟内不启动解析或资源 IO。
class _PreparedSource implements ReaderChapterSource {
  const _PreparedSource(this.pages);
  final List<PageContent> pages;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      SynchronousFuture(pages);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = <bool, _Fixture>{};
  setUpAll(() async {
    for (final scaled in [false, true]) {
      fixtures[scaled] = await _prepare(scaled).timeout(_timeout);
    }
  });
  tearDownAll(() {
    for (final fixture in fixtures.values) {
      fixture.cache.clear();
    }
    ChapterLayoutCache.recent.clear();
  });

  for (final scaled in [false, true]) {
    testWidgets('点击正式 EPUB 行内主图打开预览（缩放：$scaled）', (tester) async {
      final fixture = fixtures[scaled]!;
      final session = await _show(tester, fixture);
      final region = galleryRegionsOf(session.page!).single;
      _verifyGeometry(tester, region);
      expect(region.gallery.scale, scaled ? lessThan(1) : 1);
      expect(region.gallery.frames.first.imageUrl, galleryImageUrl);
      expect(fixture.cache.lookup(galleryImageUrl), isNotNull);
      final image = _inlineImageBox(region.gallery.frames.first);
      expect(image.size, const Size(40, 40));
      await _tap(tester, region, _pagePoint(region, image.center));
      expect(find.byType(ImagePreviewPage), findsOneWidget);
      expect(find.text('图片无法加载'), findsNothing);
    }, timeout: const Timeout(_timeout));
  }

  for (final target in ['同行文字', '题注', '图片上外边距', '右侧留白', '帧序号']) {
    testWidgets('缩放的行内画廊点击$target 不打开预览', (tester) async {
      final session = await _show(tester, fixtures[true]!);
      final region = galleryRegionsOf(session.page!).single;
      _verifyGeometry(tester, region);
      final point = _outsideImagePoint(region, target);
      expect(region.rect.contains(point), isTrue);
      await _tap(tester, region, point);
      expect(find.byType(ImagePreviewPage), findsNothing);
      expect(session.page!.pageIndex, 0);
    }, timeout: const Timeout(_timeout));
  }
}

Future<_Fixture> _prepare(bool scaled) async {
  final source = await EpubChapterSource.open(
    inlineGalleryEpub(
      extraStyle: scaled ? '.duokan-image-gallery { height: 72px; }' : '',
    ),
    contentWidth: 240,
    contentHeight: 320,
  );
  DecodedImageCache? cache;
  try {
    final pages = await source.loadChapter(0);
    final bytes = (await source.readImageBytes(galleryImageUrl))!;
    cache = DecodedImageCache(
      loadBytes: (url) =>
          SynchronousFuture(url == galleryImageUrl ? bytes : null),
    );
    expect(await cache.load(galleryImageUrl, displayWidth: 40), isNotNull);
    return (source: _PreparedSource(List.unmodifiable(pages)), cache: cache);
  } catch (_) {
    cache?.clear();
    rethrow;
  } finally {
    source.close();
    await source.preparationsStopped.timeout(const Duration(seconds: 5));
    ChapterLayoutCache.recent.clear();
  }
}

Future<ReaderSession> _show(WidgetTester tester, _Fixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(280, 380));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
  });
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        source: fixture.source,
        store: MemoryReaderProgressStore(),
        bookId: '行内画廊',
        // 与预排版使用相同的作者样式，默认阅读设置不能另行覆盖版心。
        overrides: const ReaderOverrides(),
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        showPageFooter: false,
        pageTurnMode: PageTurnMode.none,
        imageCache: fixture.cache,
        onSessionReady: (value) => session = value,
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 20),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
  return session;
}

void _verifyGeometry(WidgetTester tester, PageGalleryRegion region) {
  final reader = find.byType(ReaderView);
  final controls = find.byType(ReaderGalleryControls);
  expect(tester.getSize(reader), const Size(280, 380));
  expect(tester.widget<ReaderGalleryControls>(controls).index, 0);
  expect(
    tester.getRect(controls),
    region.rect.shift(tester.getTopLeft(reader) + const Offset(20, 30)),
    reason: '实际画廊控件与正式版心坐标一致',
  );
  final image = _inlineImageBox(region.gallery.frames.first);
  expect(
    galleryImageRectOf(
      region.gallery,
      0,
      contentOrigin: region.rect.topLeft,
      containingWidth: 240,
    ),
    rectMoreOrLessEquals(
      Rect.fromPoints(
        _pagePoint(region, image.topLeft),
        _pagePoint(region, image.bottomRight),
      ),
    ),
    reason: '正式行盒的主图坐标与命中入口一致',
  );
}

Rect _inlineImageBox(PageGalleryFrame frame) {
  // 取正式 LineBox 的绘制位置，点击点不依赖待测的 galleryImageRectOf。
  final box = TextHitTester.lineBoxes(frame.content)
      .firstWhere((box) => box.slice.block.inlineImages.isNotEmpty);
  final image = box.slice.block.inlineImages.first;
  final line = box.slice.block.layout.lines[box.lineIndex];
  final placement = line.inlineBoxes.singleWhere(
    (box) => box.offset == image.offset && box.spec.replacesPlaceholder,
  );
  return Rect.fromLTWH(
    box.rect.left + placement.left,
    (box.textTop ?? box.rect.top) +
        placement.topIn(line.baseline - line.top) +
        placement.spec.marginTop,
    placement.width,
    placement.height,
  );
}

Offset _pagePoint(PageGalleryRegion region, Offset framePoint) {
  final gallery = region.gallery;
  return Offset(
    region.rect.left +
        gallery.width * (1 - gallery.scale) / 2 +
        (framePoint.dx - gallery.left) * gallery.scale,
    region.rect.top + framePoint.dy * gallery.scale,
  );
}

Offset _outsideImagePoint(PageGalleryRegion region, String target) {
  final frame = region.gallery.frames.first;
  final lines = TextHitTester.lineBoxes(frame.content);
  final image = _inlineImageBox(frame);
  return switch (target) {
    '同行文字' => _pagePoint(
      region,
      Offset(
        lines.firstWhere((line) => line.text.contains('图一：')).rect.left + 2,
        image.center.dy,
      ),
    ),
    '题注' => _pagePoint(
      region,
      lines.firstWhere((line) => line.text.trim() == '图一题注').rect.center,
    ),
    '图片上外边距' => _pagePoint(region, image.topCenter - const Offset(0, 2)),
    '右侧留白' => Offset(
      region.rect.right - 2,
      _pagePoint(region, image.center).dy,
    ),
    '帧序号' => Offset(
      region.rect.center.dx,
      region.rect.bottom - region.gallery.indicatorExtent / 2,
    ),
    _ => throw ArgumentError.value(target),
  };
}

Future<void> _tap(
  WidgetTester tester,
  PageGalleryRegion region,
  Offset pagePoint,
) async {
  final origin = tester.getTopLeft(find.byType(ReaderGalleryControls));
  await tester.tapAt(origin + pagePoint - region.rect.topLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
