import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/image_cache.dart';

Future<Uint8List> _pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF00FF00),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('解码按显示宽×DPR 降采样并缓存', () async {
    final bytes = await _pngBytes(100, 100);
    var loads = 0;
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        loads += 1;
        return url == 'a' ? bytes : null;
      },
    );

    final image = await cache.load('a', displayWidth: 25, devicePixelRatio: 2);
    expect(image, isNotNull);
    expect(image!.width, 50, reason: '25 逻辑像素 × DPR 2 → targetWidth 50');
    expect(loads, 1);
    expect(cache.length, 1);
    expect(cache.byteCount, greaterThan(0));
    expect(cache.revision, 1);

    // 命中缓存：不再读取字节。
    final again = await cache.load('a', displayWidth: 25, devicePixelRatio: 2);
    expect(identical(again, image), isTrue);
    expect(loads, 1);
    expect(identical(cache.lookup('a'), image), isTrue);
  });

  test('缺字节或坏字节返回 null，不抛异常', () async {
    final cache = DecodedImageCache(
      loadBytes: (url) async => url == 'bad' ? Uint8List(4) : null,
    );
    expect(await cache.load('missing', displayWidth: 20), isNull);
    expect(await cache.load('bad', displayWidth: 20), isNull);
    expect(cache.length, 0);
  });

  test('prefetch 只解码一次并返回新增张数', () async {
    final bytes = await _pngBytes(10, 10);
    var loads = 0;
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        loads += 1;
        return bytes;
      },
    );
    expect(await cache.prefetch(['a', 'b'], displayWidth: 10), 2);
    expect(await cache.prefetch(['a', 'b'], displayWidth: 10), 0);
    expect(loads, 2);
  });

  test('LRU：超过条数上限淘汰最久未用', () async {
    final bytes = await _pngBytes(10, 10);
    final cache = DecodedImageCache(
      loadBytes: (url) async => bytes,
      maxEntries: 1,
    );
    await cache.load('a', displayWidth: 10);
    await cache.load('b', displayWidth: 10);
    expect(cache.length, 1);
    expect(cache.lookup('a'), isNull);
    expect(cache.lookup('b'), isNotNull);
  });

  test('clear 释放全部条目', () async {
    final bytes = await _pngBytes(10, 10);
    final cache = DecodedImageCache(loadBytes: (url) async => bytes);
    await cache.load('a', displayWidth: 10);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.byteCount, 0);
    expect(cache.lookup('a'), isNull);
  });

  test('3000×4000 大图按显示宽×DPR 解码，内存 < 原图 25%（P3-08 验收）',
      () async {
    final bytes = await _pngBytes(3000, 4000);
    final originalBytes = 3000 * 4000 * 4;
    final cache = DecodedImageCache(
      loadBytes: (url) async => bytes,
    );
    final image = await cache.load('big', displayWidth: 600, devicePixelRatio: 2);
    expect(image, isNotNull);
    expect(image!.width, 1200, reason: '600 × DPR 2 → targetWidth 1200');
    expect(image.height, 1600, reason: '等比降采样');
    final decodedBytes = image.width * image.height * 4;
    expect(decodedBytes, lessThan(originalBytes * 0.25),
        reason: '1200×1600×4 = 7.68MB，原图 48MB 的 16%');
    expect(cache.intrinsicOf('big'), isNotNull);
    expect(cache.intrinsicOf('big')!.width, 3000, reason: '原始尺寸单独缓存');
  });

  test('显示宽×DPR 超过原图宽时封顶原图宽，不放大解码', () async {
    final bytes = await _pngBytes(100, 80);
    final cache = DecodedImageCache(loadBytes: (url) async => bytes);
    final image = await cache.load('small', displayWidth: 500, devicePixelRatio: 3);
    expect(image!.width, 100, reason: 'targetWidth 1500 封顶到原图宽 100');
    expect(image.height, 80);
  });

  test('并发同 URL 解码去重：共享同一 Future', () async {
    final bytes = await _pngBytes(50, 50);
    var loads = 0;
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        loads += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return bytes;
      },
    );
    final results = await Future.wait(<Future<ui.Image?>>[
      cache.load('same', displayWidth: 50),
      cache.load('same', displayWidth: 50),
      cache.load('same', displayWidth: 50),
    ]);
    expect(loads, 1, reason: '在途解码去重');
    expect(results[0], isNotNull);
    expect(identical(results[1], results[0]), isTrue);
  });
}
