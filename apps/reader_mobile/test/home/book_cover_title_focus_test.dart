import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_title_focus.dart';
import 'package:reader_mobile/home/book_cover_title_focus_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('书名可跨相邻识别行匹配并忽略标点', () {
    final bounds = findCoverTitleBounds('海边的·卡夫卡', [
      (text: '海边的', bounds: const Rect.fromLTRB(10, 20, 70, 40)),
      (text: '卡夫卡', bounds: const Rect.fromLTRB(12, 44, 72, 64)),
      (text: '村上春树', bounds: const Rect.fromLTRB(10, 100, 90, 120)),
    ]);

    expect(bounds, const Rect.fromLTRB(10, 20, 72, 64));
    expect(
      findCoverTitleBounds('无关书名', [
        (text: '海边的卡夫卡', bounds: const Rect.fromLTRB(0, 0, 60, 20)),
      ]),
      isNull,
    );
  });

  test('书名焦点位移受拼图可见区域限制，不会让裁切露底', () {
    final clip = Path()..addRect(const Rect.fromLTRB(-30, -50, 30, 50));
    const coverSize = Size(100, 140);
    const focus = CoverTitleFocus(
      imageSize: coverSize,
      titleBounds: Rect.fromLTRB(.4, .05, .6, .15),
    );

    final placement = coverTitleFocusPlacement(
      focus: focus,
      coverSize: coverSize,
      clipPath: clip,
      regionCenter: Offset.zero,
      rotation: 0,
    );

    final cover = Rect.fromCenter(
      center: placement.translation,
      width: placement.imageSize.width,
      height: placement.imageSize.height,
    );
    expect(placement.translation.dy, greaterThan(0));
    expect(cover.contains(const Offset(-30, -50)), isTrue);
    expect(cover.contains(const Offset(30, 50)), isTrue);
  });

  test('封面书名焦点按封面版本持久缓存', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cover-title-focus-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}/cover.png');
    await image.writeAsBytes([1, 2, 3]);
    var recognitions = 0;

    BookCoverTitleFocusStore createStore() => BookCoverTitleFocusStore(
      directoryProvider: () async => directory,
      supportsPlatform: () => true,
      imageSizeReader: (_) async => const Size(100, 200),
      recognizer: (_) async {
        recognitions++;
        return [(text: '旧书店', bounds: const Rect.fromLTRB(10, 20, 70, 40))];
      },
    );

    final first = await createStore().resolve(image.path, '旧书店');
    final second = await createStore().resolve(image.path, '旧书店');

    expect(first, isNotNull);
    expect(first!.titleBounds, const Rect.fromLTRB(.1, .1, .7, .2));
    expect(second?.titleBounds, first.titleBounds);
    expect(recognitions, 1);
  });

  test('未支持的平台安全回退，不访问图片和 OCR', () async {
    final store = BookCoverTitleFocusStore(
      supportsPlatform: () => false,
      recognizer: (_) async => throw StateError('不应调用 OCR'),
    );

    expect(await store.resolve('/missing/cover.png', '书名'), isNull);
  });

  test('并发焦点请求合并，未命中也缓存，书名或封面变化后重新识别', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cover-focus-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}/cover.png');
    await image.writeAsBytes([1, 2, 3]);
    final ready = Completer<void>();
    final gate = Completer<List<CoverTitleLine>>();
    var calls = 0;
    BookCoverTitleFocusStore createStore() => BookCoverTitleFocusStore(
      directoryProvider: () async => directory,
      supportsPlatform: () => true,
      imageSizeReader: (_) async => const Size(100, 200),
      recognizer: (_) async {
        calls++;
        if (!ready.isCompleted) ready.complete();
        return gate.future;
      },
    );
    final store = createStore();
    final first = store.resolve(image.path, '目标书名');
    await ready.future;
    final second = store.resolve(image.path, '目标书名');
    gate.complete([(text: '其他文字', bounds: const Rect.fromLTWH(0, 0, 50, 20))]);
    expect(await Future.wait([first, second]), [null, null]);
    expect(await createStore().resolve(image.path, '目标书名'), isNull);
    expect(calls, 1);
    expect(await store.resolve(image.path, '其他文字'), isNotNull);
    expect(calls, 2);
    await image.writeAsBytes([1, 2, 3, 4]);
    expect(await store.resolve(image.path, '其他文字'), isNotNull);
    expect(calls, 3);
  });

  test('识别失败不缓存失败结果，后续请求可以重试', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cover-focus-retry-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}/cover.png');
    await image.writeAsBytes([1]);
    var calls = 0;
    final store = BookCoverTitleFocusStore(
      directoryProvider: () async => directory,
      supportsPlatform: () => true,
      imageSizeReader: (_) async => const Size(100, 200),
      recognizer: (_) async {
        if (++calls == 1) throw StateError('模拟识别失败');
        return [(text: '旧书店', bounds: const Rect.fromLTWH(10, 20, 70, 40))];
      },
    );
    await expectLater(store.resolve(image.path, '旧书店'), throwsStateError);
    expect(await store.resolve(image.path, '旧书店'), isNotNull);
    expect(calls, 2);
  });

  test('大封面识别长边限制为1536，焦点仍按原图比例定位', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cover-focus-large-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final bitmap = await picture.toImage(2000, 3000);
    final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    bitmap.dispose();
    picture.dispose();
    final image = File('${directory.path}/cover.png');
    await image.writeAsBytes(png!.buffer.asUint8List());
    final store = BookCoverTitleFocusStore(
      directoryProvider: () async => directory,
      supportsPlatform: () => true,
      recognizer: (bytes) async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        expect(
          Size(descriptor.width.toDouble(), descriptor.height.toDouble()),
          const Size(1024, 1536),
        );
        descriptor.dispose();
        buffer.dispose();
        return [
          (
            text: '旧书店',
            bounds: const Rect.fromLTRB(102.4, 153.6, 819.2, 460.8),
          ),
        ];
      },
    );
    final focus = (await store.resolve(image.path, '旧书店'))!;
    expect(focus.imageSize, const Size(2000, 3000));
    expect(focus.titleBounds.left, closeTo(.1, .0001));
    expect(focus.titleBounds.top, closeTo(.1, .0001));
    expect(focus.titleBounds.right, closeTo(.8, .0001));
    expect(focus.titleBounds.bottom, closeTo(.3, .0001));
  });
}
