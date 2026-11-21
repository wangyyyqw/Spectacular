import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_snapshot_cache.dart';

PageContent _page(int index) => PageContent(
  spineIndex: 0,
  pageIndex: index,
  slices: const [],
  usedHeight: 0,
  pageHeight: 100,
  topPadding: 0,
);

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认最多五张页面快照', () {
    final cache = PageSnapshotCache();
    expect(cache.maxEntries, 5);
    cache.clear();
  });

  test('超出五张时按最久未使用淘汰', () {
    final cache = PageSnapshotCache();
    final pages = [for (var index = 0; index < 6; index++) _page(index)];
    for (var index = 0; index < pages.length; index++) {
      cache.put(pages[index], _image(4, 4));
    }

    expect(cache.length, 5);
    expect(cache.get(pages.first), isNull);
    expect(cache.get(pages.last), isNotNull);
    expect(cache.bytes, 5 * 4 * 4 * 4);
    cache.clear();
  });

  test('受保护页面不参与淘汰', () {
    final cache = PageSnapshotCache(maxEntries: 2);
    final pages = [for (var index = 0; index < 3; index++) _page(index)];
    cache
      ..protected = {pages.first}
      ..put(pages[0], _image(2, 2))
      ..put(pages[1], _image(2, 2))
      ..put(pages[2], _image(2, 2));

    expect(cache.get(pages.first), isNotNull);
    expect(cache.get(pages.last), isNotNull);
    expect(cache.get(pages[1]), isNull);
    expect(cache.length, 2);
    cache.clear();
  });

  test('clear 释放全部位图', () {
    final cache = PageSnapshotCache();
    final page = _page(0);
    final image = _image(2, 2);
    cache.put(page, image);
    expect(image.debugDisposed, isFalse);
    cache.clear();
    expect(image.debugDisposed, isTrue);
    expect(cache.bytes, 0);
    expect(cache.length, 0);
  });

  test('位图尺寸不影响五页数量限制', () {
    final cache = PageSnapshotCache();
    final pages = [for (var index = 0; index < 5; index++) _page(index)];
    for (final page in pages) {
      cache.put(page, _image(256, 256));
    }
    expect(cache.length, 5);
    expect(cache.bytes, 5 * 256 * 256 * 4);
    for (final page in pages) {
      expect(cache.get(page), isNotNull);
    }
    cache.clear();
  });
}
