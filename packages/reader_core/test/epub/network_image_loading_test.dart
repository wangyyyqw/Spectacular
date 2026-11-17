import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/chapter/network_image_loader.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _options = ReaderOpenOptions(
  contentWidth: 366.6666666666667,
  contentHeight: 773.1694444444443,
);

Uint8List _book(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
      '</rootfiles></container>',
  'OEBPS/book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">network-images</dc:identifier>'
      '<dc:title>网络图片回归</dc:title></metadata><manifest>'
      '<item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'OEBPS/chapter.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<style>body {margin:0;} $css</style></head><body>$body</body></html>',
});

Future<Uint8List> _imageBytes() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff008800), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(678, 924);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<List<File>> _cachedFiles(Directory root) async {
  final directory = Directory('${root.path}/epub_network_images');
  if (!await directory.exists()) return [];
  return directory.list().where((entry) => entry is File).cast<File>().toList();
}

Future<int> _paintGreenPixels(PageContent page, DecodedImageCache cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: cache.lookup)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final painted = await picture.toImage(384, 854);
  final pixels = (await painted.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!;
  painted.dispose();
  picture.dispose();
  var count = 0;
  for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
    if (pixels.getUint8(offset) == 0 &&
        pixels.getUint8(offset + 1) == 136 &&
        pixels.getUint8(offset + 2) == 0) {
      count += 1;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List image;
  late Directory root;
  late HttpServer server;
  late List<Uri> requests;
  late Future<void> Function(HttpRequest) respond;
  final originalOverrides = HttpOverrides.current;

  setUpAll(() async {
    // 本地 HTTP 服务替代公网，允许正式加载器使用真实网络连接。
    HttpOverrides.global = null;
    image = await _imageBytes();
  });
  tearDownAll(() => HttpOverrides.global = originalOverrides);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reader-network-images-');
    addTearDown(() => root.delete(recursive: true));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    requests = [];
    respond = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = image.length;
      request.response.add(image);
      await request.response.close();
    };
    server.listen((request) {
      requests.add(request.uri);
      unawaited(respond(request));
    });
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<EpubChapterSource> open(
    String body, {
    String css = '',
    bool fromFile = false,
  }) async {
    final opener = EpubFormatOpener(
      networkImageCacheDirectoryProvider: () async => root,
    );
    final bytes = _book(body, css);
    final source = fromFile
        ? await opener.openFile(
            await File('${root.path}/book.epub').writeAsBytes(bytes),
            options: _options,
          )
        : await opener.openBytes(bytes, options: _options);
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    await source.applyOverrides(
      const ReaderOverrides(
        fontSize: 18,
        lineHeight: 1.6,
        paragraphSpacing: 10,
      ),
    );
    await source.applyContentSize(
      width: _options.contentWidth,
      height: _options.contentHeight,
      topInset: _insets.top,
      sideInsets: (left: _insets.left, right: _insets.right),
    );
    return source;
  }

  test('原始网址合并并发和重定向，文件入口重开后离线读取持久缓存', () async {
    respond = (request) async {
      if (request.uri.path == '/stable.png') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/signed.png?token=temporary',
        );
      } else {
        request.response.add(image);
      }
      await request.response.close();
    };
    final address = url('/stable.png?version=1');
    final body = '<p>正文</p><img src="$address" style="width:100%"/>';
    final source = await open(body);
    final results = await Future.wait([
      source.readImageBytes('$address#first'),
      source.readImageBytes('$address#second'),
    ]);
    expect(results.first, image);
    expect(results.last, same(results.first));
    expect(requests.map((request) => request.path), [
      '/stable.png',
      '/signed.png',
    ]);
    expect(await _cachedFiles(root), hasLength(1));
    source.close();
    await source.preparationsStopped;
    await server.close(force: true);

    final reopened = await open(body, fromFile: true);
    expect(await reopened.readImageBytes(address), image);
    final cache = DecodedImageCache(loadBytes: reopened.readImageBytes);
    addTearDown(cache.clear);
    expect(
      await cache.load(
        address,
        displayWidth: 366.6667,
        devicePixelRatio: 2.8125,
      ),
      isNotNull,
      reason: '服务停止后，新书籍来源和新解码缓存仍须显示已下载的图片',
    );
    expect(requests, hasLength(2));
  });

  for (final kind in ['块图', '行内图', '行内自然尺寸', '浮动自然尺寸', 'CSS 背景']) {
    test('$kind 使用正式资源入口解码绘制，保留正文和既有页面几何', () async {
      final address = url('/photo.png');
      final body = switch (kind) {
        '块图' =>
          '<h1>作者简介</h1><div class="portrait">'
              '<img src="$address" style="width:100%"/>'
              '<p>David G.Myers</p></div><p>附近正文</p>',
        '行内图' =>
          '<p>正文甲<img src="$address" style="width:36px;height:48px"/>正文乙</p>',
        '行内自然尺寸' =>
          '<p>正文甲<img src="$address" style="width:36px;height:auto"/>正文乙</p>',
        '浮动自然尺寸' =>
          '<p><img src="$address" style="float:left;width:36px;height:auto"/>'
              '附近正文</p><p>第二段</p>',
        _ => '<p class="background">附近正文</p>',
      };
      final source = await open(
        body,
        css:
            '.portrait {text-align:center;margin:1em 0;}'
            '.background {width:72px;height:54px;'
            'background-image:url("$address");background-size:cover;}',
      );
      final pages = await source.loadChapter(0);
      expect(pages, hasLength(1));
      expect(requests, hasLength(kind == 'CSS 背景' ? 0 : 1));
      if (kind == '块图') {
        final block = pages.single.slices
            .singleWhere((slice) => slice.block.isReplaced)
            .block;
        expect(block.style!.backgroundImage, address);
        expect(block.layout.maxWidth, closeTo(366.6666666666667, .01));
        expect(block.height, closeTo(_options.contentWidth * 924 / 678, .01));
      }
      if (kind == '行内自然尺寸') {
        final box = pages.single.slices
            .expand((slice) => slice.block.layout.lines)
            .expand((line) => line.inlineBoxes)
            .single;
        expect(box.spec.height, closeTo(36 * 924 / 678, .01));
      }
      if (kind == '浮动自然尺寸') {
        final block = pages.single.slices
            .singleWhere((slice) => slice.block.floatSide != null)
            .block;
        expect(block.height, closeTo(36 * 924 / 678, .01));
      }
      final cache = DecodedImageCache(loadBytes: source.readImageBytes);
      addTearDown(cache.clear);
      expect(
        await cache.load(
          address,
          displayWidth: _options.contentWidth,
          devicePixelRatio: 2.8125,
        ),
        isNotNull,
      );
      expect(await source.loadChapter(0), same(pages));
      expect(
        await _paintGreenPixels(pages.single, cache),
        greaterThan(300),
        reason: '正式绘制必须使用下载的位图',
      );
      expect(requests, hasLength(1));
    });
  }

  test('HTTP 错误和错误页面不写缓存，下次读取可以重试', () async {
    respond = (request) async {
      if (requests.length == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else if (requests.length == 2) {
        request.response.write('<html>不是图片</html>');
      } else {
        request.response.add(image);
      }
      await request.response.close();
    };
    final source = await open('<p>正文</p>');
    final address = url('/retry.png');
    expect(await source.readImageBytes(address), isNull);
    expect(await _cachedFiles(root), isEmpty);
    expect(await source.readImageBytes(address), isNull);
    expect(await _cachedFiles(root), isEmpty);
    expect(await source.readImageBytes(address), image);
    expect(requests, hasLength(3));
    expect(await _cachedFiles(root), hasLength(1));
  });

  test('损坏缓存重新下载，查询参数区分不同图片资源', () async {
    final source = await open('<p>正文</p>');
    final first = url('/photo.png?version=1');
    final second = url('/photo.png?version=2');
    expect(await source.readImageBytes(first), image);
    final file = (await _cachedFiles(root)).single;
    await file.writeAsString('损坏缓存');
    expect(await source.readImageBytes(first), image);
    expect(await source.readImageBytes(second), image);
    expect(requests, hasLength(3));
    expect(await _cachedFiles(root), hasLength(2));
  });

  test('缓存目录无法写入时仍显示网络图片', () async {
    final blocked = await File('${root.path}/blocked').writeAsString('文件');
    final opener = EpubFormatOpener(
      networkImageCacheDirectoryProvider: () async => Directory(blocked.path),
    );
    final source = await opener.openBytes(
      _book('<p>正文</p>', ''),
      options: _options,
    );
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    expect(await source.readImageBytes(url('/photo.png')), image);
    expect(await _cachedFiles(root), isEmpty);
  });

  test('超出单图上限的响应不写缓存，也不阻断章节读取', () async {
    respond = (request) async {
      request.response.contentLength = NetworkImageLoader.maxImageBytes + 1;
      request.response.add([0]);
      await request.response.flush();
    };
    final source = await open('<p>正文继续阅读</p>');
    expect(await source.loadChapter(0), hasLength(1));
    expect(requests, isEmpty, reason: '纯正文不会读取网络资源');
    expect(await source.readImageBytes(url('/large.png')), isNull);
    expect(await _cachedFiles(root), isEmpty);
    expect(await source.loadChapter(0), hasLength(1));
  });

  test('关闭书籍取消未完成的网络请求，等待资源释放后不发布旧图片', () async {
    final received = Completer<void>();
    respond = (request) async => received.complete();
    final source = await open('<p>正文</p>');
    final pending = source.readImageBytes(url('/waiting.png'));
    await received.future;
    source.close();
    await source.preparationsStopped.timeout(const Duration(seconds: 2));
    expect(await pending, isNull);
    expect(await source.readImageBytes(url('/waiting.png')), isNull);
    expect(await _cachedFiles(root), isEmpty);
  });

  test('持久缓存达到条数上限时淘汰最久未读的资源', () async {
    final source = await open('<p>正文</p>');
    for (var index = 0; index < NetworkImageLoader.maxCacheEntries; index++) {
      expect(
        await source.readImageBytes(url('/photo.png?index=$index')),
        image,
      );
    }
    expect(await source.readImageBytes(url('/photo.png?index=0')), image);
    expect(await source.readImageBytes(url('/photo.png?index=256')), image);
    expect(
      await _cachedFiles(root),
      hasLength(NetworkImageLoader.maxCacheEntries),
    );
    final before = requests.length;
    expect(await source.readImageBytes(url('/photo.png?index=0')), image);
    expect(requests, hasLength(before), reason: '刚读取的缓存应保留');
    expect(await source.readImageBytes(url('/photo.png?index=1')), image);
    expect(requests, hasLength(before + 1), reason: '最旧资源应已淘汰并重新下载');
  });
}
