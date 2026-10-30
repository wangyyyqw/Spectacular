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
  // 测试子集字体缺少部分着重号，加载与宿主一致的内置回退字体。
  final fallback = await File(
    '../../apps/reader_mobile/assets/fonts/SourceHanSerifCN-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    'builtin_song',
  )..addFont(Future.value(ByteData.sublistView(fallback)))).load();
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
  // 留出上侧注音区，避免页边裁剪干扰字形轮廓断言。
  final page = Paginator(pageHeight: 160, topPadding: 32)
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

  test('横排 under 着重号按 Chromium 口径增加块底部空间', () {
    final plain = TextLayoutEngine.layout(
      text: '中文',
      style: _style(),
      maxWidth: 200,
    );
    final under = TextLayoutEngine.layout(
      text: '中文',
      style: _style(const {
        'text-emphasis': 'dot',
        'text-emphasis-position': 'under',
      }),
      maxWidth: 200,
    );
    expect(under.height - plain.height, moreOrLessEquals(24 * 0.12));
  });

  test('text-emphasis: none 不画着重号', () async {
    final plain = await _render('中文', _style());
    final none = await _render('中文', _style(const {'text-emphasis': 'none'}));
    expect(_inkRows(none), _inkRows(plain));
  });

  test('text-emphasis: 实心点与空心点各自出墨且形态不同', () async {
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

  test('text-emphasis: circle 与 sesame 使用各自字形', () async {
    final circle = await _render(
      '中文',
      _style(const {'text-emphasis': 'filled circle'}),
    );
    final sesame = await _render(
      '中文',
      _style(const {'text-emphasis': 'filled sesame'}),
    );
    expect(circle, isNot(equals(sesame)), reason: '圆点和芝麻点形态应不同');
  });

  test('着重号跳过标点、分隔符和控制字符', () async {
    const text = '，。：；！？「」（）-\u00a0\u200b';
    final plain = await _render(text, _style());
    final marked = await _render(text, _style(const {'text-emphasis': 'dot'}));
    expect(marked.buffer.asUint8List(), plain.buffer.asUint8List());
  });

  test('着重号保留百分号、井号和与号等规范例外', () async {
    const text = '#%&@§¶';
    final plain = await _render(text, _style());
    final marked = await _render(text, _style(const {'text-emphasis': 'dot'}));
    final glyphRows = _inkRows(plain);
    final extra = _inkRows(marked)
        .where((row) => !glyphRows.contains(row))
        .toList();
    expect(_clusters(extra, marked), text.length);
  });

  test('实心和空心芝麻点保留字体中的不同轮廓', () async {
    final filled = await _render(
      '中文',
      _style(const {'text-emphasis': 'filled sesame'}),
    );
    final open = await _render(
      '中文',
      _style(const {'text-emphasis': 'open sesame'}),
    );
    expect(filled.buffer.asUint8List(), isNot(open.buffer.asUint8List()));
  });

  test('组合字符和补充平面汉字按字素簇各画一个着重号', () async {
    const text = '中e\u0301𠀀';
    final plain = await _render(text, _style());
    final marked = await _render(text, _style(const {'text-emphasis': 'dot'}));
    final glyphRows = _inkRows(plain);
    final extra = _inkRows(marked)
        .where((row) => !glyphRows.contains(row))
        .toList();
    expect(_clusters(extra, marked), 3);
  });
}
