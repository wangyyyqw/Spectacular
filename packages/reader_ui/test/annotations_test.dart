import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/annotations/decorations.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(String text, {required String cfi, double maxWidth = 160}) {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: _style(),
    maxWidth: maxWidth,
  );
  return PageBlock(layout: layout, style: _style(), startCfi: cfi);
}

PageContent _page(List<PageBlock> blocks) {
  final slices = <PageBlockSlice>[
    for (final block in blocks)
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: block.layout.height,
      ),
  ];
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: slices,
    usedHeight: slices.fold<double>(0, (sum, s) => sum + s.height),
    pageHeight: 600,
    topPadding: 8,
  );
}

ReaderAnnotation _annotation({
  required String id,
  required String start,
  required String end,
  required String quote,
  ReaderAnnotationType type = ReaderAnnotationType.highlight,
  int color = 0xFFFFEB3B,
  int createdMs = 1000,
}) => ReaderAnnotation(
  id: id,
  type: type,
  startCfi: start,
  endCfi: end,
  quote: quote,
  color: color,
  createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
);

void main() {
  group('标注装饰映射（P4-18）', () {
    test('同块标注：行内字符区间与 CFI 偏移一致', () {
      final block = _block('0123456789abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)');
      final page = _page(<PageBlock>[block]);
      final lines = AnnotationDecorations.linesFor(page, <ReaderAnnotation>[
        _annotation(
          id: 'a',
          start: 'epubcfi(/6/4!/4/2/1:3)',
          end: 'epubcfi(/6/4!/4/2/1:8)',
          quote: '34567',
        ),
      ]);
      expect(lines, hasLength(1));
      expect(lines.single.startOffset, 3);
      expect(lines.single.endOffset, 8);
      expect(lines.single.line.text.substring(3, 8), '34567');
    });

    test('跨块标注：起点块从偏移画到块末，终点块从块首画到偏移', () {
      final first = _block('abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)');
      final second = _block('0123456789', cfi: 'epubcfi(/6/4!/4/2/3)');
      final page = _page(<PageBlock>[first, second]);
      final lines = AnnotationDecorations.linesFor(page, <ReaderAnnotation>[
        _annotation(
          id: 'b',
          start: 'epubcfi(/6/4!/4/2/1:6)',
          end: 'epubcfi(/6/4!/4/2/3:4)',
          quote: 'ghij0123',
        ),
      ]);
      expect(lines, hasLength(2));
      final firstLine = lines.firstWhere((l) => l.line.slice == page.slices[0]);
      final secondLine = lines.firstWhere((l) => l.line.slice == page.slices[1]);
      expect(firstLine.startOffset, 6);
      expect(firstLine.endOffset, 10);
      expect(secondLine.startOffset, 0);
      expect(secondLine.endOffset, 4);
    });

    test('无关块/其他章的标注不产生片段', () {
      final block = _block('abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)');
      final page = _page(<PageBlock>[block]);
      final lines = AnnotationDecorations.linesFor(page, <ReaderAnnotation>[
        _annotation(
          id: 'c',
          start: 'epubcfi(/6/8!/4/2/1:0)',
          end: 'epubcfi(/6/8!/4/2/1:5)',
          quote: '别的块',
        ),
      ]);
      expect(lines, isEmpty);
    });

    test('重叠标注按创建时间排序（后来的在上层）', () {
      final block = _block('0123456789abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)');
      final page = _page(<PageBlock>[block]);
      final lines = AnnotationDecorations.linesFor(page, <ReaderAnnotation>[
        _annotation(
          id: 'newer',
          start: 'epubcfi(/6/4!/4/2/1:5)',
          end: 'epubcfi(/6/4!/4/2/1:10)',
          quote: '56789',
          createdMs: 2000,
        ),
        _annotation(
          id: 'older',
          start: 'epubcfi(/6/4!/4/2/1:2)',
          end: 'epubcfi(/6/4!/4/2/1:7)',
          quote: '23456',
          createdMs: 1000,
        ),
      ]);
      expect(lines.map((l) => l.annotation.id), <String>['older', 'newer']);
    });

    test('多行文本：标注跨软换行时每行各有片段', () {
      final block = _block('0123456789abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)');
      final page = _page(<PageBlock>[block]);
      final boxes = AnnotationDecorations.linesFor(page, <ReaderAnnotation>[
        _annotation(
          id: 'd',
          start: 'epubcfi(/6/4!/4/2/1:2)',
          end: 'epubcfi(/6/4!/4/2/1:18)',
          quote: '长区间',
        ),
      ]);
      expect(boxes.length, greaterThanOrEqualTo(2), reason: '跨两行');
      expect(boxes.first.startOffset, 2);
      expect(boxes.last.endOffset, 8, reason: '第二行到 18-10=8');
    });
  });

  group('标注层', () {
    testWidgets('有标注时渲染绘制层，无标注时不渲染', (tester) async {
      final block = _block('0123456789abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)');
      final page = _page(<PageBlock>[block]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: AnnotationLayer(
                page: page,
                annotations: <ReaderAnnotation>[
                  _annotation(
                    id: 'e',
                    start: 'epubcfi(/6/4!/4/2/1:0)',
                    end: 'epubcfi(/6/4!/4/2/1:5)',
                    quote: '01234',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: AnnotationLayer(
                page: page,
                annotations: const <ReaderAnnotation>[],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(AnnotationLayer), findsOneWidget);
    });
  });
}
