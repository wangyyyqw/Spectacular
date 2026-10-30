import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _size = Size(300, 500);
const _insets = EdgeInsets.fromLTRB(20, 80, 20, 20);
const _bannerColor = Color(0xFFE06020);

Future<ui.Image> _banner() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 200, 60), Paint()..color = _bannerColor);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 60);
  picture.dispose();
  return image;
}

Future<ByteData> _render(PageContent page, ui.Image banner) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => banner)
      .paint(Canvas(recorder), page, pageSize: _size, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 500);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Color _pixel(ByteData data, int x, int y) {
  final offset = (y * 300 + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

Future<PageContent> _bannerPage(ui.Image banner, {required bool fixed}) async {
  final png = await banner.toByteData(format: ui.ImageByteFormat.png);
  // 原章后面的 span 升为块级，触发保留 body 容器的路径。
  final source = await openCssChapter(
    body:
        '<div class="logo"><img src="../Images/logo.png" '
        'class="responsive-image"/></div>'
        '<h2><span>第1章</span><br/>财富隐藏在报纸里</h2><p>正文</p>'
        '<span class="custom-width"><p>报纸摘录</p></span>'
        '${fixed ? '<div class="badge">固定标记</div>' : ''}',
    css:
        'html, body { margin: 0; padding: 0; height: 100%; width: 100%; }'
        '.logo { duokan-bleed: lefttopright; }'
        '.logo .responsive-image { width: 100%; }'
        '.custom-width { display: block; }'
        '.badge { position: fixed; top: 200px; }',
    binaryFiles: {'OEBPS/Images/logo.png': png!.buffer.asUint8List()},
    contentWidth: 300,
    contentHeight: 500,
    overrides: const ReaderOverrides(
      padding: CssEdges(left: 20, top: 80, right: 20, bottom: 20),
    ),
  );
  return (await source.loadChapter(0)).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fixed in [false, true]) {
    test('千禧章首结构的头图贴左上右边（含固定定位：$fixed）', () async {
      final banner = await _banner();
      addTearDown(banner.dispose);
      final page = await _bannerPage(banner, fixed: fixed);
      final image = page.slices.first.block;
      expect(image.containers.first.container.isPageRoot, isTrue);
      expect(
        image.containers.first.container.style.overflow,
        CssOverflow.hidden,
      );
      expect(image.bleedTop, isTrue);
      final data = await _render(page, banner);
      expect(_pixel(data, 0, 0), _bannerColor, reason: '左上角不被 body 裁掉');
      expect(_pixel(data, 299, 0), _bannerColor, reason: '右上角不被 body 裁掉');
      expect(_pixel(data, 0, 200), const Color(0xFFFFFFFF), reason: '正文仍留白');
    });
  }
}
