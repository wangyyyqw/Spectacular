import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// W13：`transform` 合成（translate/scale/rotate/页外裁剪）与 `overflow`
/// 的 ink 裁剪。字体用 Ahem，字宽可精确累加。
const _width = 240;
const _height = 160;

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': '#000000',
      ...overrides,
    });

Future<ByteData> _render(
  ComputedStyle style,
  String text, {
  double layoutMaxWidth = 200,
}) async {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: layoutMaxWidth,
  );
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
  PagePainter(background: const Color(0xFFFFFFFF)).paint(
    canvas,
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 1);
int _b(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 2);

bool _isRed(ByteData b, int x, int y) =>
    _r(b, x, y) > 200 && _g(b, x, y) < 60 && _b(b, x, y) < 60;

bool _isBlank(ByteData b, int x, int y) =>
    _r(b, x, y) > 245 && _g(b, x, y) > 245 && _b(b, x, y) > 245;

bool _hasInk(ByteData b) {
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (!_isBlank(b, x, y)) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('translate(20px, 10px)：整个块（背景）右下移 20/10', () async {
    final data = await _render(
      _style(const {
        'background-color': '#ff0000',
        'color': '#ff0000',
        'transform': 'translate(20px, 10px)',
      }),
      'aa',
    );
    expect(_isBlank(data, 5, 5), isTrue, reason: '位移后左上空出');
    expect(_isRed(data, 25, 15), isTrue, reason: '块移到 (20,10) 起');
    expect(_isRed(data, 235, 20), isTrue, reason: '块右半仍在页内');
    expect(_isBlank(data, 235, 5), isTrue, reason: '位移后顶部留白');
  });

  test('translate(50%, 0)：百分比以边框盒宽为基准（半页）', () async {
    final data = await _render(
      _style(const {
        'background-color': '#ff0000',
        'color': '#ff0000',
        'transform': 'translate(50%, 0)',
      }),
      'aa',
    );
    // 盒宽 240 → 位移 120。
    expect(_isBlank(data, 100, 6), isTrue, reason: '左半空出');
    expect(_isRed(data, 130, 6), isTrue, reason: '右半有块');
  });

  test('scale(0.5) + transform-origin: left top：左上角不动、整体缩小', () async {
    final data = await _render(
      _style(const {
        'background-color': '#ff0000',
        'color': '#ff0000',
        'transform': 'scale(0.5)',
        'transform-origin': 'left top',
      }),
      'aa',
    );
    // 240×24 → 120×12，左上角 (0,0) 固定。
    expect(_isRed(data, 2, 2), isTrue, reason: '原点处仍着色');
    expect(_isRed(data, 110, 8), isTrue, reason: '缩放后仍在盒内');
    expect(_isBlank(data, 150, 8), isTrue, reason: '右半被缩掉');
    expect(_isBlank(data, 60, 30), isTrue, reason: '高度缩到 12，下方留白');
  });

  test('rotate(90deg)：绕盒中心旋转，块变成竖直条带', () async {
    final data = await _render(
      _style(const {
        'background-color': '#ff0000',
        'color': '#ff0000',
        'transform': 'rotate(90deg)',
      }),
      'aa',
    );
    // 240×24 绕中心 (120,12) 转 90° → x 108..132、y -108..132。
    expect(_isRed(data, 120, 60), isTrue, reason: '竖直条带内有块');
    expect(_isBlank(data, 20, 12), isTrue, reason: '原左侧转出去后留白');
    expect(_isRed(data, 118, 130), isTrue, reason: '旋转后可延伸到页底附近');
  });

  test('页外裁剪：translate 500px 后页内无任何墨迹', () async {
    final data = await _render(
      _style(const {
        'background-color': '#ff0000',
        'color': '#ff0000',
        'transform': 'translate(500px, 0)',
      }),
      'aa',
    );
    expect(_hasInk(data), isFalse, reason: '整块移出页面应被裁掉');
  });

  test('overflow: hidden：文字 ink 不画到 padding-box 外', () async {
    // 行按 240 宽排版（无省略号），块宽 100 + overflow hidden ⇒ 右侧被裁。
    final data = await _render(
      _style(const {
        'width': '100px',
        'overflow': 'hidden',
        'white-space': 'nowrap',
        'text-overflow': 'clip',
      }),
      'abcdefghijklmnopqrstuvwx',
      layoutMaxWidth: 320,
    );
    for (var y = 0; y < 30; y++) {
      for (var x = 103; x < _width; x++) {
        expect(
          _isBlank(data, x, y),
          isTrue,
          reason: '($x,$y) 在 padding-box 外，不应有 ink',
        );
      }
    }
    // 盒内仍有文字。
    var ink = 0;
    for (var y = 0; y < 30; y++) {
      for (var x = 0; x < 100; x++) {
        if (!_isBlank(data, x, y)) ink++;
      }
    }
    expect(ink, greaterThan(0), reason: '盒内应保留文字');
  });

  test('overflow: visible：文字照常外溢（不裁剪）', () async {
    final data = await _render(
      _style(const {
        'width': '100px',
        'white-space': 'nowrap',
      }),
      'abcdefghijklmnopqrstuvwx',
      layoutMaxWidth: 320,
    );
    var inkOutside = 0;
    for (var y = 0; y < 30; y++) {
      for (var x = 103; x < 200; x++) {
        if (!_isBlank(data, x, y)) inkOutside++;
      }
    }
    expect(inkOutside, greaterThan(0), reason: 'visible 时 ink 应外溢');
  });

  test('text-overflow: ellipsis：布局截断后绘制层补画省略号', () async {
    final style = _style(const {
      'width': '100px',
      'overflow': 'hidden',
      'white-space': 'nowrap',
      'text-overflow': 'ellipsis',
    });
    // 布局按内容宽 100 测量：行宽含省略号 advance。
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmnopqrstuvwx',
      style: style,
      maxWidth: 100,
    );
    expect(layout.lines.first.ellipsized, isTrue, reason: '布局应标记截断');
    final data = await _render(style, 'abcdefghijklmnopqrstuvwx',
        layoutMaxWidth: 100);
    // 省略号在行尾（行宽 96 = 5×16 + 16）。
    var inkNearEnd = 0;
    for (var y = 0; y < 30; y++) {
      for (var x = 80; x < 100; x++) {
        if (!_isBlank(data, x, y)) inkNearEnd++;
      }
    }
    expect(inkNearEnd, greaterThan(0), reason: '行尾应有省略号墨迹');
  });
}
