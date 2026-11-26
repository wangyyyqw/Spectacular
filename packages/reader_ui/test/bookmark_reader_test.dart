import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/bookmarks/bookmark_ribbon.dart';
import 'package:reader_ui/bookmarks/bookmark_style.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

class _Book implements RestylableChapterSource {
  double fontSize = 16;

  @override
  int get chapterCount => 1;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    fontSize = overrides.fontSize ?? 16;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle({
      'font-size': '${fontSize}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: '书签回归测试正文 ' * 400,
      style: style,
      maxWidth: 320,
    );
    return Paginator(pageHeight: 480)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              containingWidth: 320,
              layout: layout,
              style: style,
              startCfi: 'epubcfi(/6/2!/4/2/1:0)',
            ),
          ],
          spineIndex: spineIndex,
        )
        .pages;
  }
}

class _Bookmarks implements ReaderBookmarkStore {
  final items = <ReaderBookmark>[];
  bool fail = false;
  bool failRemove = false;

  @override
  Future<List<ReaderBookmark>> list() async => List.of(items);

  @override
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  }) async {
    if (fail) throw StateError('测试保存失败');
    if (items.any((item) => item.cfi == cfi)) return null;
    final item = ReaderBookmark(
      id: '${items.length}',
      cfi: cfi,
      spineIndex: spineIndex,
      label: label,
      createdAt: DateTime(2026),
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> remove(String id) async {
    if (failRemove) throw StateError('测试删除失败');
    items.removeWhere((item) => item.id == id);
  }
}

Future<ReaderSession> _open(
  WidgetTester tester,
  _Bookmarks bookmarks, {
  PageTurnMode mode = PageTurnMode.cover,
  ReaderBookmarkStyle style = const ReaderBookmarkStyle(),
  ValueChanged<ReaderBookmarkStyle>? onStyle,
  bool disableAnimations = false,
  double topInset = 0,
  double devicePixelRatio = 1,
  double? touchSlop,
  Size viewport = const Size(360, 520),
  Future<Uint8List> Function(String)? imageLoader,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          padding: EdgeInsets.only(top: topInset),
          devicePixelRatio: devicePixelRatio,
          gestureSettings: touchSlop == null
              ? null
              : DeviceGestureSettings(touchSlop: touchSlop),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: ReaderPage(
              source: _Book(),
              store: MemoryReaderProgressStore(),
              bookId: '书签回归',
              bookmarks: bookmarks,
              bookmarkStyle: style,
              bookmarkImageLoader: imageLoader,
              onBookmarkStyleChanged: onStyle,
              pageTurnMode: mode,
              overrides: const ReaderOverrides(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
}

Future<void> _openBookmarkStyle(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-entry-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-bookmark-style')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('size-tab')));
  await tester.pumpAndSettle();
}

Future<void> _expectBookmarkPullDisabled(WidgetTester tester) async {
  final view = find.byType(ReaderView);
  final original = tester.getRect(view);
  final gesture = await tester.startGesture(tester.getCenter(view));
  await gesture.moveBy(const Offset(0, 25));
  await tester.pump();
  await gesture.moveBy(const Offset(0, 280));
  await tester.pump();
  expect(tester.getRect(view), original);
  expect(find.text('松手确认添加'), findsNothing);
  expect(find.text('松手确认移除'), findsNothing);
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _move(WidgetTester tester, Future<Object?> action) async {
  unawaited(action);
  await tester.pumpAndSettle();
}

Future<void> _dragBookmark(WidgetTester tester, List<Offset> deltas) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ReaderView)),
  );
  for (final delta in deltas) {
    await gesture.moveBy(delta);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pullBookmark(
  WidgetTester tester, {
  bool remove = false,
  double rightInset = 37,
}) async {
  final view = find.byType(ReaderView);
  final original = tester.getRect(view);
  final gesture = await tester.startGesture(tester.getCenter(view));
  await gesture.moveBy(const Offset(0, 25));
  await tester.pump();
  await gesture.moveBy(const Offset(0, 280));
  await tester.pump();
  final hint = find.text(remove ? '松手确认移除' : '松手确认添加');
  expect(hint, findsOneWidget);
  final pulled = tester.getRect(view);
  expect(pulled.size, original.size, reason: '整页移动不压缩正文或重新分页');
  expect(pulled.top, original.top + 161);
  expect(tester.getRect(hint).bottom, lessThan(pulled.top));
  final ribbon = find.byKey(const ValueKey('reader-bookmark-ribbon'));
  expect(ribbon, findsOneWidget, reason: '下拉提示与纸面不能重复绘制书签');
  expect(tester.getTopRight(ribbon).dy, original.top);
  expect(tester.getTopRight(ribbon).dx, original.right - rightInset);
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  final returning = tester.getTopLeft(view).dy;
  expect(returning, greaterThan(original.top));
  expect(returning, lessThan(pulled.top));
  await tester.pumpAndSettle();
  expect(tester.getRect(view), original);
  expect(hint, findsNothing);
}

Future<Uint8List> _redPng(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(1, 1);
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
      } finally {
        image.dispose();
        picture.dispose();
      }
    }))!;

