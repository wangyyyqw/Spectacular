import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/icons/app_icon.dart';

Future<void> _writeWideCover(File file) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 50),
    Paint()..color = const Color(0xFF0000FF),
  );
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 50, 50),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(150, 0, 50, 50),
    Paint()..color = const Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 50);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

void main() {
  testWidgets('宽高缓存档位只限制尺寸，解码保持原封面比例', (tester) async {
    final directory = Directory.systemTemp.createTempSync('cover-aspect');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/wide.png');
    await tester.runAsync(() async {
      await _writeWideCover(file);
      for (final size in [
        const Size(92, 123),
        const Size(153, 204),
        const Size(66, 88),
      ]) {
        final result = Completer<ImageInfo>();
        final stream = coverImageProvider(
          file.path,
          coverDecodeWidth(size.width, 1),
          decodeHeight: coverDecodeHeight(size.height, 1),
        ).resolve(const ImageConfiguration());
        final listener = ImageStreamListener(
          (image, _) => result.complete(image),
          onError: result.completeError,
        );
        stream.addListener(listener);
        final image = await result.future;
        try {
          expect(
            image.image.width / image.image.height,
            closeTo(4, .15),
            reason: '原图为4:1，解码不能被两个缓存档位拉成其他比例',
          );
          expect(
            image.image.width,
            lessThanOrEqualTo(coverDecodeWidth(size.width, 1)),
          );
          expect(
            image.image.height,
            lessThanOrEqualTo(coverDecodeHeight(size.height, 1)),
          );
        } finally {
          stream.removeListener(listener);
          image.dispose();
        }
      }
    });
  });

  testWidgets('封面居中等比裁切并铺满三比四边框', (tester) async {
    final directory = Directory.systemTemp.createTempSync('cover-visible');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/wide.png');
    await tester.runAsync(() => _writeWideCover(file));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(key: ValueKey('precache'))),
      ),
    );
    final imageContext = tester.element(find.byKey(const ValueKey('precache')));
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(imageContext);
    final decodeWidth = coverDecodeWidth(100, devicePixelRatio);
    final decodeHeight = coverDecodeHeight(160, devicePixelRatio);
    await tester.runAsync(
      () => precacheImage(
        coverImageProvider(file.path, decodeWidth, decodeHeight: decodeHeight),
        imageContext,
      ),
    );
    final book = BookEntry(
      id: 'cover',
      title: '横向封面',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: file.path,
      readabilityLevel: 2,
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: BookCoverImage(book: book, width: 100, height: 160),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pixels = (await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final result = (width: image.width, bytes: bytes);
      image.dispose();
      return result;
    }))!;
    final bytes = pixels.bytes;
    final left = (80 * pixels.width + 10) * 4;
    final right = (80 * pixels.width + 90) * 4;
    expect(bytes[left], 0, reason: '左侧边缘必须被裁掉');
    expect(bytes[left + 1], 0);
    expect(bytes[left + 2], 255, reason: '裁切后应显示居中内容');
    expect(bytes[right], 0);
    expect(bytes[right + 1], 0);
    expect(bytes[right + 2], 255, reason: '裁切后应显示居中内容');
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(find.byType(AppIcon), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('可按需应用与搜索栏一致的轻阴影', (tester) async {
    final book = BookEntry(
      id: 'shadow',
      title: '立体封面',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
    );
    final theme = ThemeData();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: BookCoverImage(
            book: book,
            width: 100,
            height: 140,
            showShadow: true,
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(BookCoverImage),
        matching: find.byType(Material),
      ),
    );
    expect(material.elevation, 2);
    expect(
      material.shadowColor,
      theme.colorScheme.shadow.withValues(alpha: .12),
    );
  });

  testWidgets('封面解码宽度与预解码共用同一图像源', (tester) async {
    final book = BookEntry(
      id: 'preload',
      title: '预解码封面',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: '/封面/预解码.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BookCoverImage(book: book, width: 100, height: 160),
          ),
        ),
      ),
    );
    final expectedWidth = coverDecodeWidth(100, tester.view.devicePixelRatio);
    final expectedHeight = coverDecodeHeight(160, tester.view.devicePixelRatio);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      coverImageProvider(
        book.coverPath!,
        expectedWidth,
        decodeHeight: expectedHeight,
      ),
      reason: '首屏预解码与显示必须命中同一份缓存，否则仍会重新解码',
    );
  });

  testWidgets('窗口尺寸变化保留已加载封面并按档位复用图像源', (tester) async {
    final directory = Directory.systemTemp.createTempSync('cover-resize');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/cover.png');
    await tester.runAsync(() => _writeWideCover(file));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(key: ValueKey('precache'))),
      ),
    );
    final imageContext = tester.element(find.byKey(const ValueKey('precache')));
    final dpr = MediaQuery.devicePixelRatioOf(imageContext);
    await tester.runAsync(
      () => precacheImage(
        coverImageProvider(
          file.path,
          coverDecodeWidth(100, dpr),
          decodeHeight: coverDecodeHeight(160, dpr),
        ),
        imageContext,
      ),
    );
    final book = BookEntry(
      id: 'resize',
      title: '窗口缩放',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: file.path,
    );
    Widget host(double width, double height) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: BookCoverImage(book: book, width: width, height: height),
        ),
      ),
    );
    final placeholder = find.byKey(const ValueKey('cover-placeholder-resize'));
    await tester.pumpWidget(host(100, 160));
    await tester.pumpAndSettle();
    expect(placeholder, findsNothing);
    final before = tester.widget<Image>(find.byType(Image)).image;

    await tester.pumpWidget(host(103, 165));
    await tester.pump();
    expect(tester.widget<Image>(find.byType(Image)).image, before);
    expect(placeholder, findsNothing);

    await tester.pumpWidget(host(260, 347));
    await tester.pump();
    expect(placeholder, findsNothing);
  });

  test('封面解码尺寸按 64 像素档位稳定并限制在 96～1200', () {
    expect(coverDecodeWidth(20, 2), 96);
    expect(coverDecodeWidth(100, 3), 320);
    expect(coverDecodeWidth(103, 3), 320);
    expect(coverDecodeWidth(1000, 4), 1200);
    expect(coverDecodeHeight(20, 2), 96);
    expect(coverDecodeHeight(160, 3), 512);
    expect(coverDecodeHeight(1000, 4), 1200);
  });

  testWidgets('布局重建且目标尺寸尚未解码时复用旧封面，不露出占位', (tester) async {
    final directory = Directory.systemTemp.createTempSync('cover-switch');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/cover.png');
    await tester.runAsync(() => _writeWideCover(file));
    final book = BookEntry(
      id: 'switch',
      title: '视图切换封面',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: file.path,
    );
    Widget host(String view, double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: BookCoverImage(
            key: ValueKey(view),
            book: book,
            width: width,
            height: width * 4 / 3,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(key: ValueKey('warmup'))),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byKey(const ValueKey('warmup')));
      await precacheImage(
        coverImageProvider(
          file.path,
          coverDecodeWidth(120, tester.view.devicePixelRatio),
          decodeHeight: coverDecodeHeight(160, tester.view.devicePixelRatio),
        ),
        context,
      );
    });
    await tester.pumpWidget(host('grid', 120));
    await tester.pumpAndSettle();
    final oldProvider = tester.widget<Image>(find.byType(Image)).image;
    await tester.pumpWidget(host('list', 66));
    expect(
      find.byKey(const ValueKey('cover-placeholder-switch')),
      findsNothing,
    );
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .any((image) => image.image == oldProvider),
      isTrue,
      reason: '新组件在不同解码尺寸准备好之前仍显示已加载封面',
    );
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      isTrue,
    );
    await tester.runAsync(() => file.delete());
    await tester.pumpWidget(host('missing', 260));
    final context = tester.element(find.byType(BookCoverImage));
    var failed = false;
    final stream = coverImageProvider(
      file.path,
      coverDecodeWidth(260, tester.view.devicePixelRatio),
      decodeHeight: coverDecodeHeight(
        260 * 4 / 3,
        tester.view.devicePixelRatio,
      ),
    ).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (_, _) => fail('文件已删除，不能解码新尺寸'),
      onError: (_, _) => failed = true,
    );
    stream.addListener(listener);
    for (var attempt = 0; !failed && attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    stream.removeListener(listener);
    await tester.pumpAndSettle();
    expect(failed, isTrue);
    expect(
      find.byKey(const ValueKey('cover-placeholder-switch')),
      findsOneWidget,
      reason: '新尺寸确实加载失败后清除旧预览，恢复书名占位',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('封面文件缺失时显示书名占位，不叠加警告标识', (tester) async {
    final book = BookEntry(
      id: 'missing',
      title: '测试书',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: '/不存在的封面.png',
      readabilityLevel: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BookCoverImage(book: book, width: 100, height: 160),
          ),
        ),
      ),
    );
    var failed = false;
    final stream = tester
        .widget<Image>(find.byType(Image))
        .image
        .resolve(
          createLocalImageConfiguration(
            tester.element(find.byType(BookCoverImage)),
          ),
        );
    final listener = ImageStreamListener(
      (_, _) => fail('缺失的封面不应解码成功'),
      onError: (_, _) => failed = true,
    );
    stream.addListener(listener);
    for (var attempt = 0; !failed && attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    stream.removeListener(listener);
    expect(failed, isTrue, reason: '必须等到真实文件加载失败后验证占位');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cover-placeholder-missing')),
      findsOneWidget,
    );
    expect(find.byType(AppIcon), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(find.text('测试书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final level in [2, 3, 4]) {
    testWidgets('可读性等级 $level 的无封面书籍仅显示书名占位', (tester) async {
      final book = BookEntry(
        id: 'placeholder-$level',
        title: '朕',
        author: '',
        filePath: '',
        addedAt: DateTime(2026),
        readabilityLevel: level,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BookCoverImage(book: book, width: 120, height: 160),
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('cover-placeholder-${book.id}')),
        findsOneWidget,
      );
      expect(find.text('朕'), findsOneWidget);
      expect(find.byType(AppIcon), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
