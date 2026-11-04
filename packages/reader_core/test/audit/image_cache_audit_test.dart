import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/image_cache.dart';

Future<Uint8List> _pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('清空隔离旧请求并允许同 URL 重新解码', () async {
    final bytes = await _pngBytes(10, 10);
    final oldBytes = Completer<Uint8List?>();
    final newBytes = Completer<Uint8List?>();
    var loads = 0;
    final cache = DecodedImageCache(
      loadBytes: (_) => ++loads == 1 ? oldBytes.future : newBytes.future,
    );
    addTearDown(cache.clear);
    final oldLoad = cache.load('a', displayWidth: 10);
    cache.clear();
    final newLoad = cache.load('a', displayWidth: 10);
    expect(loads, 2, reason: '清空后不能复用旧代次的在途请求');
    oldBytes.complete(bytes);
    expect(await oldLoad, isNull);
    expect(cache.length, 0);
    expect(cache.intrinsicOf('a'), isNull);
    final concurrentLoad = cache.load('a', displayWidth: 10);
    expect(loads, 2, reason: '旧请求结束不能移除新请求的去重记录');
    newBytes.complete(bytes);
    final image = await newLoad;
    expect(image, isNotNull);
    expect(await concurrentLoad, same(image));
    expect(cache.length, 1);
    expect(cache.revision, 1);
  });

  test('超出解码预算返回 null，保留已有可用图片', () async {
    final small = await _pngBytes(2, 2);
    final large = await _pngBytes(10, 10);
    final cache = DecodedImageCache(
      loadBytes: (url) async => url == 'small' ? small : large,
      maxBytes: 100,
    );
    addTearDown(cache.clear);
    final image = await cache.load('small', displayWidth: 2);
    expect(await cache.load('large', displayWidth: 10), isNull);
    expect(cache.lookup('small'), same(image));
    expect(cache.lookup('large'), isNull);
    expect(cache.byteCount, 16);
    expect(cache.revision, 1);
  });

  test('零条目预算不返回已释放的图片', () async {
    final bytes = await _pngBytes(10, 10);
    final cache = DecodedImageCache(
      loadBytes: (_) async => bytes,
      maxEntries: 0,
    );
    addTearDown(cache.clear);
    expect(await cache.load('a', displayWidth: 10), isNull);
    expect(cache.length, 0);
    expect(cache.byteCount, 0);
  });
}
