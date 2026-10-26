import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(200, 120);

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

TextLayoutResult _layout(
  String text,
  ComputedStyle style, {
  List<StyledRun> runs = const [],
}) => TextLayoutEngine.layout(
  text: text,
  style: style,
  maxWidth: 180,
  runs: runs,
);

Future<ByteData> _render(
  String text,
  ComputedStyle style, {
  StyledRun? run,
}) async {
  final layout = _layout(text, style, runs: run == null ? const [] : [run]);
  final page = Paginator(pageHeight: 120, topPadding: 20)
      .measureChapter(
        blocks: [
          PageBlock.styled(layout: layout, style: style, containingWidth: 180),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.round(),
    _pageSize.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

({int top, int bottom}) _inkRows(ByteData bytes) {
  final width = _pageSize.width.round();
  var top = -1;
  var bottom = -1;
  for (var y = 0; y < _pageSize.height.round(); y++) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint32((y * width + x) * 4) != 0xFFFFFFFF) {
        top = top == -1 ? y : top;
        bottom = y;
        break;
      }
    }
  }
  return (top: top, bottom: bottom);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vertical-align: super 段整体上移 0.4em', () async {
    final base = _style();
    final sup = _style(const {'vertical-align': 'super'});
    final plain = await _render('2', base);
    final shifted = await _render(
      '2',
      base,
      run: StyledRun(
        start: 0,
        end: 1,
        style: sup,
        baselineShift: sup.verticalAlignShift,
      ),
    );
    final plainRows = _inkRows(plain);
    final shiftedRows = _inkRows(shifted);
    expect(plainRows.top, greaterThan(0));
    expect(
      shiftedRows.top - plainRows.top,
      closeTo(-6.4, 1.0),
      reason: '上标墨迹整体上移',
    );
    expect(shiftedRows.bottom - plainRows.bottom, closeTo(-6.4, 1.0));
  });

  test('vertical-align: sub 段按父级字号 1/5+1 下移', () async {
    final base = _style();
    final sub = _style(const {'vertical-align': 'sub'});
    final plain = await _render('2', base);
    final shifted = await _render(
      '2',
      base,
      run: StyledRun(
        start: 0,
        end: 1,
        style: sub,
        baselineShift: sub.verticalAlignShift,
      ),
    );
    final plainRows = _inkRows(plain);
    final shiftedRows = _inkRows(shifted);
    expect(
      shiftedRows.top - plainRows.top,
      closeTo(4.2, 1.0),
      reason: '下标墨迹整体下移（父级字号 16/5+1）',
    );
  });

  test('无基线偏移时整行绘制路径不变', () async {
    final base = _style();
    final plain = await _render('ab', base);
    final withRun = await _render(
      'ab',
      base,
      run: StyledRun(start: 0, end: 1, style: base),
    );
    expect(_inkRows(withRun), _inkRows(plain));
  });
}
