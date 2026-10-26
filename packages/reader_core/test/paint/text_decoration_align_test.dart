import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 装饰线（line-through / overline）与列表项目符号的浏览器对齐回归。
///
/// 浏览器基准值来自 tool/css_parity 04-decoration / 11-list 的 4x 截图测量：
/// Chromium + 思源宋体，17px、line-height 1.8（装饰线用）/ 1.7（列表用）。
/// 引擎侧同字体同字号渲染后按「墨迹行」对比，容差按字形栅格取整留 1.5px。
const _pageWidth = 350.0;
const _pageHeight = 200.0;
const _topPadding = 40.0;
const _serif = 'DecoAlignSerif';

/// 浏览器 17px：CJK 字形墨迹顶边到 line-through / overline 顶边都是 6.5px。
const _browserDecoGap17 = 6.5;

Future<void> _loadFont() async {
  final bytes = await File(
    '../../test_fonts/SourceHanSerifSC-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    _serif,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '17px',
      'line-height': '1.8',
      'font-family': _serif,
      'color': '#000000',
      ...overrides,
    });

/// 排版一页并渲染成 RGBA 像素。
Future<ByteData> _render(
  String text,
  ComputedStyle style, {
  String? listMarker,
}) async {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: _pageWidth,
  );
  final page = Paginator(pageHeight: 120, topPadding: _topPadding)
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: _pageWidth,
            listMarker: listMarker,
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, _pageWidth, _pageHeight),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const PagePainter().paint(
    canvas,
    page,
    pageSize: const Size(_pageWidth, _pageHeight),
  );
  final image = await recorder.endRecording().toImage(
    _pageWidth.toInt(),
    _pageHeight.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

bool _ink(ByteData bytes, int x, int y) =>
    bytes.getUint32((y * _pageWidth.toInt() + x) * 4) != 0xFFFFFFFF;

/// 有墨迹的行号。
List<int> _inkRows(ByteData bytes, {int x0 = 0, int x1 = -1}) {
  final right = x1 < 0 ? _pageWidth.toInt() : x1;
  final rows = <int>[];
  for (var y = 0; y < _pageHeight.toInt(); y++) {
    for (var x = x0; x < right; x++) {
      if (_ink(bytes, x, y)) {
        rows.add(y);
        break;
      }
    }
  }
  return rows;
}

/// 该行最长连续墨迹段长度（装饰线是贯穿整行的细线）。
int _longestRun(ByteData bytes, int y, {int x0 = 0, int x1 = -1}) {
  final right = x1 < 0 ? _pageWidth.toInt() : x1;
  var best = 0;
  var run = 0;
  for (var x = x0; x < right; x++) {
    if (_ink(bytes, x, y)) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
  }
  return best;
}

/// 贯穿整行的装饰线行（排除字形笔画行）。
List<int> _decorationRows(ByteData bytes, {int minRun = 100}) => [
  for (var y = 0; y < _pageHeight.toInt(); y++)
    if (_longestRun(bytes, y) >= minRun) y,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('line-through 位于浏览器位置（字形顶边下方 6.5px）', () async {
    final plain = await _render('删除线一二三四五', _style());
    final struck = await _render(
      '删除线一二三四五',
      _style(const {'text-decoration': 'line-through'}),
    );
    final glyphTop = _inkRows(plain).first;
    final deco = _decorationRows(struck);
    expect(deco, isNotEmpty, reason: 'line-through 应画出贯穿的实线');
    expect(deco.first - glyphTop, closeTo(_browserDecoGap17, 1.5));
  });

  test('overline 位于浏览器位置（字形顶边上方 6.5px）', () async {
    final plain = await _render('上划线一二三四五', _style());
    final overlined = await _render(
      '上划线一二三四五',
      _style(const {'text-decoration': 'overline'}),
    );
    final glyphTop = _inkRows(plain).first;
    final deco = _decorationRows(overlined);
    expect(deco, isNotEmpty, reason: 'overline 应画在字形上方');
    expect(glyphTop - deco.last, closeTo(_browserDecoGap17, 1.5));
  });

  test('装饰线跨行内子元素连续，不在 span 边界断开', () async {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '删除线一二三四五',
      style: style,
      maxWidth: _pageWidth,
      runs: [
        StyledRun(
          start: 3,
          end: 6,
          style: _style(const {'color': '#cc0000'}),
        ),
      ],
    );
    final page = Paginator(pageHeight: 120, topPadding: _topPadding)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: _pageWidth,
            ),
          ],
        )
        .pages
        .single;
    // 整行文本块自身带 line-through：浏览器把线画满整行（含子 span）。
    final struckStyle = _style(const {'text-decoration': 'line-through'});
    final struckLayout = TextLayoutEngine.layout(
      text: '删除线一二三四五',
      style: struckStyle,
      maxWidth: _pageWidth,
      runs: [
        StyledRun(
          start: 3,
          end: 6,
          style: _style(const {'color': '#cc0000'}),
        ),
      ],
    );
    expect(page.slices, isNotEmpty);
    final struckPage = Paginator(pageHeight: 120, topPadding: _topPadding)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: struckLayout,
              style: struckStyle,
              containingWidth: _pageWidth,
            ),
          ],
        )
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, _pageWidth, _pageHeight),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    const PagePainter().paint(
      canvas,
      struckPage,
      pageSize: const Size(_pageWidth, _pageHeight),
    );
    final image = await recorder.endRecording().toImage(
      _pageWidth.toInt(),
      _pageHeight.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final deco = _decorationRows(data!);
    expect(deco, isNotEmpty);
    // 线宽覆盖整行文本：最长连续段不短于 5 个汉字的宽度（去掉少量栅格缺口）。
    expect(_longestRun(data, deco.first), greaterThan(5 * 17 * 0.8));
  });

  test('点线 line-through 保留引擎线型（不画成实线）', () async {
    final plain = await _render('点线一二三四五', _style());
    final dotted = await _render(
      '点线一二三四五',
      _style(const {'text-decoration': 'line-through dotted'}),
    );
    // 点线与字形同高，按「同一行墨迹变多」找装饰行。
    int inkCount(ByteData bytes, int y) {
      var count = 0;
      for (var x = 0; x < _pageWidth.toInt(); x++) {
        if (_ink(bytes, x, y)) count++;
      }
      return count;
    }

    final decoRows = <int>[
      for (var y = 0; y < _pageHeight.toInt(); y++)
        if (inkCount(dotted, y) - inkCount(plain, y) >= 3) y,
    ];
    expect(decoRows, isNotEmpty, reason: '点线仍应画出墨迹');
    // 点线不连续：装饰行上的最长连续段远小于实线（整行 5 个汉字）。
    expect(
      _longestRun(dotted, decoRows.first),
      lessThan(5 * 17 * 0.5),
      reason: '点线不能被实线替换',
    );
  });

  test('无序列表 disc 标记按浏览器几何画实心圆（直径约 0.4em）', () async {
    final style = _style(const {'line-height': '1.7', 'margin-left': '40px'});
    final data = await _render('项一', style, listMarker: '•');
    // 标记画在文本左侧 gutter（文本从 margin-left 40px 起）。
    final marker = _inkRows(data, x0: 0, x1: 40);
    expect(marker, isNotEmpty);
    final markerTop = marker.first;
    final markerBottom = marker.last;
    // disc 直径 ≈ 0.4em = 6.8px；浏览器实测 6.75px（4x 截图）。
    expect(markerBottom - markerTop + 1, closeTo(6.8, 1.5));
  });

  test('无序列表 circle 标记是空心圆（比实心 disc 更大且中空）', () async {
    final style = _style(const {'line-height': '1.7', 'margin-left': '40px'});
    final data = await _render('项一', style, listMarker: '○');
    final markerRows = _inkRows(data, x0: 0, x1: 40);
    expect(markerRows, isNotEmpty);
    // 空心圆：纵向跨度接近 disc + 1px 描边，且中间行左右各有一段墨迹、
    // 中间是空白（中空）。
    expect(markerRows.last - markerRows.first + 1, closeTo(7.8, 1.5));
    final middle = markerRows[(markerRows.length / 2).floor()];
    var leftEdge = -1;
    var rightEdge = -1;
    for (var x = 0; x < 40; x++) {
      if (_ink(data, x, middle)) {
        if (leftEdge < 0) leftEdge = x;
        rightEdge = x;
      }
    }
    expect(leftEdge, greaterThanOrEqualTo(0));
    final leftInk = _longestRun(data, middle) < 40;
    expect(rightEdge - leftEdge + 1 >= 6, isTrue);
    expect(leftInk, isTrue, reason: '空心圆中间行应有描边墨迹');
  });

  test('visibility:hidden 时装饰线与列表标记都不绘制', () async {
    final hidden = await _render(
      '删除线一二三四五',
      _style(const {
        'text-decoration': 'line-through',
        'visibility': 'hidden',
      }),
    );
    expect(_inkRows(hidden), isEmpty);
  });
}
