import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/image_preview_page.dart';

Future<ui.Image> _createImage(int width, int height, int color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Color(color),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<List<ui.Image>> _images(WidgetTester tester) async {
  final images = await tester.runAsync(
    () => Future.wait([
      _createImage(40, 30, 0xFFFF0000),
      _createImage(80, 60, 0xFF00FF00),
      _createImage(120, 90, 0xFF0000FF),
    ]),
  );
  addTearDown(() {
    for (final image in images!) {
      image.dispose();
    }
  });
  return images!;
}

List<ImagePreviewItem> _items(List<ui.Image> images, List<int> loads) => [
  for (var index = 0; index < images.length; index++)
    ImagePreviewItem(
      thumbnail: () => images[index],
      loadOriginal: () async {
        loads.add(index);
        return images[index];
      },
    ),
];

Future<void> _swipe(WidgetTester tester, Offset distance) async {
  await tester.fling(find.byType(InteractiveViewer), distance, 1200);
  await tester.pumpAndSettle();
}

Future<void> _doubleTap(WidgetTester tester) async {
  final target = find.byType(InteractiveViewer);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

bool _enabled(WidgetTester tester, IconData icon) =>
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
        .onPressed !=
    null;

PageController _pager(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!;

Future<void> _pinch(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(InteractiveViewer));
  final first = await tester.startGesture(center - const Offset(50, 0));
  final second = await tester.startGesture(
    center + const Offset(50, 0),
    pointer: 2,
  );
  await first.moveBy(const Offset(-40, 0));
  await tester.pump();
  await second.moveBy(const Offset(40, 0));
  await tester.pump();
  await first.moveBy(const Offset(-60, 0));
  await second.moveBy(const Offset(60, 0));
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('预览页：缩略图先出、原图解码后替换、可缩放、可关闭', (tester) async {
    final thumbnail = await tester.runAsync(
      () => _createImage(40, 30, 0xFF00FF00),
    );
    final original = await tester.runAsync(
      () => _createImage(400, 300, 0xFFFF0000),
    );
    final pending = Completer<ui.Image?>();
    var originalLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImagePreviewPage(
                  thumbnail: thumbnail,
                  loadOriginal: () async {
                    originalLoads += 1;
                    return pending.future;
                  },
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('preview-viewer')),
      findsOneWidget,
      reason: '固定视口允许拖动中加入第二指缩放',
    );
    expect(find.byKey(const ValueKey<String>('preview-close')), findsOneWidget);

    // 原图解码完成后替换缩略图。
    final rawImage = find.byKey(const ValueKey('preview-image'));
    final size = tester.getSize(rawImage);
    expect(
      tester.widget<RawImage>(rawImage).image!.isCloneOf(thumbnail!),
      isTrue,
    );
    pending.complete(original);
    await tester.pump(const Duration(milliseconds: 100));
    expect(originalLoads, 1);
    final displayed = tester
        .widget<RawImage>(find.byKey(const ValueKey('preview-image')))
        .image!;
    expect(displayed.isCloneOf(original!), isTrue);
    expect(tester.getSize(rawImage), size, reason: '原图替换时保持视口尺寸');

    // 关闭（先于手势测试：排除拖拽状态干扰）。
    await tester.tap(find.byKey(const ValueKey<String>('preview-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsNothing);
  });

  testWidgets('预览页：拖动手势不崩溃且不关闭页面', (tester) async {
    final thumbnail = await tester.runAsync(
      () => _createImage(40, 30, 0xFF00FF00),
    );
    final original = await tester.runAsync(
      () => _createImage(400, 300, 0xFFFF0000),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          thumbnail: thumbnail,
          loadOriginal: () async => original,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final center = tester.getCenter(
      find.byKey(const ValueKey<String>('preview-viewer')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-40, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsOneWidget);
  });

  testWidgets('原图解码失败：保持缩略图展示不崩溃', (tester) async {
    final thumbnail = await tester.runAsync(
      () => _createImage(40, 30, 0xFF00FF00),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          thumbnail: thumbnail,
          loadOriginal: () async => null,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('preview-image')), findsOneWidget);
  });

  testWidgets('无缩略图且解码中：显示加载圈', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          loadOriginal: () =>
              Future<ui.Image?>.delayed(const Duration(seconds: 1), () => null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 清掉 1s 定时器再结束（fake_async 不留 pending timer）。
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('无缩略图且加载失败：显示错误并允许重新加载', (tester) async {
    var loads = 0;
    final image = await tester.runAsync(() => _createImage(40, 30, 0xFF00FF00));
    addTearDown(() => image?.dispose());
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage(
          loadOriginal: () async => ++loads == 1 ? null : image,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图片无法加载'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-image')), findsOneWidget);
    expect(loads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('画廊从指定图片打开，只加载当前原图，切图按钮在首尾禁用', (tester) async {
    final images = await _images(tester);
    final loads = <int>[];
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage.gallery(
          items: _items(images, loads),
          initialIndex: 1,
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(loads, [1]);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(_enabled(tester, Icons.chevron_right), isFalse);
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(_enabled(tester, Icons.chevron_left), isFalse);
    expect(changes, [2, 1, 0]);
    expect(loads, [1, 2, 1, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('原尺寸横滑切图，纵滑与放大后的拖动不误切图，切图重置缩放', (tester) async {
    final images = await _images(tester);
    await tester.pumpWidget(
      MaterialApp(home: ImagePreviewPage.gallery(items: _items(images, []))),
    );
    await tester.pumpAndSettle();
    await _swipe(tester, const Offset(-200, 0));
    expect(find.text('2 / 3'), findsOneWidget);
    await _swipe(tester, const Offset(0, -200));
    expect(find.text('2 / 3'), findsOneWidget);
    await _doubleTap(tester);
    expect(_scale(tester), closeTo(3, 0.01));
    await _swipe(tester, const Offset(-200, 0));
    expect(find.text('2 / 3'), findsOneWidget);
    await _doubleTap(tester);
    expect(_scale(tester), closeTo(1, 0.01));
    await _swipe(tester, const Offset(-200, 0));
    expect(find.text('3 / 3'), findsOneWidget);
    await _doubleTap(tester);
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(_scale(tester), closeTo(1, 0.01));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('双指缩放不会被横滑切图抢占', (tester) async {
    final images = await _images(tester);
    await tester.pumpWidget(
      MaterialApp(home: ImagePreviewPage.gallery(items: _items(images, []))),
    );
    await tester.pumpAndSettle();
    await _pinch(tester);
    expect(_scale(tester), greaterThan(1.2));
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('拖动跟手但不提前切图，短拖和反向拖回松手后还原', (tester) async {
    final images = await _images(tester);
    final loads = <int>[];
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage.gallery(
          items: _items(images, loads),
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    final width = tester.getSize(viewer).width;
    final pager = _pager(tester);
    for (final reverse in [false, true]) {
      final gesture = await tester.startGesture(tester.getCenter(viewer));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(Offset(-width * 0.2, 0));
      await tester.pump();
      final position = pager.page!;
      expect(position, inExclusiveRange(0, 0.5));
      expect(find.text('1 / 3'), findsOneWidget);
      expect(loads, [0], reason: '吸附前只加载当前原图');
      if (reverse) {
        await gesture.moveBy(Offset(width * 0.1, 0));
        await tester.pump();
        expect(pager.page, lessThan(position));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pager.page, closeTo(0, 0.001));
      expect(changes, isEmpty);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('横滑超过半帧后加入第二指仍可缩放，剩余单指不误切图', (tester) async {
    final images = await _images(tester);
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage.gallery(
          items: _items(images, []),
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    final size = tester.getSize(viewer);
    final start =
        tester.getTopLeft(viewer) + Offset(size.width * 0.9, size.height / 2);
    final first = await tester.startGesture(start);
    await first.moveBy(const Offset(-40, 0));
    await first.moveBy(Offset(-size.width * 0.6, 0));
    await tester.pump();
    expect(_pager(tester).page, greaterThan(0.5));
    expect(find.text('1 / 3'), findsOneWidget);
    final second = await tester.startGesture(start, pointer: 2);
    await tester.pump();
    expect(_pager(tester).page, closeTo(0, 0.001));
    await first.moveBy(const Offset(-50, 0));
    await second.moveBy(const Offset(30, 0));
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(_scale(tester), greaterThan(1.2));
    await second.up();
    await first.moveBy(const Offset(-60, 0));
    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(changes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首尾有拖动反馈，松手回到边界且不绕回其他图片', (tester) async {
    final images = await _images(tester);
    await tester.pumpWidget(
      MaterialApp(home: ImagePreviewPage.gallery(items: _items(images, []))),
    );
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    for (final direction in [1.0, -1.0]) {
      if (direction < 0) {
        await tester.tap(find.byTooltip('下一张'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('下一张'));
        await tester.pumpAndSettle();
      }
      final gesture = await tester.startGesture(tester.getCenter(viewer));
      await gesture.moveBy(Offset(direction * 40, 0));
      await gesture.moveBy(Offset(direction * 80, 0));
      await tester.pump();
      final position = _pager(tester).position;
      expect(position.outOfRange, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(position.outOfRange, isFalse);
      expect(find.text(direction > 0 ? '1 / 3' : '3 / 3'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('减少动画或墨水模式下仍可即时切图和双击缩放', (tester) async {
    final images = await _images(tester);
    for (final systemReduced in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(systemReduced),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: systemReduced),
            child: child!,
          ),
          home: ImagePreviewPage.gallery(
            items: _items(images, []),
            animate: systemReduced,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      final gesture = await tester.startGesture(tester.getCenter(viewer));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      expect(_pager(tester).page, 0, reason: '拖动期间不播放过渡');
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(viewer);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(viewer);
      await tester.pump();
      expect(_scale(tester), closeTo(3, 0.001));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('键盘可切图与缩放，读屏序号随图片更新', (tester) async {
    final images = await _images(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: ImagePreviewPage.gallery(items: _items(images, []))),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.byType(InteractiveViewer))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_scale(tester), closeTo(3, 0.01));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('第 2 张，共 3 张'), findsOneWidget);
    expect(_scale(tester), closeTo(1, 0.01));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('晚到的原图不覆盖新图片，切图和关闭释放克隆句柄', (tester) async {
    final images = await _images(tester);
    final first = Completer<ui.Image?>();
    final second = Completer<ui.Image?>();
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage.gallery(
          items: [
            ImagePreviewItem(loadOriginal: () => first.future),
            ImagePreviewItem(loadOriginal: () => second.future),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    first.complete(images[0]);
    await tester.pump();
    expect(find.byKey(const ValueKey('preview-image')), findsNothing);
    second.complete(images[1]);
    await tester.pumpAndSettle();
    final displayed = tester
        .widget<RawImage>(find.byKey(const ValueKey('preview-image')))
        .image!;
    expect(displayed.isCloneOf(images[1]), isTrue);
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(displayed.debugDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final image in images) {
      expect(image.debugGetOpenHandleStackTraces(), hasLength(1));
    }
  });

  testWidgets('缺图可重试或继续切图，保留作者分帧序号', (tester) async {
    final images = await _images(tester);
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ImagePreviewPage.gallery(
          items: [
            ImagePreviewItem(
              loadOriginal: () async {
                if (++attempts == 1) throw StateError('原图读取失败');
                return images.first;
              },
            ),
            ImagePreviewItem(loadOriginal: () async => null),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图片无法加载'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-image')), findsOneWidget);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('图片无法加载'), findsOneWidget);
    await tester.fling(find.text('图片无法加载'), const Offset(200, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-image')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('关闭后才完成原图加载，不保留图片或更新已销毁界面', (tester) async {
    final images = await _images(tester);
    final pending = Completer<ui.Image?>();
    await tester.pumpWidget(
      MaterialApp(home: ImagePreviewPage(loadOriginal: () => pending.future)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(images.first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(images.first.debugGetOpenHandleStackTraces(), hasLength(1));
  });

  testWidgets('窄屏大字号下序号和切图控件保持可见且无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = await _images(tester);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ImagePreviewPage.gallery(items: _items(images, [])),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1 / 3').hitTestable(), findsOneWidget);
    final nextButton = find.widgetWithIcon(IconButton, Icons.chevron_right);
    expect(nextButton.hitTestable(), findsOneWidget);
    expect(
      tester.getSize(nextButton).shortestSide,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );
    await tester.tapAt(tester.getTopLeft(nextButton) + const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
