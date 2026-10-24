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

const _pageSize = Size(240, 240);
const _serif = 'DecoSerif';

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _serif,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '20px',
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
  final page = Paginator(pageHeight: 240)
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
      const Rect.fromLTWH(0, 0, 240, 240),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const PagePainter().paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(240, 240);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

bool _isInk(ByteData bytes, int x, int y) =>
    bytes.getUint32((y * 240 + x) * 4) != 0xFFFFFFFF;

List<int> _inkRows(ByteData bytes) => [
  for (var y = 0; y < 240; y++)
    if ([for (var x = 0; x < 240; x++) _isInk(bytes, x, y)].any((v) => v)) y,
];

/// 含足够长的水平连续墨迹段的行（下划线是整行贯穿的细线）。
List<int> _lineRows(ByteData bytes, {int minRun = 12}) {
  final rows = <int>[];
  for (var y = 0; y < 240; y++) {
    var run = 0;
    for (var x = 0; x < 240; x++) {
      if (_isInk(bytes, x, y)) {
        run += 1;
        if (run >= minRun) {
          rows.add(y);
          break;
        }
      } else {
        run = 0;
      }
    }
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('text-decoration: underline 画在字形下方且不覆盖字形', () async {
    final plain = await _render('一二三', _style());
    final underlined = await _render(
      '一二三',
      _style(const {'text-decoration': 'underline'}),
    );
    final glyphRows = _inkRows(plain);
    final allRows = _inkRows(underlined);
    final extra = allRows.where((row) => !glyphRows.contains(row)).toList();

    expect(glyphRows, isNotEmpty);
    expect(extra, isNotEmpty, reason: '下划线应产生新的墨迹行');
    expect(
      extra.first,
      greaterThan(glyphRows.last),
      reason: '下划线整行都在字形最低墨迹之下（不压字）',
    );
    expect(glyphRows.every(allRows.contains), isTrue, reason: '下划线不影响原有字形墨迹');
  });

  test('text-decoration: overline 画在字形上方', () async {
    final plain = await _render('一二三', _style());
    final overlined = await _render(
      '一二三',
      _style(const {'text-decoration': 'overline'}),
    );
    final glyphRows = _inkRows(plain);
    final extra = _inkRows(overlined)
        .where((row) => !glyphRows.contains(row))
        .toList();
    expect(extra, isNotEmpty);
    expect(extra.last, lessThan(glyphRows.first));
  });

  test('跨页装饰不重复：每页只画本页行的下划线', () async {
    final style = _style(const {
      'text-decoration': 'underline',
      'font-size': '16px',
      'line-height': '1.5',
      'max-width': '20px',
    });
    // 4 行文本，硬换行保证每行一行。
    final layout = TextLayoutEngine.layout(
      text: 'ab\ncd\nef\ngh',
      style: style,
      maxWidth: 200,
    );
    // 每行 24px，一页 48px → 2 页。
    final pagination = Paginator(pageHeight: 48).measureChapter(
      blocks: [
        PageBlock.styled(layout: layout, style: style, containingWidth: 200),
      ],
    );
    expect(pagination.pages, hasLength(2));

    Future<ByteData> renderPage(PageContent page) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 240, 240),
          Paint()..color = const Color(0xFFFFFFFF),
        );
      const PagePainter().paint(canvas, page, pageSize: _pageSize);
      final image = await recorder.endRecording().toImage(240, 240);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }

    final page1 = await renderPage(pagination.pages[0]);
    final page2 = await renderPage(pagination.pages[1]);
    final lines1 = _lineRows(page1);
    final lines2 = _lineRows(page2);
    // 每行一条下划线；两页各 2 行，合计 4 条，不重复绘制。
    // 每页 2 行 → 2 条下划线（按连续行聚成簇计数，避开线宽 1~2 行）。
    List<List<int>> clusters(List<int> rows) {
      final result = <List<int>>[];
      for (final row in rows) {
        if (result.isNotEmpty && row - result.last.last <= 2) {
          result.last.add(row);
        } else {
          result.add([row]);
        }
      }
      return result;
    }

    expect(clusters(lines1), hasLength(2), reason: '第 1 页 2 条线');
    expect(clusters(lines2), hasLength(2), reason: '第 2 页 2 条线');
  });
}
