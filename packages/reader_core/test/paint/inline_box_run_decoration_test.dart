import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 180;
const _height = 100;

ComputedStyle _style(Map<String, String> properties) => ComputedStyle({
  'font-size': '20px',
  'font-family': 'Ahem',
  'line-height': '2',
  'color': '#000000',
  ...properties,
});

Future<ByteData> _render({
  required Map<String, String> properties,
  required bool table,
  required bool crossBox,
  required bool withBox,
  bool selection = false,
}) async {
  final style = _style({});
  final layout = TextLayoutEngine.layout(
    text: 'AB',
    style: style,
    maxWidth: _width.toDouble(),
    runs: [
      StyledRun(start: crossBox ? 0 : 1, end: 2, style: _style(properties)),
    ],
    inlineBoxes: [
      if (withBox)
        InlineBoxSpec(
          offset: 1,
          width: 60,
          height: 20,
          payload: _style({'background-color': '#0000ff'}),
        ),
    ],
  );
  // 用真实布局结果驱动公共绘制入口，保证盒宽确实参与断行及文字定位。
  expect(layout.lines.single.width, withBox ? 100 : 40);
  final block = PageBlock.styled(
    layout: layout,
    style: style,
    containingWidth: _width.toDouble(),
    table: table
        ? TableRenderSpec(
            cells: [
              TableCellRender(
                row: 0,
                rect: Rect.fromLTWH(0, 0, _width.toDouble(), layout.height),
                layout: layout,
                style: style,
              ),
            ],
            columnXs: const [0, 180],
            rowYs: [0, layout.height],
            tableWidth: _width.toDouble(),
          )
        : null,
  );
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(blocks: [block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  PagePainter(
    selectionColor: const Color(0xFFFF0000),
    selection: selection
        ? PageSelection([
            SelectedTextRange(sliceIndex: 0, start: crossBox ? 0 : 1, end: 2),
          ])
        : null,
  ).paint(Canvas(recorder), page, pageSize: const Size(180, 100));
  final image = await recorder.endRecording().toImage(_width, _height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return bytes;
}

int _redPixels(ByteData bytes, int left, int right) {
  var count = 0;
  for (var x = left; x < right; x++) {
    for (var y = 0; y < _height; y++) {
      final index = (y * _width + x) * 4;
      if (bytes.getUint8(index) > 200 &&
          bytes.getUint8(index + 1) < 50 &&
          bytes.getUint8(index + 2) < 50) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = {
    '删除线': {
      'text-decoration': 'line-through',
      'text-decoration-color': '#ff0000',
    },
    '虚线下划线': {
      'text-decoration': 'underline',
      'text-decoration-style': 'dashed',
      'text-decoration-color': '#ff0000',
    },
    '背景': {'background-color': '#ff0000'},
    '边框': {'border': '2px solid #ff0000'},
  };
  for (final table in [false, true]) {
    for (final crossBox in [false, true]) {
      for (final entry in cases.entries) {
        // 表格保留引擎原生装饰线；本轮修复其普通 run 背景与边框。
        if (table && entry.value.containsKey('text-decoration')) continue;
        test(
          '${table ? '表格' : '正文'}${crossBox ? '跨盒' : '盒后'}run的${entry.key}跟随文字',
          () async {
            final plain = await _render(
              properties: entry.value,
              table: table,
              crossBox: crossBox,
              withBox: false,
            );
            final boxed = await _render(
              properties: entry.value,
              table: table,
              crossBox: crossBox,
              withBox: true,
            );
            expect(
              _redPixels(plain, 22, 38),
              greaterThan(0),
              reason: '无盒对照应可见',
            );
            expect(
              _redPixels(boxed, 82, 98),
              greaterThan(0),
              reason: 'B的装饰应右移60px',
            );
            expect(_redPixels(boxed, 30, 70), 0, reason: '文字装饰不应画到独立蓝色标签上');
            if (crossBox) {
              expect(
                _redPixels(boxed, 2, 18),
                greaterThan(0),
                reason: '盒前A的装饰仍保留',
              );
            }
          },
        );
      }
    }
  }
  for (final crossBox in [false, true]) {
    test('${crossBox ? '跨盒' : '盒后'}选区高亮覆盖原文而不覆盖独立标签', () async {
      final pixels = await _render(
        properties: {},
        table: false,
        crossBox: crossBox,
        withBox: true,
        selection: true,
      );
      expect(_redPixels(pixels, 82, 98), greaterThan(0));
      expect(_redPixels(pixels, 30, 70), 0);
      if (crossBox) expect(_redPixels(pixels, 2, 18), greaterThan(0));
    });
  }
}
