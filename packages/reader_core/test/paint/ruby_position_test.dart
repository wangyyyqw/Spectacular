import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// `ruby-position` / `ruby-align`（CSS Ruby 1 §5）：注音默认画在基字上方
/// （横排 over），`under` 画在下方；`ruby-align` 控制注音在基字区间内的对齐。
const _w = 240;
const _h = 240;

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '32px',
      'line-height': '1.6',
      'font-family': 'Ahem',
      ...overrides,
    });

Future<ByteData> _render({required Map<String, String> overrides}) async {
  final style = _style(overrides);
  final layout = TextLayoutEngine.layout(
    text: '汉字',
    style: style,
    maxWidth: _w.toDouble(),
  );
  final block = PageBlock.styled(
    layout: layout,
    style: style,
    containingWidth: _w.toDouble(),
    rubies: const [RubyAnnotation(start: 0, end: 1, text: '注音')],
  );
  // 顶部留 40px：注音画在行顶上方，贴页顶会被裁掉。
  final page = Paginator(pageHeight: _h.toDouble(), topPadding: 40)
      .measureChapter(blocks: [block])
      .pages
      .first;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(background: const Color(0xFFFFFFFF)).paint(
    canvas,
    page,
    pageSize: Size(_w.toDouble(), _h.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_w, _h);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * _w + x) * 4);
bool _ink(ByteData b, int x, int y) => _r(b, x, y) < 220;

/// 首个有墨迹的 y（用于判断注音在基字上方还是下方）。
int _firstInkRow(ByteData b) {
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      if (_ink(b, x, y)) {
        return y;
      }
    }
  }
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认 over：注音画在基字上方（墨迹从更小的 y 开始）', () async {
    final over = await _render(overrides: const {});
    final under = await _render(overrides: const {'ruby-position': 'under'});
    expect(_firstInkRow(over), lessThan(_firstInkRow(under)));
  });

  test('ruby-align: start 时注音靠基字区间左侧', () async {
    // 基字是 2 个 32px 字，注音「注音」也是 2 个 16px 字 → 有空隙可对齐。
    final center = await _render(overrides: const {'font-size': '32px'});
    final start = await _render(
      overrides: const {'font-size': '32px', 'ruby-align': 'start'},
    );
    int firstInkCol(ByteData b) {
      for (var x = 0; x < _w; x++) {
        for (var y = 0; y < _h; y++) {
          if (_ink(b, x, y)) return x;
        }
      }
      return -1;
    }

    expect(firstInkCol(start), lessThanOrEqualTo(firstInkCol(center)));
  });
}
