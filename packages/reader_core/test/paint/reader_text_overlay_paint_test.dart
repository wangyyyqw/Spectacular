import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show ReaderTextOverlay;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/position/cfi.dart';

const _blockCfi = 'epubcfi(/6/2!/4/2/1)';
const _size = Size(160, 160);

ReaderTextOverlay _color(int start, int end, int color) => ReaderTextOverlay(
  startCfi: cfiWithCharOffset(_blockCfi, start),
  endCfi: cfiWithCharOffset(_blockCfi, end),
  color: color,
);

PageContent _page({
  bool justify = false,
  bool vertical = false,
  bool authorBox = false,
}) {
  final base = ComputedStyle({
    'font-size': '24px',
    'line-height': '1.5',
    'font-family': 'Ahem',
    if (vertical) 'writing-mode': 'vertical-rl',
    if (vertical) 'text-orientation': 'upright',
  });
  final author = ComputedStyle(
    {
      'color': '#008000',
      if (authorBox) 'background-color': '#dddddd',
      if (authorBox) 'border-bottom': '1px solid #888888',
    },
    parent: base,
    hasExplicitTextColor: true,
  );
  final measured = TextLayoutEngine.layout(
    text: 'ABCDE',
    style: base,
    maxWidth: 140,
    runs: [StyledRun(start: 1, end: 4, style: author)],
  );
  final layout = justify
      ? TextLayoutResult(
          text: measured.text,
          lines: [
            for (final line in measured.lines) line.copyWith(justifyExtra: 12),
          ],
          width: measured.width,
          height: measured.height,
          maxWidth: measured.maxWidth,
          runs: measured.runs,
          plainTextLayout: measured.plainTextLayout,
        )
      : measured;
  return Paginator(pageHeight: _size.height)
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: base,
            startCfi: _blockCfi,
            containingWidth: _size.width,
          ),
        ],
      )
      .pages
      .single;
}

Future<ByteData> _render(PageContent page, PagePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), page, pageSize: _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.round(),
    _size.height.round(),
  );
  picture.dispose();
  final result = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return result!;
}

int _pixels(ByteData bytes, Color color) {
  final argb = color.toARGB32();
  final rgba = ((argb & 0xffffff) << 8) | (argb >> 24);
  var count = 0;
  for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
    if (bytes.getUint32(offset) == rgba) count += 1;
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (label, justify, vertical) in [
    ('普通', false, false),
    ('两端对齐', true, false),
    ('竖排', false, true),
  ]) {
    test('$label文字色覆盖原文区间并保留区间外作者文字色', () async {
      final page = _page(justify: justify, vertical: vertical);
      final layout = page.slices.single.block.layout;
      final pixels = await _render(
        page,
        PagePainter(
          textColor: const Color(0xff333333),
          textOverlays: [_color(2, 4, 0xffff0000)],
        ),
      );
      expect(_pixels(pixels, const Color(0xffff0000)), greaterThan(0));
      expect(_pixels(pixels, const Color(0xff008000)), greaterThan(0));
      expect(page.slices.single.block.layout, same(layout));
      expect(layout.runs.first.style.color, const Color(0xff008000));
    });
  }

  test('同页换色失效文字 painter，重复绘制命中缓存', () async {
    final page = _page();
    final cache = ParagraphCache();
    addTearDown(cache.dispose);
    final redPainter = PagePainter(
      paragraphCache: cache,
      textOverlays: [_color(1, 4, 0xffff0000)],
    );
    final red = await _render(page, redPainter);
    final repeated = await _render(page, redPainter);
    expect(
      repeated.buffer.asUint8List(),
      orderedEquals(red.buffer.asUint8List()),
    );
    expect(cache.hits, greaterThan(0));
    final blue = await _render(
      page,
      PagePainter(
        paragraphCache: cache,
        textOverlays: [_color(1, 4, 0xff0000ff)],
      ),
    );
    expect(_pixels(blue, const Color(0xffff0000)), 0);
    expect(_pixels(blue, const Color(0xff0000ff)), greaterThan(0));
  });

  test('后应用文字色覆盖前者，墨水屏保持黑白', () async {
    final page = _page();
    final overlays = [_color(1, 4, 0xffff0000), _color(1, 4, 0xff0000ff)];
    final blue = await _render(page, PagePainter(textOverlays: overlays));
    expect(_pixels(blue, const Color(0xffff0000)), 0);
    expect(_pixels(blue, const Color(0xff0000ff)), greaterThan(0));
    final monochrome = await _render(
      page,
      PagePainter(textOverlays: overlays, inkMode: true),
    );
    expect(_pixels(monochrome, const Color(0xff0000ff)), 0);
    expect(_pixels(monochrome, const Color(0xff000000)), greaterThan(0));
  });

  test('仅换色不拆分重画作者背景边框', () async {
    final page = _page(authorBox: true);
    final original = await _render(page, const PagePainter());
    final colored = await _render(
      page,
      PagePainter(textOverlays: [_color(2, 3, 0xffff0000)]),
    );
    expect(
      _pixels(colored, const Color(0xffdddddd)),
      _pixels(original, const Color(0xffdddddd)),
    );
    expect(
      _pixels(colored, const Color(0xff888888)),
      _pixels(original, const Color(0xff888888)),
    );
  });

  test('装饰底层钩子位于作者边框后文字前并隔离画布状态', () async {
    final page = _page();
    final phases = <String>[];
    final result = await _render(
      page,
      PagePainter(
        onPhase: (phase) => phases.add(phase.name),
        beforeBlockText: (canvas, paintedPage, slice) {
          expect(paintedPage, same(page));
          expect(slice, same(page.slices.single));
          phases.add('装饰底层');
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 140, 60),
            Paint()..color = const Color(0xffff0000),
          );
          canvas.translate(160, 160);
        },
      ),
    );
    expect(phases.indexOf('装饰底层'), greaterThan(phases.indexOf('blockBorder')));
    expect(phases.indexOf('装饰底层'), lessThan(phases.indexOf('text')));
    expect(_pixels(result, const Color(0xffff0000)), greaterThan(0));
    expect(_pixels(result, const Color(0xff000000)), greaterThan(0));
  });
}
