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
}
