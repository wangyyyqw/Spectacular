import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_margins.dart';

import '../support/reader_pump.dart';
import 'support/css_chapter_book.dart';

const _size = Size(300, 500);
const _insets = EdgeInsets.fromLTRB(20, 80, 20, 20);
const _bannerColor = Color(0xFFE06020);

Future<ui.Image> _banner({int width = 200, int height = 60}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = _bannerColor,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ByteData> _render(
  PageContent page,
  ui.Image banner, {
  EdgeInsets insets = _insets,
  double? topInset,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => banner).paint(
    Canvas(recorder),
    page,
    pageSize: _size,
    pageInsets: topInset == null ? insets : insets.copyWith(top: topInset),
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

Rect _imageBounds(ByteData data) {
  var left = 300;
  var top = 500;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < 500; y++) {
    for (var x = 0; x < 300; x++) {
      if (_pixel(data, x, y) != _bannerColor) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '图片必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (right + 1).toDouble(),
    (bottom + 1).toDouble(),
  );
}

Future<EpubChapterSource> _narrowImageSource(
  ui.Image image, {
  required String align,
  required bool topBleed,
}) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return openCssChapter(
    body:
        '<div><div class="logo"><img src="../Images/logo.png"/></div>'
        '<h3>序</h3><p>首段正文</p></div>',
    css:
        'body { margin: 0 1%; font-size: 16px; }'
        'div { margin: 0; padding: 0; }'
        '.logo { margin: 1.75em 0 0; text-align: $align; '
        'duokan-bleed: ${topBleed ? 'lefttopright' : 'leftright'}; }'
        'img { width: 30%; }'
        'h3 { margin: -4em 0 0; padding: 5px; width: 3em; '
        'font-size: 20px; line-height: 1.45; color: transparent; }'
        'p { margin: 10px 0 0; width: 170px; font-size: 10px; '
        'line-height: 20px; color: transparent; background: #224466; }',
    binaryFiles: {'OEBPS/Images/logo.png': png!.buffer.asUint8List()},
    contentWidth: 300,
    contentHeight: 500,
    overrides: const ReaderOverrides(
      padding: CssEdges(left: 20, top: 80, right: 20, bottom: 20),
    ),
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

  testWidgets('自定义左右页边距按实际页面宽计算出血窄图，不裁掉右侧', (tester) async {
    final image = (await tester.runAsync(
      () => _banner(width: 120, height: 180),
    ))!;
    addTearDown(image.dispose);
    final source = (await tester.runAsync(
      () => _narrowImageSource(image, align: 'right', topBleed: true),
    ))!;
    addTearDown(source.close);
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 500,
            child: ReaderPage(
              source: source,
              store: MemoryReaderProgressStore(),
              bookId: 'bleed-custom-margins',
              showPageFooter: false,
              overrides: source.overrides,
              margins: const ReaderMargins(
                left: 8,
                right: 12,
                topOuter: 80,
                topInner: 0,
                bottomInner: 0,
                bottomOuter: 20,
              ),
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    final page = session.page!;
    expect(source.contentWidth, 280);
    expect(page.slices.first.block.style!.width!.value, 90);
    expect(
      _imageBounds(
        (await tester.runAsync(
          () => _render(
            page,
            image,
            insets: const EdgeInsets.fromLTRB(8, 80, 12, 20),
          ),
        ))!,
      ),
      const Rect.fromLTWH(210, 0, 90, 135),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('正文宽高不变时实际左右内缩使窄图缓存失效，恢复时不沿用预览宽度', () async {
    final image = await _banner(width: 120, height: 180);
    addTearDown(image.dispose);
    final source = await _narrowImageSource(
      image,
      align: 'right',
      topBleed: true,
    );
    addTearDown(source.close);
    Future<bool> resize(double right) => source.applyContentSize(
      width: 280,
      height: 400,
      topInset: 80,
      sideInsets: (left: 8, right: right),
    );
    await resize(12);
    final before = await source.loadChapter(0);
    expect(before.first.slices.first.block.style!.width!.value, 90);
    expect(await resize(22), isTrue);
    final preview = await source.loadChapter(0);
    expect(preview, isNot(same(before)));
    expect(preview.first.slices.first.block.style!.width!.value, 93);
    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(replayed.first.slices.first.block.style!.width!.value, 93);
    expect(await resize(12), isTrue);
    final restored = (await source.loadChapter(0)).first;
    expect(restored.slices.first.block.style!.width!.value, 90);
    expect(
      _imageBounds(
        await _render(
          restored,
          image,
          insets: const EdgeInsets.fromLTRB(8, 80, 12, 20),
        ),
      ),
      const Rect.fromLTWH(210, 0, 90, 135),
    );
    expect(await resize(12), isFalse);
  });

  for (final topBleed in [false, true]) {
    for (final alignment in {
      'left': 0.0,
      'center': 105.0,
      'right': 210.0,
    }.entries) {
      test('30% 窄图保留尺寸和 ${alignment.key} 对齐（顶部出血：$topBleed）', () async {
        final image = await _banner(width: 120, height: 180);
        addTearDown(image.dispose);
        final source = await _narrowImageSource(
          image,
          align: alignment.key,
          topBleed: topBleed,
        );
        addTearDown(source.close);
        final page = (await source.loadChapter(0)).first;
        final block = page.slices.first.block;
        expect(block.style!.width!.value, 90, reason: '30% 使用出血包含块宽度');
        expect(block.layout.height, 135);
        expect(block.spaceBefore, 28, reason: '作者上边距保留在普通流中');
        final top = topBleed ? 0.0 : 108.0;
        final expected = Rect.fromLTWH(alignment.value, top, 90, 135);
        expect(_imageBounds(await _render(page, image)), expected);
        source.clearPaginationCache();
        final replayed = (await source.loadChapter(0)).first;
        expect(_imageBounds(await _render(replayed, image)), expected);
        expect(replayed.usedHeight, page.usedHeight);
      });
    }
  }

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
