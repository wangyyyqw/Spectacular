import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/annotations/annotation_style_painter.dart';
import 'package:reader_ui/annotations/decorations.dart';
import 'package:reader_ui/annotations/mark_settings.dart';
import 'package:reader_ui/annotations/thought_marker.dart';

const _cfi = 'epubcfi(/6/2!/4/2/1:0)';

Future<ByteData> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 120);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _alpha(ByteData pixels, int left, int top) =>
    pixels.getUint8((top * 180 + left) * 4 + 3);

ReaderAnnotation _annotation({
  String id = 'mark',
  String end = 'epubcfi(/6/2!/4/2/1:20)',
  ReaderAnnotationType type = ReaderAnnotationType.mark,
}) => ReaderAnnotation(
  id: id,
  type: type,
  startCfi: _cfi,
  endCfi: end,
  quote: 'abcdefghijklmnopqrst',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

List<PageContent> _pages({
  double height = 120,
  bool rtl = false,
  bool vertical = false,
  bool separateBlocks = false,
}) {
  final style = ComputedStyle({
    'font-family': 'Ahem',
    'font-size': '16px',
    'line-height': '2',
    if (rtl) 'direction': 'rtl',
    if (vertical) 'writing-mode': 'vertical-rl',
  });
  PageBlock block(String text, String cfi) => PageBlock(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 160),
    style: style,
    startCfi: cfi,
    spaceAfter: separateBlocks ? 20 : 0,
  );
  return Paginator(pageHeight: height)
      .measureChapter(
        blocks: [
          if (separateBlocks) ...[
            block('abcdefghij', _cfi),
            block('klmnopqrst', 'epubcfi(/6/2!/4/2/3:0)'),
          ] else
            block('abcdefghijklmnopqrst', _cfi),
        ],
      )
      .pages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('九种样式产生稳定且互不相同的像素，文字染色由正文管线处理', () async {
    final signatures = <String>{};
    for (final style in ReaderAnnotationStyle.values) {
      final data = await _pixels(
        (canvas) => AnnotationStylePainter.paint(
          canvas,
          const Rect.fromLTWH(10, 10, 120, 30),
          color: const Color(0xFFFF0000),
          style: style,
        ),
      );
      final bytes = data.buffer.asUint8List();
      if (style == ReaderAnnotationStyle.tint) {
        expect(bytes.every((value) => value == 0), isTrue);
      } else {
        expect(bytes.any((value) => value != 0), isTrue, reason: style.name);
      }
      expect(signatures.add(bytes.join(',')), isTrue, reason: style.name);
    }
    expect(signatures, hasLength(9));
  });

  test('半高底色只覆盖下半行，默认透明度保持半透明', () async {
    final pixels = await _pixels(
      (canvas) => AnnotationStylePainter.paint(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 30),
        color: const Color(0xFFFFFF00),
        style: ReaderAnnotationStyle.halfBackground,
        fillAlpha: ReaderAnnotationStyle.halfBackground.defaultOpacity,
      ),
    );
    expect(_alpha(pixels, 30, 18), 0);
    expect(_alpha(pixels, 30, 32), inInclusiveRange(85, 88));
  });

  test('底色连行开关只填相邻同块行距，不跨文本块', () async {
    final page = _pages().single;
    final annotation = _annotation();
    final lines = AnnotationDecorations.linesFor(page, [annotation]);
    final upper = AnnotationDecorations.rectsFor(lines.first).first;
    final lower = AnnotationDecorations.rectsFor(lines.last).first;
    final gap = ((upper.bottom + lower.top) / 2).floor();
    final separated = await _pixels(
      (canvas) => ReaderAnnotationPainting.paintBackgrounds(canvas, page, [
        annotation,
      ], const ReaderMarkSettings()),
    );
    final joined = await _pixels(
      (canvas) => ReaderAnnotationPainting.paintBackgrounds(canvas, page, [
        annotation,
      ], const ReaderMarkSettings(joinBackgroundLines: true)),
    );
    expect(_alpha(separated, 10, gap), 0);
    expect(_alpha(joined, 10, gap), greaterThan(0));
    final splitPage = _pages(separateBlocks: true).single;
    final cross = _annotation(end: 'epubcfi(/6/2!/4/2/3:10)');
    final splitLines = AnnotationDecorations.linesFor(splitPage, [cross]);
    final middle =
        ((AnnotationDecorations.rectsFor(splitLines.first).first.bottom +
                    AnnotationDecorations.rectsFor(splitLines.last).first.top) /
                2)
            .floor();
    final blocks = await _pixels(
      (canvas) => ReaderAnnotationPainting.paintBackgrounds(canvas, splitPage, [
        cross,
      ], const ReaderMarkSettings(joinBackgroundLines: true)),
    );
    expect(_alpha(blocks, 10, middle), 0);
  });

  test('墨水屏背景和染色降级实线，其他线型保留形状', () {
    for (final style in ReaderAnnotationStyle.values) {
      expect(
        style.inkStyle,
        [
              ReaderAnnotationStyle.background,
              ReaderAnnotationStyle.halfBackground,
              ReaderAnnotationStyle.tint,
            ].contains(style)
            ? ReaderAnnotationStyle.underline
            : style,
      );
    }
  });

  test('想法只在结束页绘制一次，点击目标为44dp', () {
    final pages = _pages(height: 32);
    final thought = _annotation(type: ReaderAnnotationType.thought);
    expect(pages, hasLength(2));
    final first = ThoughtMarkerGeometry.markersFor(
      pages.first,
      AnnotationDecorations.linesFor(pages.first, [thought]),
      contentWidth: 160,
    );
    final last = ThoughtMarkerGeometry.markersFor(
      pages.last,
      AnnotationDecorations.linesFor(pages.last, [thought]),
      contentWidth: 160,
    );
    expect(first, isEmpty);
    expect(last, hasLength(1));
    expect(last.single.center.dx, 168);
    expect(last.single.touchRect.size, const Size(44, 44));
    expect(
      AnnotationDecorations.annotationAt(
        pages.last,
        last.single.center + const Offset(0, 21),
        [thought],
        contentWidth: 160,
      )?.id,
      thought.id,
    );
  });

  test('RTL 和竖排图标在左页边，多图标18dp步进且页底向上错开', () {
    for (final (rtl, vertical) in [(true, false), (false, true)]) {
      final page = _pages(rtl: rtl, vertical: vertical).first;
      final thought = _annotation(type: ReaderAnnotationType.thought);
      final marker = ThoughtMarkerGeometry.markersFor(
        page,
        AnnotationDecorations.linesFor(page, [thought]),
        contentWidth: 160,
      ).single;
      expect(marker.center.dx, -8);
    }
    final page = _pages(height: 64).single;
    final thoughts = List.generate(
      3,
      (index) =>
          _annotation(id: 'thought-$index', type: ReaderAnnotationType.thought),
    );
    final markers = ThoughtMarkerGeometry.markersFor(
      page,
      AnnotationDecorations.linesFor(page, thoughts),
      contentWidth: 160,
    );
    expect(markers, hasLength(3));
    expect(markers[1].center.dy - markers[0].center.dy, 18);
    expect(markers[2].center.dy - markers[1].center.dy, 18);
    expect(markers.last.center.dy, lessThanOrEqualTo(58));
  });
}
