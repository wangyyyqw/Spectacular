import 'dart:io';
import 'dart:async';
import 'dart:convert';

import '../support/reader_pump.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/library/library_store.dart';

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
  testWidgets('豆瓣原节点异步失败后自动重试备用节点并解码封面', (tester) async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final client = HttpClient();
    HttpOverrides.global = overrides;
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    final hosts = <String>[];
    final referers = <String?>[];
    await tester.runAsync(() async {
      server.listen((request) {
        hosts.add(request.uri.path.substring(1));
        referers.add(request.headers.value('referer'));
        if (hosts.last == 'img9.doubanio.com') {
          request.response.statusCode = 403;
        } else {
          request.response.add(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg6GD4DwACnAGIgL4sqAAAAABJRU5ErkJggg==',
            ),
          );
        }
        unawaited(request.response.close());
      });
    });
    debugNetworkImageHttpClientProvider = () =>
        _CoverClient(client, server.port);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
      client.close(force: true);
      await tester.runAsync(() => server.close(force: true));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BookCoverImage(
            book: BookEntry(
              id: 'douban-retry',
              title: '豆瓣封面',
              author: '',
              filePath: '',
              addedAt: DateTime(2026),
              remoteCoverUrl: 'https://img9.doubanio.com/view/subject/m/public/test-retry.jpg',
            ),
            width: 100,
            height: 140,
          ),
        ),
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => hosts.length == 2,
      description: '豆瓣备用请求',
    );
    await pumpReaderUntilComplete(
      tester,
      () => find
          .byType(RawImage)
          .evaluate()
          .any((e) => (e.widget as RawImage).image != null),
      description: '封面解码',
    );
    expect(hosts, ['img9.doubanio.com', 'img3.doubanio.com']);
    expect(referers, everyElement('https://book.douban.com/'));
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = null;
    client.close(force: true);
    await tester.pumpWidget(const SizedBox());
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
    final decodeWidth = (100 * MediaQuery.devicePixelRatioOf(imageContext))
        .ceil()
        .clamp(96, 1200);
    await tester.runAsync(
      () => precacheImage(
        ResizeImage.resizeIfNeeded(decodeWidth, null, FileImage(file)),
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
              child: BookCoverImage(
                book: book,
                width: 100,
                height: 160,
                showReadabilityBadge: true,
              ),
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
    expect(find.byKey(const ValueKey('book-damaged-badge')), findsOneWidget);
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
    expect(expectedWidth, (100 * tester.view.devicePixelRatio).ceil());
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      coverImageProvider(book.coverPath!, expectedWidth),
      reason: '首屏预解码与显示必须命中同一份缓存，否则仍会重新解码',
    );
  });

  test('封面解码宽度限制在 96～1200', () {
    expect(coverDecodeWidth(20, 2), 96);
    expect(coverDecodeWidth(100, 3), 300);
    expect(coverDecodeWidth(1000, 4), 1200);
  });

  testWidgets('封面文件缺失时显示书名占位和结构异常提示', (tester) async {
    final book = BookEntry(
      id: 'missing',
      title: '测试书',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: '/不存在的封面.png',
      readabilityLevel: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BookCoverImage(
              book: book,
              width: 100,
              height: 160,
              showReadabilityBadge: true,
            ),
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
    expect(find.byKey(const ValueKey('book-damaged-badge')), findsOneWidget);
    expect(find.text('测试书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地没有封面时使用阅微云端封面', (tester) async {
    const url = 'https://cdn.reamicro.test/cloud.jpg';
    final book = BookEntry(
      id: 'remote-cover',
      title: '云端封面',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      remoteCoverUrl: url,
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

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect(
      (image.image as ResizeImage).imageProvider,
      isA<NetworkImage>().having((value) => value.url, 'url', url),
    );
  });

  testWidgets('本地封面存在时优先于阅微云端封面', (tester) async {
    final directory = Directory.systemTemp.createTempSync('cover-remote');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/local.png');
    await tester.runAsync(() => _writeWideCover(file));
    final book = BookEntry(
      id: 'local-cover',
      title: '本地封面',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      coverPath: file.path,
      remoteCoverUrl: 'https://cdn.reamicro.test/cloud.jpg',
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

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as ResizeImage).imageProvider,
      isA<FileImage>().having((value) => value.file.path, 'path', file.path),
    );
  });
}

class _CoverClient implements HttpClient {
  _CoverClient(this.client, this.port);
  final HttpClient client;
  final int port;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => client.getUrl(
    Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/${url.host}'),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
