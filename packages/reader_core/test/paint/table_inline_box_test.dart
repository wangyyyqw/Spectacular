import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final table in [true, false]) {
    test(table ? '右对齐表格单元格绘制行内评级盒及文字' : '正文为前置行内标签保留占位宽度', () async {
      final cellStyle = ComputedStyle({
        'font-size': '12px',
        'font-family': 'Ahem',
        'text-align': 'right',
      });
      final badgeStyle = ComputedStyle({
        'font-size': '12px',
        'font-family': 'Ahem',
        'color': '#0000ff',
        'background-color': '#ff0000',
        'border': '2px solid #00ff00',
        'padding': '2px',
      }, hasExplicitTextColor: true);
      final badgeLayout = TextLayoutEngine.layout(
        text: 'S',
        style: badgeStyle,
        maxWidth: 24,
      );
      final badge = PageBlock.styled(
        layout: badgeLayout,
        style: badgeStyle,
        containingWidth: 32,
      );
      final layout = TextLayoutEngine.layout(
        text: table ? '' : 'AA',
        style: cellStyle,
        maxWidth: 100,
        inlineBoxes: [
          InlineBoxSpec(
            offset: 0,
            width: 32,
            height: 32,
            contentBaseline: 20,
            payload: badge,
          ),
        ],
      );
      final line = layout.lines.single;
      final placement = line.inlineBoxes.single;
      final badgeLeft = line.offsetX + placement.left;
      final badgeTop = line.baseline - line.top - placement.ascent;
      expect(badgeLeft, greaterThan(40), reason: '评级盒须靠单元格右侧');
      final block = PageBlock.styled(
        layout: layout,
        style: cellStyle,
        containingWidth: 100,
        table: !table
            ? null
            : TableRenderSpec(
                cells: [
                  TableCellRender(
                    row: 0,
                    rect: Rect.fromLTWH(0, 0, 100, layout.height),
                    layout: layout,
                    style: cellStyle,
                  ),
                ],
                columnXs: const [0, 100],
                rowYs: [0, layout.height],
                tableWidth: 100,
              ),
      );
      final page = Paginator(pageHeight: 100)
          .measureChapter(blocks: [block])
          .pages
          .single;
      final recorder = ui.PictureRecorder();
      const PagePainter().paint(
        Canvas(recorder),
        page,
        pageSize: const Size(120, 100),
      );
      final image = await recorder.endRecording().toImage(120, 100);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      List<int> pixel(int x, int y) => List.generate(
        4,
        (channel) => data.getUint8((y * 120 + x) * 4 + channel),
      );
      expect(pixel(badgeLeft.round(), badgeTop.round() + 10), [0, 255, 0, 255]);
      expect(pixel(badgeLeft.round() + 27, badgeTop.round() + 26), [
        255,
        0,
        0,
        255,
      ]);
      var blue = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i) < 40 &&
            data.getUint8(i + 1) < 40 &&
            data.getUint8(i + 2) > 200) {
          blue++;
        }
      }
      expect(blue, greaterThan(10), reason: '盒内容文字也必须绘制');
      if (!table) {
        var bodyInk = 0;
        for (var y = 0; y < 40; y++) {
          for (var x = (badgeLeft + placement.width).ceil(); x < 110; x++) {
            final color = pixel(x, y);
            if (color[0] < 40 && color[1] < 40 && color[2] < 40) bodyInk++;
          }
        }
        expect(bodyInk, greaterThan(30), reason: '正文必须在标签右边，不得叠在标签上');
      }
    });
  }

  test('单元格文字按格矩形裁剪，不画入后续行或下一表格区域', () async {
    final cellStyle = ComputedStyle({
      'font-size': '16px',
      'font-family': 'Ahem',
      'line-height': '20px',
      'color': '#000000',
    });
    final cellLayout = TextLayoutEngine.layout(
      text: 'AA\nBB',
      style: cellStyle,
      maxWidth: 100,
    );
    expect(cellLayout.height, greaterThan(32), reason: '测试文字须越过格底');
    final block = PageBlock.styled(
      layout: TextLayoutResult(
        text: '',
        lines: <LineBox>[
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: 80,
            baseline: 80,
            width: 100,
          ),
        ],
        width: 100,
        height: 80,
        maxWidth: 100,
        runs: <StyledRun>[],
      ),
      style: ComputedStyle({'font-size': '13px'}),
      containingWidth: 120,
      table: TableRenderSpec(
        cells: [
          TableCellRender(
            row: 0,
            rect: const Rect.fromLTWH(0, 0, 100, 30),
            layout: cellLayout,
            style: cellStyle,
          ),
        ],
        columnXs: const [0, 100],
        rowYs: const [0, 30, 80],
        tableWidth: 100,
      ),
    );
    final page = Paginator(pageHeight: 80)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    const PagePainter().paint(
      Canvas(recorder),
      page,
      pageSize: const Size(120, 80),
    );
    final image = await recorder.endRecording().toImage(120, 80);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    int darkPixels(int fromY, int toY) {
      var count = 0;
      for (var y = fromY; y < toY; y++) {
        for (var x = 0; x < 100; x++) {
          final offset = (y * 120 + x) * 4;
          if (data.getUint8(offset) < 40 &&
              data.getUint8(offset + 1) < 40 &&
              data.getUint8(offset + 2) < 40) {
            count += 1;
          }
        }
      }
      return count;
    }

    expect(darkPixels(0, 20), greaterThan(10), reason: '格内首行仍须绘制');
    expect(darkPixels(32, 80), 0, reason: '格底以下不得残留文字墨迹');
  });

  test('单元格绘制沿用测量换行宽度，不在窄内宽中重新换行', () async {
    final cellStyle = ComputedStyle({
      'font-size': '16px',
      'font-family': 'Ahem',
      'line-height': '20px',
      'color': '#000000',
      'padding': '8px 12px',
      'border': '1px solid #000000',
    });
    final cellLayout = TextLayoutEngine.layout(
      text: 'AA',
      style: cellStyle,
      maxWidth: 18,
    );
    expect(cellLayout.maxWidth, 48, reason: '行宽被正文 3em 下限钳制');
    expect(cellLayout.lineCount, 1, reason: '测量结果是一行');
    final block = PageBlock.styled(
      layout: TextLayoutResult(
        text: '',
        lines: <LineBox>[
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: 40,
            baseline: 40,
            width: 44,
          ),
        ],
        width: 44,
        height: 40,
        maxWidth: 44,
        runs: <StyledRun>[],
      ),
      style: ComputedStyle({'font-size': '13px'}),
      containingWidth: 60,
      table: TableRenderSpec(
        cells: [
          TableCellRender(
            row: 0,
            rect: const Rect.fromLTWH(0, 0, 44, 40),
            layout: cellLayout,
            style: cellStyle,
          ),
        ],
        columnXs: const [0, 44],
        rowYs: const [0, 40],
        tableWidth: 44,
      ),
    );
    final page = Paginator(pageHeight: 40)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    const PagePainter().paint(
      Canvas(recorder),
      page,
      pageSize: const Size(60, 40),
    );
    final image = await recorder.endRecording().toImage(60, 40);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    var rightInk = 0;
    for (var y = 0; y < 40; y++) {
      for (var x = 30; x < 42; x++) {
        final offset = (y * 60 + x) * 4;
        if (data.getUint8(offset) < 40 &&
            data.getUint8(offset + 1) < 40 &&
            data.getUint8(offset + 2) < 40) {
          rightInk += 1;
        }
      }
    }
    expect(rightInk, greaterThan(10), reason: '第二个字仍须留在首行可见');
  });
}
