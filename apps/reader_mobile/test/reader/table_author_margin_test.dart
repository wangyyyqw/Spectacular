import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

Future<PageContent> _page(String css, {String attributes = ''}) async {
  final source = await openCssChapter(
    body: '<table $attributes><tr><td>甲</td><td>乙</td></tr></table>',
    css:
        'body {margin:0 1%; font:16px Ahem;} '
        'table {margin:0 auto; border-spacing:0; background:#1122aa;} '
        'td {width:10px; padding:0; font:10px Ahem;} $css',
    contentWidth: 300,
    contentHeight: 300,
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).single;
}

Future<void> _expectPaintLeft(PageContent page, int left, int width) async {
  final recorder = ui.PictureRecorder();
  PagePainter().paint(
    ui.Canvas(recorder),
    page,
    pageSize: const ui.Size(300, 300),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 300);
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final colored = <int>{};
  for (var y = 0; y < 40; y++) {
    for (var x = 0; x < 300; x++) {
      if (pixels!.getUint32((y * 300 + x) * 4) == 0x1122aaff) {
        colored.add(x);
      }
    }
  }
  final columns = colored.toList()..sort();
  expect(columns.first, left);
  expect(columns.last + 1, left + width);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自动列宽表格在作者 body 内容盒内居中，绘制位置同步', () async {
    final page = await _page('');
    final block = page.slices.single.block;
    expect(block.table!.tableWidth, closeTo(20, .01));
    expect(block.style!.margin.left, closeTo(140, .01));
    expect(block.style!.margin.right, closeTo(140, .01));
    await _expectPaintLeft(page, 140, 20);
  });

  test('百分比表宽先按完整父盒解算，自动外边距不重复收窄宽度', () async {
    final page = await _page('table {width:50%;} td {width:auto;}');
    final block = page.slices.single.block;
    expect(block.table!.tableWidth, closeTo(147, .01));
    expect(block.style!.margin.left, closeTo(76.5, .01));
    expect(block.style!.margin.right, closeTo(76.5, .01));
  });

  for (final side in ['left', 'right']) {
    test('单侧 $side 自动外边距分配表宽之外的余量，保留另一侧声明', () async {
      final page = await _page(
        'table {margin-left:${side == 'left' ? 'auto' : '12px'}; '
        'margin-right:${side == 'right' ? 'auto' : '12px'};}',
      );
      final margin = page.slices.single.block.style!.margin;
      expect(margin.left, closeTo(side == 'left' ? 265 : 15, .01));
      expect(margin.right, closeTo(side == 'right' ? 265 : 15, .01));
    });
  }

  test('HTML cellspacing 提示进入列坐标，显式作者 CSS 优先且 collapse 清零', () async {
    for (final css in ['initial', '6px']) {
      final page = await _page(
        'table {border-spacing:$css;}',
        attributes: 'cellspacing="10px"',
      );
      expect(
        page.slices.single.block.table!.cells.first.rect.left,
        css == '6px' ? 6 : 0,
      );
    }
    final source = await openCssChapter(
      body: '<table cellspacing="10px"><tr><td>甲</td></tr></table>',
      css: 'body {margin:0;} td {padding:0;}',
      contentWidth: 300,
      contentHeight: 300,
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).single.slices.single.block;
    expect(block.table!.cells.first.rect.left, 10);
    expect(block.style!.borderSpacing.left, 10);
    final collapsed = await _page(
      'table {border-collapse:collapse;}',
      attributes: 'cellspacing="10px"',
    );
    expect(collapsed.slices.single.block.table!.cells.first.rect.left, 0);
  });
}
