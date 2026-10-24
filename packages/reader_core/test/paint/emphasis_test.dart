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

const _pageSize = Size(240, 160);
const _serif = 'EmphSerif';

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _serif,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '24px',
      'line-height': '1.6',
      'font-family': _serif,
      'color': '#000000',
      ...overrides,
    });

Future<ByteData> _render(String text, ComputedStyle style) async {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: 200,
  );
  final page = Paginator(pageHeight: 160)
      .measureChapter(
        blocks: [
          PageBlock.styled(layout: layout, style: style, containingWidth: 200),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 240, 160),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const PagePainter().paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(240, 160);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

bool _isInk(ByteData bytes, int x, int y) =>
    bytes.getUint32((y * 240 + x) * 4) != 0xFFFFFFFF;

List<int> _inkRows(ByteData bytes) => [
  for (var y = 0; y < 160; y++)
    if ([for (var x = 0; x < 240; x++) _isInk(bytes, x, y)].any((v) => v)) y,
];

/// 额外墨迹行的水平簇数量（每个着重号是一个独立小圆点）。
int _clusters(List<int> extraRows, ByteData bytes) {
  if (extraRows.isEmpty) {
    return 0;
  }
  final first = extraRows.first;
  final columns = <int>[
    for (var x = 0; x < 240; x++)
      if (_isInk(bytes, x, first)) x,
  ];
  var clusters = 0;
  var previous = -10;
  for (final x in columns) {
    if (x - previous > 3) {
      clusters += 1;
    }
    previous = x;
  }
  return clusters;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('text-emphasis: dot over 画在字形上方，每字一个点', () async {
    final plain = await _render('中文', _style());
    final emphasized = await _render(
      '中文',
      _style(const {'text-emphasis': 'dot'}),
    );
    final glyphRows = _inkRows(plain);
    final extra = _inkRows(emphasized)
        .where((row) => !glyphRows.contains(row))
        .toList();
    expect(extra, isNotEmpty, reason: '着重号应产生新的墨迹行');
    expect(extra.last, lessThan(glyphRows.first), reason: '着重号在字形上方');
    expect(_clusters(extra, emphasized), 2, reason: '两个字两个点');
  });

  test('text-emphasis-position: under 画在字形下方', () async {
    final plain = await _render('中文', _style());
    final emphasized = await _render(
      '中文',
      _style(const {'text-emphasis': 'dot', 'text-emphasis-position': 'under'}),
    );
    final glyphRows = _inkRows(plain);
    final extra = _inkRows(emphasized)
        .where((row) => !glyphRows.contains(row))
        .toList();
    expect(extra, isNotEmpty);
    expect(extra.first, greaterThan(glyphRows.last), reason: '着重号在字形下方');
  });

  test('text-emphasis: none 不画着重号', () async {
    final plain = await _render('中文', _style());
    final none = await _render('中文', _style(const {'text-emphasis': 'none'}));
    expect(_inkRows(none), _inkRows(plain));
  });

  test('text-emphasis: filled 与 open 各自出墨且形态不同', () async {
    final filled = await _render(
      '中文',
      _style(const {'text-emphasis': 'filled'}),
    );
    final open = await _render('中文', _style(const {'text-emphasis': 'open'}));
    int inkCount(ByteData bytes) => [
      for (var y = 0; y < 160; y++)
        for (var x = 0; x < 240; x++)
          if (_isInk(bytes, x, y)) 1,
    ].length;
    final none = await _render('中文', _style(const {'text-emphasis': 'none'}));
    expect(inkCount(filled), greaterThan(inkCount(none)));
    expect(inkCount(open), greaterThan(inkCount(none)));
    expect(inkCount(filled), isNot(equals(inkCount(open))));
  });
}
