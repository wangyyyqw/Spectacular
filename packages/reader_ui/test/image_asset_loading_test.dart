import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

class _StaticSource implements ReaderChapterSource {
  _StaticSource(this.page);
  final PageContent page;
  @override
  int get chapterCount => 1;
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [page];
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(3, 3);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets('阅读页应加载边框图及所有背景层', (tester) async {
    final style = ComputedStyle({
      'font-size': '16px',
      'border': '10px solid transparent',
      'border-image': 'url(border.png) 10 stretch',
      'background-image': 'url(front.png), url(back.png)',
    });
    expect(style.borderImage?.url, 'border.png');
    expect(style.backgroundLayers, hasLength(2));
    final layout = TextLayoutEngine.layout(
      text: '图片预取审计',
      style: style,
      maxWidth: 300,
    );
    final page = Paginator(pageHeight: 600)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 300,
            ),
          ],
        )
        .pages
        .single;
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    addTearDown(cache.clear);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _StaticSource(page),
          store: MemoryReaderProgressStore(),
          bookId: '图片预取',
          imageCache: cache,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requested, containsAll(['front.png', 'back.png', 'border.png']));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('实际阅读页绘制全部背景层和边框图像素', (tester) async {
    const colors = <String, Color>{
      'front.png': Color(0xffcd1234),
      'back.png': Color(0xff1256cd),
      'border.png': Color(0xff12cd56),
    };
    final assets = (await tester.runAsync(
      () async => <String, Uint8List>{
        for (final entry in colors.entries) entry.key: await _png(entry.value),
      },
    ))!;
    final style = ComputedStyle({
      'font-size': '16px',
      'border': '10px solid transparent',
      'border-image': 'url(border.png) 1 stretch',
      'background-image': 'url(front.png), url(back.png)',
      'background-size': '20px 20px, 100% 100%',
      'background-repeat': 'no-repeat',
    });
    final page = Paginator(pageHeight: 600)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: TextLayoutEngine.layout(
                text: '背景层与边框图',
                style: style,
                maxWidth: 300,
              ),
              style: style,
              containingWidth: 300,
            ),
          ],
        )
        .pages
        .single;
    final cache = DecodedImageCache(loadBytes: (url) async => assets[url]);
    addTearDown(cache.clear);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: ReaderPage(
            source: _StaticSource(page),
            store: MemoryReaderProgressStore(),
            bookId: '图片绘制',
            imageCache: cache,
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final url in assets.keys) {
        await cache.load(url, displayWidth: 300);
      }
    });
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final image =
        (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImageSync();
    final pixels = (await tester.runAsync(image.toByteData))!.buffer
        .asUint8List();
    image.dispose();
    for (final entry in colors.entries) {
      final rgb = entry.value.toARGB32() & 0xffffff;
      var count = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if ((pixels[i] << 16 | pixels[i + 1] << 8 | pixels[i + 2]) == rgb) {
          count++;
        }
      }
      expect(count, greaterThan(20), reason: '${entry.key} 应进入真实绘制');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
