import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// P2-37 关键 P1 属性抽样：opacity / text-overflow / box-shadow /
/// border-double（已绘但无测试）。像素级断言复用 box_decoration 口径
///（RGBA 原始通道值比较，不用废弃的 Color 访问器）。
const _width = 240;
const _height = 120;

int _r(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 1);
int _bl(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 2);
int _a(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 3);

bool _isInk(ByteData b, int x, int y) =>
    _a(b, x, y) == 255 && (_r(b, x, y) < 250 || _g(b, x, y) < 250);

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': '#000000',
      ...overrides,
    });

TextLayoutResult _layout(String text, ComputedStyle style, double maxWidth) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: maxWidth);

Future<ByteData> _renderBlock(ComputedStyle style, String text) async {
  final layout = _layout(text, style, 200);
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: _width.toDouble(),
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(
    canvas,
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

void main() {
  testWidgets('opacity: 0.5 的黑字在白底渲染为中灰', (tester) async {
    await tester.runAsync(() async {
      final plain = await _renderBlock(_style(const {}), 'abc');
      final faded = await _renderBlock(
        _style(const {'opacity': '0.5'}),
        'abc',
      );
      // Ahem：字块从 (0,0) 起，取首个墨迹像素对比灰度。
      (int, int) firstInk(ByteData bytes) {
        for (var y = 0; y < _height; y++) {
          for (var x = 0; x < _width; x++) {
            if (_isInk(bytes, x, y)) return (x, y);
          }
        }
        return (-1, -1);
      }

      final solidAt = firstInk(plain);
      final halfAt = firstInk(faded);
      expect(solidAt, isNot((-1, -1)), reason: '不透明样本应有墨迹');
      expect(halfAt, isNot((-1, -1)), reason: '半透明样本应有墨迹');
      expect(_r(plain, solidAt.$1, solidAt.$2), lessThan(30),
          reason: '不透明字为黑');
      // 0.5 透明混合白底：黑 → 128 左右灰。
      final gray = _r(faded, halfAt.$1, halfAt.$2);
      expect(gray, greaterThan(100));
      expect(gray, lessThan(170));
      expect(_g(faded, halfAt.$1, halfAt.$2), closeTo(gray, 2),
          reason: '灰度无色偏');
      // 解析：越界钳制、缺省为 1。
      expect(_style(const {'opacity': '2'}).opacity, 1.0);
      expect(_style(const {'opacity': '-1'}).opacity, 0.0);
      expect(_style(const {}).opacity, 1.0);
    });
  });

  testWidgets('text-overflow: ellipsis 截断 nowrap 行并在右缘补省略号', (tester) async {
    await tester.runAsync(() async {
      final style = _style(const {
        'white-space': 'nowrap',
        'text-overflow': 'ellipsis',
        'background-color': '#FFFFFF',
      });
      // 26 字 × 16px = 416px > 240 画布 → 必截断。
      final bytes = await _renderBlock(style, 'abcdefghijklmnopqrstuvwxyz');
      var inkRight = -1;
      outer:
      for (var y = 0; y < _height; y++) {
        for (var x = _width - 1; x >= _width - 60; x--) {
          if (_isInk(bytes, x, y)) {
            inkRight = x;
            break outer;
          }
        }
      }
      expect(inkRight, greaterThan(_width - 60), reason: '右缘应有省略号墨迹');
      // W13 契约：布局层负责截断（行宽含省略号 advance、不超内容宽），
      // 原文不改写、start/end 仍是前缀坐标（CFI/分页按全文）。
      final layout = _layout('abcdefghijklmnopqrstuvwxyz', style, 200);
      expect(layout.lineCount, 1);
      expect(layout.lines.first.ellipsized, isTrue, reason: 'ellipsis 行应被标记');
      expect(
        layout.lines.first.width,
        lessThanOrEqualTo(200.5),
        reason: '行宽含省略号 advance，不超过内容宽',
      );
      expect(layout.lines.first.ellipsisWidth, greaterThan(0));
      expect(
        layout.text,
        'abcdefghijklmnopqrstuvwxyz',
        reason: '原文不改写，只截取前缀区间',
      );
      // 解析：未知值回退 clip。
      expect(
        _style(const {'text-overflow': 'ellipsis'}).textOverflow.name,
        'ellipsis',
      );
      expect(_style(const {'text-overflow': 'foo'}).textOverflow.name, 'clip');
      expect(_style(const {}).textOverflow.name, 'clip');
    });
  });

  testWidgets('box-shadow：偏移投影出现在块下方、背景覆盖重叠区', (tester) async {
    await tester.runAsync(() async {
      final withShadow = _style(const {
        'background-color': '#FFFFFF',
        'box-shadow': '8px 8px #FF0000',
      });
      final bytes = await _renderBlock(withShadow, 'a');
      // 块（背景铺内容区）底边在行高 24 处，其下 8px 内应有红色投影带；
      // 重叠区被白色背景覆盖（x 任意，y=28 在投影带内）。
      var shadowPixel = false;
      for (var x = 0; x < _width; x++) {
        if (_r(bytes, x, 28) > 200 &&
            _g(bytes, x, 28) < 80 &&
            _bl(bytes, x, 28) < 80) {
          shadowPixel = true;
          break;
        }
      }
      expect(shadowPixel, isTrue, reason: '块底下方应有红色阴影带');
      // 解析：none/缺省为 null；多阴影取首个；inset 忽略仍投影。
      expect(_style(const {'box-shadow': 'none'}).boxShadow, isNull);
      expect(_style(const {}).boxShadow, isNull);
      final multi = _style(const {
        'box-shadow': '2px 3px #00FF00, 10px 10px #FF0000',
      }).boxShadow;
      expect(multi!.offsetX, 2, reason: '只取首个阴影');
      expect(multi.color, const Color(0xFF00FF00));
      expect(
        _style(const {'box-shadow': 'inset 4px 4px #0000FF'}).boxShadow!
            .offsetX,
        4,
        reason: 'inset 标记忽略',
      );
    });
  });

  testWidgets('border-style: double 三线模式有墨迹', (tester) async {
    await tester.runAsync(() async {
      final style = _style(const {
        'border-width': '6px',
        'border-style': 'double',
        'border-color': '#000000',
      });
      final bytes = await _renderBlock(style, 'a');
      // double = 三分线宽两条（各 2px）+ 中缝 2px：扫描 x=120 列前 8 行。
      final rows = <int>[
        for (var y = 0; y < 8; y++)
          if (_isInk(bytes, 120, y)) y,
      ];
      expect(rows.length, greaterThanOrEqualTo(3), reason: '双线至少 3 行墨');
      expect(
        _style(const {'border-style': 'double'}).borders.top.style.name,
        'double',
      );
    });
  });
}