Future<void> _prepareTurn(WidgetTester tester, {required bool next}) async {
  final controller = tester
      .state<PageTurnViewState>(find.byType(PageTurnView))
      .controller;
  final down = Offset(next ? 350 : 10, 260);
  final touch = Offset(next ? 170 : 190, 260);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  controller.updateDrag(
    DragUpdateDetails(localPosition: touch, globalPosition: touch),
  );
  for (
    var i = 0;
    i < 80 &&
        (controller.originImage == null || controller.targetImage == null);
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(controller.originImage, isNotNull);
  expect(controller.targetImage, isNotNull);
}

Future<void> _expectSnapshotBookmark(
  WidgetTester tester,
  ui.Image image, {
  required bool marked,
}) async {
  final data = (await tester.runAsync(image.toByteData))!;
  final x = (image.width * 311 / 360).floor();
  final y = (image.height * 8 / 520).floor();
  final offset = (y * image.width + x) * 4;
  final channels = [for (var i = 0; i < 3; i++) data.getUint8(offset + i)];
  if (marked) {
    expect(channels, everyElement(lessThan(100)));
    expect(data.getUint8(offset + 3), 255);
  } else {
    expect(
      data.getUint8(offset + 3) == 0 || channels.every((value) => value > 240),
      isTrue,
      reason: '无书签纸面在该位置应为透明或纸底色',
    );
  }
}

void main() {
  testWidgets('自定义书签图片先解码再捕获，邻页快照复用同一图片', (tester) async {
    final bytes = Completer<Uint8List>();
    var loads = 0;
    final bookmarks = _Bookmarks();
    await _open(
      tester,
      bookmarks,
      style: const ReaderBookmarkStyle(imageId: 'image:书签'),
      imageLoader: (_) {
        loads++;
        return bytes.future;
      },
    );
    await _pullBookmark(tester);
    final png = await _redPng(tester);
    bytes.complete(png);
    await _prepareTurn(tester, next: true);
    final controller = tester
        .state<PageTurnViewState>(find.byType(PageTurnView))
        .controller;
    final image = controller.originImage!;
    final data = (await tester.runAsync(image.toByteData))!;
    final offset =
        ((image.height * 8 / 520).floor() * image.width +
            (image.width * 311 / 360).floor()) *
        4;
    expect(
      [for (var i = 0; i < 4; i++) data.getUint8(offset + i)],
      [255, 0, 0, 255],
    );
    expect(loads, 1);
    controller.cancel();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('图片书签下拉交接逐帧复用解码图，短拉保留翻页缓存', (tester) async {
    final png = await _redPng(tester);
    var loads = 0;
    final bookmarks = _Bookmarks();
    await _open(
      tester,
      bookmarks,
      mode: PageTurnMode.simulation3d,
      style: const ReaderBookmarkStyle(imageId: 'image:书签', rightInset: 64),
      imageLoader: (_) async {
        loads++;
        return png;
      },
    );
    await _pullBookmark(tester, rightInset: 64);
    await _prepareTurn(tester, next: true);
    final turn = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    turn.controller.cancel();
    await tester.pumpAndSettle();
    final ribbon = find.byType(ReaderBookmarkRibbon);
    final decoded = tester
        .widget<RawImage>(
          find.descendant(of: ribbon, matching: find.byType(RawImage)),
        )
        .image;
    expect(decoded, isNotNull);
    final cached = turn.snapshotCount;
    expect(cached, greaterThan(0));

    // 反复在提示层与静态纸面间交接，不能短暂绘制黑色默认图标。
    for (final distance in [80.0, 280.0, 280.0]) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReaderView)),
      );
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(Offset(0, distance));
      await tester.pump();
      if (distance == 80) expect(turn.snapshotCount, cached);
      await gesture.up();
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (bookmarks.items.isNotEmpty) {
          expect(ribbon, findsWidgets, reason: '归位交接不能出现书签消失的一帧');
        }
        expect(
          find.descendant(of: ribbon, matching: find.byType(ClipPath)),
          findsNothing,
        );
        for (final image in tester.widgetList<RawImage>(
          find.descendant(of: ribbon, matching: find.byType(RawImage)),
        )) {
          expect(image.image, same(decoded), reason: '重新挂载的每一帧直接使用同一解码图');
        }
      }
      await tester.pumpAndSettle();
    }
    expect(bookmarks.items, hasLength(1));
    expect(loads, 1);
    await _prepareTurn(tester, next: true);
    turn.controller.endDrag(
      DragEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(-1000, 0)),
      ),
    );
    await tester.pumpAndSettle();
    await _prepareTurn(tester, next: false);
    turn.controller.endDrag(
      DragEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
      ),
    );
    for (var frame = 0; frame < 50; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(of: ribbon, matching: find.byType(ClipPath)),
        findsNothing,
      );
      for (final image in tester.widgetList<RawImage>(
        find.descendant(of: ribbon, matching: find.byType(RawImage)),
      )) {
        expect(image.image, same(decoded));
      }
    }
    expect(loads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in PageTurnMode.values.where(
    (mode) => mode != PageTurnMode.scroll && mode != PageTurnMode.none,
  )) {
    testWidgets('${mode.label}翻页快照携带各自书签，增删后不沿用旧缓存', (tester) async {
      final bookmarks = _Bookmarks();
      final session = await _open(tester, bookmarks, mode: mode);
      final controller = tester
          .state<PageTurnViewState>(find.byType(PageTurnView))
          .controller;
      await _prepareTurn(tester, next: true);
      await _expectSnapshotBookmark(
        tester,
        controller.originImage!,
        marked: false,
      );
      controller.cancel();
      await tester.pumpAndSettle();
      await _pullBookmark(tester);
      await _prepareTurn(tester, next: true);
      await _expectSnapshotBookmark(
        tester,
        controller.originImage!,
        marked: true,
      );
      await _expectSnapshotBookmark(
        tester,
        controller.targetImage!,
        marked: false,
      );
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
        reason: '活动翻页由纸面快照承载书签，屏幕顶边不再叠加固定标记',
      );
      controller.endDrag(
        DragEndDetails(
          velocity: const Velocity(pixelsPerSecond: Offset(-1000, 0)),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 1);
      await _prepareTurn(tester, next: false);
      await _expectSnapshotBookmark(
        tester,
        controller.originImage!,
        marked: false,
      );
      await _expectSnapshotBookmark(
        tester,
        controller.targetImage!,
        marked: true,
      );
      controller.endDrag(
        DragEndDetails(
          velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 0);
      await _pullBookmark(tester, remove: true);
      await _prepareTurn(tester, next: true);
      await _expectSnapshotBookmark(
        tester,
        controller.originImage!,
        marked: false,
      );
      controller.cancel();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('书签在有状态栏留白时仍贴紧页面顶边，添加与移除不弹底部提示', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks, topInset: 32);
    await _pullBookmark(tester);
    final ribbon = find.byKey(const ValueKey('reader-bookmark-ribbon'));
    expect(
      tester.getTopRight(ribbon).dy,
      tester.getTopLeft(find.byType(ReaderView)).dy,
    );
    expect(bookmarks.items, hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items, isEmpty);
    expect(ribbon, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('未到阈值松手回位不添加，减少动画设置直接归位', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks, disableAnimations: true);
    final view = find.byType(ReaderView);
    final original = tester.getRect(view);
    final gesture = await tester.startGesture(original.center);
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(tester.getRect(view), original, reason: '缓冲距离内不推动纸面');
    expect(find.text('下拉添加书签'), findsNothing);
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(tester.getTopLeft(view).dy, original.top + 41);
    expect(find.text('下拉添加书签'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(tester.getRect(view), original);
    expect(bookmarks.items, isEmpty);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
  });

  testWidgets('替换书签存储立即清除旧命中，并按章节和重定位状态更新标记', (tester) async {
    ReaderBookmark bookmark(String id, int spine, {String? status}) =>
        ReaderBookmark(
          id: id,
          cfi: 'epubcfi(/6/2!/4/2/1:0)',
          spineIndex: spine,
          label: '缓存回归',
          createdAt: DateTime(2026),
          relocationStatus: status,
        );
    final marked = _Bookmarks()..items.add(bookmark('当前章', 0));
    final unrelated = _Bookmarks()
      ..items.add(bookmark('其它章', 1))
      ..items.add(bookmark('待重定位', 0, status: 'pending'));
    final store = ValueNotifier<_Bookmarks>(marked);
    final source = _Book();
    final progress = MemoryReaderProgressStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<_Bookmarks>(
            valueListenable: store,
            builder: (_, bookmarks, _) => ReaderPage(
              source: source,
              store: progress,
              bookId: '书签缓存替换',
              bookmarks: bookmarks,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ribbon = find.byKey(const ValueKey('reader-bookmark-ribbon'));
    expect(ribbon, findsOneWidget);
    await _openMenu(tester);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isTrue,
    );

    store.value = unrelated;
    await tester.pumpAndSettle();
    expect(ribbon, findsNothing);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isFalse,
    );
    store.value = marked;
    await tester.pumpAndSettle();
    expect(ribbon, findsOneWidget);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('3D 短促红线斜滑只收到两次 MOVE 仍可前后翻页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bookmarks = _Bookmarks();
    final session = await _open(
      tester,
      bookmarks,
      mode: PageTurnMode.simulation3d,
      viewport: const Size(360, 800),
      devicePixelRatio: 2,
      touchSlop: 36,
    );
    for (final direction in [-1.0, 1.0]) {
      final down =
          tester.getTopLeft(find.byType(ReaderView)) +
          Offset(direction < 0 ? 286 : 74, 625);
      final drag = await tester.startGesture(down);
      await drag.moveTo(
        down + Offset(direction, -176 / 104),
        timeStamp: const Duration(milliseconds: 20),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveTo(
        down + Offset(direction * 104, -176),
        timeStamp: const Duration(milliseconds: 180),
      );
      await tester.pump(const Duration(milliseconds: 160));
      await drag.up(timeStamp: const Duration(milliseconds: 180));
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, direction < 0 ? 1 : 0);
      expect(bookmarks.items, isEmpty);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in PageTurnMode.values.where(
    (value) => value != PageTurnMode.scroll,
  )) {
    testWidgets('${mode.label}红线向上斜滑前后翻页，不触发下拉书签', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bookmarks = _Bookmarks();
      final session = await _open(
        tester,
        bookmarks,
        mode: mode,
        viewport: const Size(360, 800),
        devicePixelRatio: 2,
        touchSlop: 36,
      );
      expect(tester.getSize(find.byType(ReaderView)), const Size(360, 800));
      final initial = session.currentCfi;
      // 普通模式保留 35% 页宽的松手门槛，只沿同一红线方向延长轨迹。
      final distance = mode.is3d || mode == PageTurnMode.simulationBessel
          ? 104.0
          : 144.0;
      for (final direction in [-1.0, 1.0]) {
        final down =
            tester.getTopLeft(find.byType(ReaderView)) +
            Offset(direction < 0 ? 286 : 74, 625);
        final delta = Offset(direction * distance, -distance * 176 / 104);
        final drag = await tester.startGesture(down);
        for (var step = 1; step <= 20; step++) {
          await drag.moveTo(
            down + delta * (step / 20),
            timeStamp: Duration(milliseconds: step * 17),
          );
          await tester.pump(const Duration(milliseconds: 17));
        }
        await drag.up(timeStamp: const Duration(milliseconds: 340));
        await tester.pumpAndSettle();
        expect(session.page!.pageIndex, direction < 0 ? 1 : 0);
        expect(bookmarks.items, isEmpty);
        expect(find.textContaining('松手确认'), findsNothing);
      }
      expect(session.currentCfi, initial);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${mode.label}纵向主方向斜拉可切换书签，锁定后横移不取消', (tester) async {
      final bookmarks = _Bookmarks();
      final session = await _open(tester, bookmarks, mode: mode);
      final initial = session.currentCfi;
      for (final direction in [-1.0, 1.0]) {
        for (final diagonalStart in [false, true]) {
          final remove = bookmarks.items.isNotEmpty;
          await _dragBookmark(tester, [
            Offset(diagonalStart ? 24 * direction : 0, 40),
            Offset(180 * direction, 260),
            Offset(-180 * direction, 0),
          ]);
          expect(bookmarks.items, hasLength(remove ? 0 : 1));
          expect(session.currentCfi, initial, reason: '纵向锁定后横移不能翻页');
          expect(find.textContaining('松手确认'), findsNothing);
        }
      }
      await _dragBookmark(tester, [const Offset(4, 25), const Offset(6, 280)]);
      expect(bookmarks.items, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${mode.label}关闭下拉书签后不增删，菜单添加和已有标记仍正常', (tester) async {
      final bookmarks = _Bookmarks();
      await _open(
        tester,
        bookmarks,
        mode: mode,
        style: const ReaderBookmarkStyle(pullEnabled: false),
      );
      await _expectBookmarkPullDisabled(tester);
      expect(bookmarks.items, isEmpty);
      await _openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
      await tester.pumpAndSettle();
      expect(bookmarks.items, hasLength(1));
      final bookmark = bookmarks.items.single;
      await _openMenu(tester);
      await _expectBookmarkPullDisabled(tester);
      expect(bookmarks.items.single, same(bookmark));
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${mode.label}下拉添加与移除，短拖和上滑不触发，横滑仍翻页', (tester) async {
      final bookmarks = _Bookmarks();
      final session = await _open(tester, bookmarks, mode: mode);
      final view = find.byType(ReaderView);
      final initial = session.currentCfi;
      await tester.drag(view, const Offset(0, 45));
      await tester.pumpAndSettle();
      await tester.drag(view, const Offset(0, 125));
      await tester.pumpAndSettle();
      await tester.drag(view, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(bookmarks.items, isEmpty);
      final start = tester.getCenter(view);
      await _pullBookmark(tester);
      expect(bookmarks.items.single.cfi, initial);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsOneWidget,
      );
      await _pullBookmark(tester, remove: true);
      expect(bookmarks.items, isEmpty);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
      );
      expect(find.byType(SnackBar), findsNothing);
      await _pullBookmark(tester);
      // 用多次采样兼容仿真模式的原生起拖规则。
      final horizontal = await tester.startGesture(
        start + const Offset(100, 0),
      );
      for (var i = 0; i < 12; i++) {
        await horizontal.moveBy(const Offset(-24, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await horizontal.up();
      await tester.pumpAndSettle();
      expect(session.currentCfi, isNot(initial));
      expect(bookmarks.items, hasLength(1));
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('书签面板保存开关后立即禁用或恢复下拉手势', (tester) async {
    final bookmarks = _Bookmarks();
    ReaderBookmarkStyle? saved;
    await _open(tester, bookmarks, onStyle: (style) => saved = style);
    for (final enabled in [false, true]) {
      await _openMenu(tester);
      await _openBookmarkStyle(tester);
      final toggle = find.byKey(const ValueKey('bookmark-pull-enabled'));
      expect(tester.widget<SwitchListTile>(toggle).value, !enabled);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookmark-style-save')));
      await tester.pumpAndSettle();
      expect(saved!.pullEnabled, enabled);
      final mask = find.byKey(const ValueKey('menu-drawer-mask'));
      await tester.tapAt(tester.getTopLeft(mask) + const Offset(10, 10));
      await tester.pumpAndSettle();
      // 点遮罩直接退出菜单，回到正文后再验证下拉手势。
      expect(
        tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
        isFalse,
      );
      if (enabled) {
        await _pullBookmark(tester);
        expect(bookmarks.items, hasLength(1));
      } else {
        await _expectBookmarkPullDisabled(tester);
        expect(bookmarks.items, isEmpty);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [PageTurnMode.cover, PageTurnMode.scroll]) {
    testWidgets('${mode.label}工具栏添加、重复去重、列表同步与删除标记', (tester) async {
      final bookmarks = _Bookmarks();
      final session = await _open(tester, bookmarks, mode: mode);
      if (mode == PageTurnMode.scroll) {
        final before = session.currentCfi;
        await tester.drag(find.byType(ReaderView), const Offset(0, -230));
        await tester.pumpAndSettle();
        expect(session.currentCfi, isNot(before));
        await tester.drag(find.byType(ReaderView), const Offset(0, 130));
        await tester.pumpAndSettle();
        expect(bookmarks.items, isEmpty, reason: '滚动阅读下拉不能添加书签');
      }
      final expected = session.currentCfi;
      await _openMenu(tester);
      final button = find.byKey(const ValueKey('menu-add-bookmark'));
      expect(
        tester.getCenter(button).dx,
        greaterThan(
          tester.getCenter(find.byKey(const ValueKey('menu-daynight'))).dx,
        ),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(bookmarks.items.single.cfi, expected);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        mode == PageTurnMode.scroll ? findsNothing : findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(bookmarks.items, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer-tab-bookmarks')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('删除书签'), findsOneWidget);
      await tester.tap(find.byTooltip('删除书签'));
      await tester.pumpAndSettle();
      expect(find.text('还没有书签'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('横向主方向、未达阈值、回拉和系统取消均不改变书签', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks);
    final center = tester.getCenter(find.byType(ReaderView));
    for (final deltas in [
      [const Offset(70, 25), const Offset(0, 300)],
      [const Offset(0, -40), const Offset(0, 220)],
      [const Offset(0, 25), const Offset(0, 280), const Offset(0, -80)],
    ]) {
      final gesture = await tester.startGesture(center);
      for (final delta in deltas) {
        await gesture.moveBy(delta);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(bookmarks.items, isEmpty);
    }
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 25));
    await gesture.moveBy(const Offset(0, 280));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(bookmarks.items, isEmpty);
    await _pullBookmark(tester);
    expect(bookmarks.items, hasLength(1));
  });

  for (final ratio in [1.0, 2.0, 3.0]) {
    testWidgets('像素比 $ratio 按 144 物理像素缓冲和 128dp 纸面阈值切换', (tester) async {
      final bookmarks = _Bookmarks();
      await _open(tester, bookmarks, devicePixelRatio: ratio);
      final view = find.byType(ReaderView);
      final original = tester.getRect(view);
      final gesture = await tester.startGesture(original.center);
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(Offset(0, 144 / ratio + 128 - 25 - 0.5));
      await tester.pump();
      expect(tester.getTopLeft(view).dy, original.top + 127.5);
      expect(find.text('下拉添加书签'), findsOneWidget);
      final hintIcon = find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.glyph == AppGlyph.bookmark,
      );
      expect(tester.widget<AppIcon>(hintIcon).filled, isFalse);
      expect(bookmarks.items, isEmpty, reason: '拖动时尚未保存');
      await gesture.moveBy(const Offset(0, 0.5));
      await tester.pump();
      expect(find.text('松手确认添加'), findsOneWidget);
      expect(tester.widget<AppIcon>(hintIcon).filled, isTrue);
      expect(bookmarks.items, isEmpty, reason: '达到阈值仍须松手');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(bookmarks.items, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('设备起拖阈值前的采样不推动纸面，纵向先上滑后下拉仍可添加', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks, touchSlop: 40);
    final view = find.byType(ReaderView);
    final original = tester.getRect(view);
    final gesture = await tester.startGesture(original.center);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(tester.getTopLeft(view).dy, original.top + 36);
    expect(find.text('松手确认添加'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bookmarks.items, isEmpty);
    await _dragBookmark(tester, [const Offset(0, -50), const Offset(0, 340)]);
    expect(bookmarks.items, hasLength(1));
  });

  testWidgets('拖动达到阈值后切换页面，松手不会修改旧页或新页书签', (tester) async {
    final bookmarks = _Bookmarks();
    final session = await _open(tester, bookmarks);
    final initial = session.currentCfi;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReaderView)),
    );
    await gesture.moveBy(const Offset(0, 25));
    await gesture.moveBy(const Offset(0, 280));
    await tester.pump();
    expect(find.text('松手确认添加'), findsOneWidget);
    await _move(tester, session.next());
    expect(session.currentCfi, isNot(initial));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bookmarks.items, isEmpty);
    expect(find.textContaining('松手确认'), findsNothing);
  });

  testWidgets('下拉移除按当前页文本范围匹配，并保留其它页和待重定位书签', (tester) async {
    final bookmarks = _Bookmarks();
    final session = await _open(tester, bookmarks);
    final currentCfi = session.currentCfi!;
    await _move(tester, session.next());
    final nextCfi = session.currentCfi!;
    await _move(tester, session.previous());
    bookmarks.items.addAll([
      for (final offset in [5, 20])
        ReaderBookmark(
          id: '当前页-$offset',
          cfi: currentCfi.replaceFirst(':0)', ':$offset)'),
          spineIndex: 0,
          label: '当前页正文中的书签',
          createdAt: DateTime(2026),
        ),
      ReaderBookmark(
        id: '其它页',
        cfi: nextCfi,
        spineIndex: 0,
        label: '其它页书签',
        createdAt: DateTime(2026),
      ),
      ReaderBookmark(
        id: '待重定位',
        cfi: currentCfi,
        spineIndex: 0,
        label: '待重定位书签',
        createdAt: DateTime(2026),
        relocationStatus: 'pending',
      ),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, bookmarks);
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items.map((item) => item.id), ['其它页', '待重定位']);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
  });

  testWidgets('下拉移除失败保留标记，重试可成功', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks);
    await _pullBookmark(tester);
    bookmarks.failRemove = true;
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items, hasLength(1));
    expect(find.text('书签删除失败，请重试'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reader-bookmark-ribbon')),
      findsOneWidget,
    );
    bookmarks.failRemove = false;
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items, isEmpty);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
  });

  testWidgets('重排后按文本位置恢复标记，书签样式可从设置修改并保存', (tester) async {
    final bookmarks = _Bookmarks();
    ReaderBookmarkStyle? saved;
    final session = await _open(
      tester,
      bookmarks,
      style: const ReaderBookmarkStyle(
        width: 32,
        length: 90,
        rightInset: 64,
        color: 0xFFA5D6A7,
      ),
      onStyle: (style) => saved = style,
    );
    await _move(tester, session.next());
    await _openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
    await tester.pumpAndSettle();
    final cfi = bookmarks.items.single.cfi;
    await _move(
      tester,
      session.applyOverrides(const ReaderOverrides(fontSize: 22)),
    );
    await _move(tester, session.jumpToCfi(cfi));
    final ribbon = find.byKey(const ValueKey('reader-bookmark-ribbon'));
    expect(ribbon, findsOneWidget);
    expect(tester.getSize(ribbon), const Size(32, 90));
    expect(
      tester.widget<ReaderBookmarkRibbon>(ribbon).color,
      const Color(0xFFA5D6A7),
    );
    final readerRect = tester.getRect(find.byType(ReaderView));
    expect(tester.getTopRight(ribbon).dx, readerRect.right - 64);
    expect(tester.getTopRight(ribbon).dy, readerRect.top);
    await _openBookmarkStyle(tester);
    final slider = find.byKey(const ValueKey('bookmark-宽度'));
    await tester.ensureVisible(slider);
    await tester.tapAt(tester.getCenter(slider));
    await tester.pumpAndSettle();
    final inset = find.byKey(const ValueKey('bookmark-距右侧'));
    await tester.ensureVisible(inset);
    await tester.tapAt(tester.getCenter(inset));
    await tester.pumpAndSettle();
    final preview = find.byType(ReaderBookmarkRibbon).last;
    expect(tester.widget<ReaderBookmarkRibbon>(preview).style.rightInset, 80);
    await tester.tap(find.byKey(const ValueKey('bookmark-style-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.width, isNot(32));
    expect(saved!.rightInset, 80);
    expect(tester.widget<ReaderBookmarkRibbon>(ribbon).style, saved);
    expect(tester.getTopRight(ribbon).dx, readerRect.right - 80);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('保存失败不显示已添加，重试可成功', (tester) async {
    final bookmarks = _Bookmarks()..fail = true;
    await _open(tester, bookmarks);
    await _openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
    await tester.pumpAndSettle();
    expect(find.text('书签保存失败，请重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
    bookmarks.fail = false;
    await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
    await tester.pumpAndSettle();
    expect(bookmarks.items, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
