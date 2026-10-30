import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

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

Future<ByteData> _render(
  PageContent page,
  ui.Image banner, {
  double topInset = 80,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => banner).paint(
    Canvas(recorder),
    page,
    pageSize: _size,
    pageInsets: _insets.copyWith(top: topInset),
  );
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

Future<EpubChapterSource> _bannerSource(
  ui.Image banner, {
  bool fixed = false,
  bool bleed = true,
  String tail = '',
}) async {
  final png = await banner.toByteData(format: ui.ImageByteFormat.png);
  // 原章后面的 span 升为块级，触发保留 body 容器的路径。
  final source = await openCssChapter(
    body:
        '<div class="logo"><img src="../Images/logo.png" '
        'class="responsive-image"/></div>'
        '<h2><span>第1章</span><br/>财富隐藏在报纸里</h2><p>正文</p>'
        '<span class="custom-width"><p>报纸摘录</p></span>'
        '$tail'
        '${fixed ? '<div class="badge">固定标记</div>' : ''}',
    css:
        'html, body { margin: 0; padding: 0; height: 100%; width: 100%; }'
        '${bleed ? '.logo { duokan-bleed: lefttopright; }' : ''}'
        '.logo .responsive-image { width: 100%; }'
        'h2 { margin: 8px 0; background: #224466; font-size: 10px; line-height: 20px; }'
        '.custom-width { display: block; }'
        '.tail { margin: 0; font-size: 10px; line-height: 20px; }'
        '.badge { position: fixed; top: 200px; }',
    binaryFiles: {'OEBPS/Images/logo.png': png!.buffer.asUint8List()},
    contentWidth: 300,
    contentHeight: 500,
    overrides: const ReaderOverrides(
      padding: CssEdges(left: 20, top: 80, right: 20, bottom: 20),
    ),
  );
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fixed in [false, true]) {
    test('千禧章首结构的头图贴左上右边（含固定定位：$fixed）', () async {
      final banner = await _banner();
      addTearDown(banner.dispose);
      final source = await _bannerSource(banner, fixed: fixed);
      final page = (await source.loadChapter(0)).first;
      final image = page.slices.first.block;
      expect(image.containers.first.container.isPageRoot, isTrue);
      expect(
        image.containers.first.container.style.overflow,
        CssOverflow.hidden,
      );
      expect(image.bleedTop, isTrue);
      expect(page.topPadding, -80, reason: '章首图从页顶排版，不重复占页眉槽');
      final data = await _render(page, banner);
      expect(_pixel(data, 0, 0), _bannerColor, reason: '左上角不被 body 裁掉');
      expect(_pixel(data, 299, 0), _bannerColor, reason: '右上角不被 body 裁掉');
      expect(_pixel(data, 100, 89), _bannerColor);
      expect(
        _pixel(data, 100, 90),
        const Color(0xFFFFFFFF),
        reason: '图盒高度为 90',
      );
      expect(_pixel(data, 0, 97), const Color(0xFFFFFFFF));
      expect(
        _pixel(data, 20, 98),
        const Color(0xFF224466),
        reason: '只保留书籍标题上边距 8',
      );
      expect(_pixel(data, 0, 200), const Color(0xFFFFFFFF), reason: '正文仍留白');
      final title = TextHitTester.lineBoxes(page)
          .firstWhere((line) => line.text.isNotEmpty);
      expect(title.rect.top + 80, 98, reason: '命中位置与绘制位置一致');
      expect(page.hitTest(Offset(40, title.rect.top + 1))?.sliceIndex, 1);
      source.clearPaginationCache();
      final replayed = (await source.loadChapter(0)).first;
      expect(replayed.topPadding, page.topPadding);
      expect(replayed.usedHeight, page.usedHeight);
      expect(
        TextHitTester.lineBoxes(replayed)
            .firstWhere((line) => line.text.isNotEmpty)
            .rect,
        title.rect,
      );
    });
  }

  test('仅章首页回收上内缩，后续页与页底仍保留正文边界', () async {
    final banner = await _banner();
    addTearDown(banner.dispose);
    final tail = List.filled(60, '<p class="tail">后续正文</p>').join();
    final source = await _bannerSource(banner, tail: tail);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    expect(pages.first.topPadding, -80);
    expect(pages.first.usedHeight, greaterThan(400), reason: '第一页使用回收的空间');
    for (final page in pages) {
      expect(page.topPadding + page.usedHeight, lessThanOrEqualTo(402));
      if (page.pageIndex > 0) {
        expect(page.topPadding, 0);
        final lines = TextHitTester.lineBoxes(page);
        expect(lines.first.rect.top, greaterThanOrEqualTo(0));
        final data = await _render(page, banner);
        expect(_pixel(data, 20, 79), const Color(0xFFFFFFFF));
        expect(_pixel(data, 20, 482), const Color(0xFFFFFFFF));
      }
    }
    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(
      replayed.map((page) => page.topPadding),
      pages.map((page) => page.topPadding),
    );
    expect(
      replayed.map((page) => page.usedHeight),
      pages.map((page) => page.usedHeight),
    );
  });

  test('上内缩变化但正文宽高不变时重排，普通图不回收页眉槽', () async {
    final banner = await _banner();
    addTearDown(banner.dispose);
    final source = await _bannerSource(banner);
    await source.applyContentSize(width: 260, height: 400, topInset: 80);
    final before = await source.loadChapter(0);
    expect(
      await source.applyContentSize(width: 260, height: 400, topInset: 110),
      isTrue,
    );
    final after = await source.loadChapter(0);
    expect(after, isNot(same(before)));
    expect(after.first.topPadding, -110);
    final data = await _render(after.first, banner, topInset: 110);
    expect(_pixel(data, 20, 98), const Color(0xFF224466));
    expect(
      await source.applyContentSize(width: 260, height: 400, topInset: 110),
      isFalse,
    );
    final normal = await _bannerSource(banner, bleed: false);
    final page = (await normal.loadChapter(0)).first;
    expect(page.topPadding, 0);
    expect(
      TextHitTester.lineBoxes(page)
          .firstWhere((line) => line.text.isNotEmpty)
          .rect
          .top,
      86,
      reason: '普通图高为正文宽×比例（78）',
    );
    final normalData = await _render(page, banner);
    expect(_pixel(normalData, 0, 0), const Color(0xFFFFFFFF));
    expect(_pixel(normalData, 20, 166), const Color(0xFF224466));
  });
}
