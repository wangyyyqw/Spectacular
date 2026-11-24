import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/editing/book_editor_preview.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';
import 'package:reader_ui/theme/reader_margins.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Future<({ReaderSession session, EpubChapterSource source})> _openPreview(
  WidgetTester tester, {
  ReaderSettings? settings,
  ValueChanged<ReaderEditTarget>? onEdit,
  ValueChanged<ReaderEditTarget>? onLocation,
}) async {
  final bytes = buildTestEpub(
    paragraphs: ['目标段落', ...List.generate(24, (index) => '后续正文第 $index 段。')],
  );
  final source = (await tester.runAsync(() => EpubChapterSource.open(bytes)))!;
  addTearDown(source.close);
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: BookEditorPreview(
        source: source,
        revision: 1,
        settings: settings,
        onEditTarget: onEdit ?? (_) {},
        onLocationChanged: onLocation,
        onSessionReady: (value) => session = value,
      ),
    ),
  );
  await pumpReaderUntilComplete(
    tester,
    () => session.page != null && !session.loading,
  );
  await tester.pumpAndSettle();
  return (session: session, source: source);
}

Rect _checkPhone(WidgetTester tester, Size window) {
  final reader = find.byType(ReaderPage);
  final frame = tester.getRect(
    find.byKey(const ValueKey('editor-phone-frame')),
  );
  final screen = tester.getRect(reader);
  final media = MediaQuery.of(tester.element(reader));
  expect(tester.getSize(reader), const Size(360, 800));
  expect(media.size, const Size(360, 800));
  expect(media.size * media.devicePixelRatio, const Size(1080, 2400));
  expect(media.viewPadding, const EdgeInsets.only(top: 24, bottom: 16));
  expect(media.padding, media.viewPadding);
  expect(media.viewInsets, EdgeInsets.zero);
  expect(media.systemGestureInsets, EdgeInsets.zero);
  expect(screen.width / screen.height, closeTo(1080 / 2400, 1e-6));
  expect(frame.intersect(Offset.zero & window), frame);
  expect(frame.deflate(1).intersect(screen), screen);
  return frame;
}

void main() {
  testWidgets('窄栏与矮窗只缩放整机，切换宿主尺寸不改变实际分页', (tester) async {
    const narrow = Size(210, 920);
    const short = Size(920, 240);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = narrow
      ..viewPadding = const FakeViewPadding(top: 58, bottom: 35)
      ..padding = const FakeViewPadding(top: 58)
      ..viewInsets = const FakeViewPadding(bottom: 70)
      ..systemGestureInsets = const FakeViewPadding(left: 10);
    addTearDown(tester.view.reset);
    final (:session, :source) = await _openPreview(tester);
    final generation = session.generation;
    final firstPage = session.page;
    final tallFrame = _checkPhone(tester, narrow);
    expect(source.contentWidth, 320);
    expect(source.contentHeight, 728 - PageFurniture.reservedHeight);
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.showPageFooter, isTrue);
    expect(reader.cornerInfo, ReaderCornerInfo.defaults);
    expect(find.byType(ReaderPageFooter), findsOneWidget);

    tester.view.physicalSize = short;
    await tester.pumpAndSettle();
    final shortFrame = _checkPhone(tester, short);
    expect(shortFrame.height, lessThan(tallFrame.height));
    expect(shortFrame.width, lessThan(tallFrame.width));
    expect(
      shortFrame.size.aspectRatio,
      closeTo(tallFrame.size.aspectRatio, 1e-6),
    );
    expect(source.contentWidth, 320);
    expect(source.contentHeight, 728 - PageFurniture.reservedHeight);
    expect(session.generation, generation);
    expect(session.page, same(firstPage));
  });

  testWidgets('正式阅读设置生效，缩小后的正文点击命中对应段落', (tester) async {
    const settings = ReaderSettings(
      fontSize: 22,
      themeId: 'sepia',
      backgroundImageOpacity: 0.6,
      margins: ReaderMargins(
        left: 28,
        right: 16,
        topOuter: 0,
        topInner: 12,
        bottomInner: 8,
        bottomOuter: 0,
      ),
    );
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(700, 380);
    addTearDown(tester.view.reset);
    final edits = <ReaderEditTarget>[];
    final (:session, :source) = await _openPreview(
      tester,
      settings: settings,
      onEdit: edits.add,
    );
    expect(source.overrides.fontSize, settings.fontSize);
    expect(source.overrides.backgroundColor, settings.theme.background);
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage)).backgroundImageOpacity,
      settings.backgroundImageOpacity,
    );
    expect(source.contentWidth, 316);
    expect(
      source.contentHeight,
      780 - PageFurniture.headerHeight - PageFurniture.footerHeight,
    );

    final line = TextHitTester.lineBoxes(session.page!)
        .singleWhere((line) => line.text == '目标段落');
    final paper = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('reader-page-0-0')),
    );
    await tester.tapAt(
      paper.localToGlobal(
        line.rect.center +
            Offset(
              settings.margins!.left,
              settings.margins!.topInner + PageFurniture.headerHeight,
            ),
      ),
    );
    await tester.pump();
    expect(edits.single.cfi, cfiBase(line.slice.block.cfiAt(0)!));
    expect(edits.single.spineIndex, 0);
    expect(edits.single.contentRevision, 'editor-1');
  });

  testWidgets('左右滑动和翻页按钮只写预览内存，竖向拖动不滚动正文', (tester) async {
    String? location;
    final (:session, source: _) = await _openPreview(
      tester,
      onLocation: (target) => location = target.cfi,
    );
    expect(session.store, isA<MemoryReaderProgressStore>());
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage)).pageTurnMode,
      PageTurnMode.slideHorizontal,
    );
    final before = session.readingCfi;
    final beforePage = session.page;
    await tester.timedDrag(
      find.byType(ReaderPage),
      const Offset(0, -120),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(session.page, same(beforePage));
    expect(session.readingCfi, before);
    await tester.timedDrag(
      find.byType(ReaderPage),
      const Offset(-180, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    await pumpReaderUntilComplete(
      tester,
      () => location != null && location != before,
    );
    await session.flushProgress();
    final saved = await session.store.load(session.bookId);
    expect(saved?.cfi, location);
    expect(saved?.scrollOffset, isNull);
    expect(saved?.pageIndex, 1);
    expect(find.byType(ReaderPageHeader), findsOneWidget);
    expect(find.byType(ReaderPageFooter), findsOneWidget);
    await tester.tap(find.byTooltip('上一页'));
    await pumpReaderUntilComplete(tester, () => session.page?.pageIndex == 0);
    expect(session.readingCfi, before);
    await tester.tap(find.byTooltip('下一页'));
    await pumpReaderUntilComplete(tester, () => session.page?.pageIndex == 1);
    final nextCfi = session.readingCfi;

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(230, 700));
    await tester.pumpAndSettle();
    expect(session.readingCfi, nextCfi);
  });
}
