import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _pageSize = ui.Size(320, 300);
const _tagBackground = 0x2b1f3dff;

Future<PageContent> _tagPage(String side, String width) async {
  final source = await openCssChapter(
    body:
        '<div class="outer"><div class="card">'
        '<p class="title"><span class="tag">【欺诈】法师</span>'
        '诡术大师</p><p>模糊事实，变假为真。</p></div></div>',
    css:
        'body { margin: 0; } p { margin: 0; } '
        '.outer { margin: 12px; padding: 18px; '
        'border: 3px double #f3d382; background: #101827; } '
        '.card { margin: 10px 0; padding: 12px 16px; '
        'border: 1px solid #2a3a58; border-top: 2px solid #e2b867; '
        'background: #0d131f; font-size: 14px; } '
        '.title { margin: 0 0 8px; padding: 0 0 6px; clear: both; } '
        '.tag { float: $side; $width padding: 2px 8px; '
        'margin: 0 5px 0 3px; border: 1px solid #f3d382; '
        'background: #2b1f3d; color: transparent; font-size: 11px; }',
    contentWidth: _pageSize.width,
    contentHeight: _pageSize.height,
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(ui.Canvas(recorder), page, pageSize: _pageSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 300);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _pixel(ByteData data, int x, int y) =>
    data.getUint32((y * _pageSize.width.toInt() + x) * 4);

Future<void> _expectTagPaintBounds(PageContent page) async {
  final tag = page.slices.singleWhere((slice) => slice.block.floatSide != null);
  final style = tag.block.style!;
  final model = BoxModel.fromStyle(style, containingWidth: 320);
  final left = tag.leftInset + style.margin.left;
  final right = left + model.borderBoxWidth(tag.block.layout.maxWidth);
  final row = (tag.absoluteTop! + tag.height / 2).floor();
  final pixels = await _render(page);
  final purple = [
    for (var x = 0; x < _pageSize.width; x++)
      if (_pixel(pixels, x, row) == _tagBackground) x,
  ];
  expect(purple, isNotEmpty);
  expect(purple.first, closeTo(left + model.borders.left, 1));
  expect(purple.last + 1, closeTo(right - model.borders.right, 1));
  expect(_pixel(pixels, (right - 1).floor(), row), 0xf3d382ff);

  final outer = tag.block.containers.first.container;
  final withoutTag = await _render(
    PageContent(
      spineIndex: page.spineIndex,
      pageIndex: page.pageIndex,
      slices: page.slices.where((slice) => !identical(slice, tag)).toList(),
      usedHeight: page.usedHeight,
      pageHeight: page.pageHeight,
      topPadding: page.topPadding,
    ),
  );
  // 标签所在高度的双金线必须与无标签时逐像素一致，不能被背景遮掉。
  for (
    var x = (outer.left + outer.width - 3).ceil();
    x < outer.left + outer.width;
    x++
  ) {
    expect(_pixel(pixels, x, row), _pixel(withoutTag, x, row));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final side in ['left', 'right']) {
    for (final width in {
      '自动宽': '',
      '定宽内容盒': 'width: 90px;',
      '百分比边框盒': 'width: 60%; box-sizing: border-box;',
    }.entries) {
      test('嵌套卡片 $side 浮动${width.key}：背景和边框不越界遮住外框', () async {
        await _expectTagPaintBounds(await _tagPage(side, width.value));
      });
    }
  }
}
