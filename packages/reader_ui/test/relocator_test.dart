import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/relocator.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _pageFor(
  List<({String text, String cfi})> blocks, {
  int pageIndex = 0,
}) {
  final slices = <PageBlockSlice>[
    for (final block in blocks)
      PageBlockSlice(
        block: PageBlock(
          layout: TextLayoutEngine.layout(
            text: block.text,
            style: _style(),
            maxWidth: 160,
          ),
          style: _style(),
          startCfi: block.cfi,
        ),
        startLine: 0,
        endLine: 0,
        height: 100,
      ),
  ];
  return PageContent(
    spineIndex: 0,
    pageIndex: pageIndex,
    slices: slices,
    usedHeight: 100.0 * slices.length,
    pageHeight: 600,
    topPadding: 8,
  );
}

ReaderAnnotation _annotation({
  String start = 'epubcfi(/6/4!/4/2/1:3)',
  String end = 'epubcfi(/6/4!/4/2/1:8)',
  required String quote,
  String? before,
  String? after,
}) => ReaderAnnotation(
  id: 'a',
  type: ReaderAnnotationType.highlight,
  startCfi: start,
  endCfi: end,
  quote: quote,
  contextBefore: before,
  contextAfter: after,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('标注重定位（P4-20，§30.4）', () {
    test('CFI 命中当前排版 → verified，位置不变', () {
      final pages = <PageContent>[
        _pageFor(<({String text, String cfi})>[
          (text: '0123456789abcdefghij', cfi: 'epubcfi(/6/4!/4/2/1)'),
        ]),
      ];
      final results = AnnotationRelocator.relocate(
        annotations: <ReaderAnnotation>[_annotation(quote: '34567')],
        pages: pages,
      );
      expect(results, hasLength(1));
      expect(results.single.status, AnnotationRelocationStatus.verified);
      expect(results.single.startCfi, 'epubcfi(/6/4!/4/2/1:3)');
      expect(results.single.isResolved, isTrue);
    });

    test('CFI 块不存在但引文唯一 → relocated，重建区间', () {
      final pages = <PageContent>[
        _pageFor(<({String text, String cfi})>[
          (text: '前面的话找学习资源然后走了', cfi: 'epubcfi(/6/4!/4/2/9)'),
        ]),
      ];
      final results = AnnotationRelocator.relocate(
        annotations: <ReaderAnnotation>[
          _annotation(
            start: 'epubcfi(/6/4!/4/2/1:3)',
            end: 'epubcfi(/6/4!/4/2/1:8)',
            quote: '找学习资源',
          ),
        ],
        pages: pages,
      );
      expect(results.single.status, AnnotationRelocationStatus.relocated);
      expect(results.single.startCfi, 'epubcfi(/6/4!/4/2/9:4)');
      expect(results.single.endCfi, 'epubcfi(/6/4!/4/2/9:9)');
    });

    test('引文多处无上下文 → 待确认，不自动取第一条', () {
      final pages = <PageContent>[
        _pageFor(<({String text, String cfi})>[
          (text: '重复的文字xx重复的文字', cfi: 'epubcfi(/6/4!/4/2/9)'),
        ]),
      ];
      final results = AnnotationRelocator.relocate(
        annotations: <ReaderAnnotation>[
          _annotation(
            start: 'epubcfi(/6/4!/4/2/1:0)',
            end: 'epubcfi(/6/4!/4/2/1:5)',
            quote: '重复的文字',
          ),
        ],
        pages: pages,
      );
      expect(results.single.status, AnnotationRelocationStatus.failed);
      expect(
        results.single.failure,
        AnnotationRelocationFailure.ambiguousQuote,
      );
    });

    test('引文多处且上下文都对不上 → 失败但保留数据', () {
      final pages = <PageContent>[
        _pageFor(<({String text, String cfi})>[
          (text: '重复的文字xx重复的文字', cfi: 'epubcfi(/6/4!/4/2/9)'),
        ]),
      ];
      final results = AnnotationRelocator.relocate(
        annotations: <ReaderAnnotation>[
          _annotation(
            start: 'epubcfi(/6/4!/4/2/1:0)',
            end: 'epubcfi(/6/4!/4/2/1:5)',
            quote: '重复的文字',
            before: '不存在的前文',
          ),
        ],
        pages: pages,
      );
      expect(results.single.status, AnnotationRelocationStatus.failed);
      expect(results.single.isResolved, isFalse);
      expect(results.single.annotation.quote, '重复的文字', reason: '数据保留');
    });

    test('上下文消歧：多处命中时用前后文选中正确位置', () {
      final pages = <PageContent>[
        _pageFor(<({String text, String cfi})>[
          (text: '甲处重复的文字乙处重复的文字', cfi: 'epubcfi(/6/4!/4/2/9)'),
        ]),
      ];
      final results = AnnotationRelocator.relocate(
        annotations: <ReaderAnnotation>[
          _annotation(
            start: 'epubcfi(/6/4!/4/2/1:0)',
            end: 'epubcfi(/6/4!/4/2/1:4)',
            quote: '重复的文字',
            before: '乙处',
          ),
        ],
        pages: pages,
      );
      expect(results.single.status, AnnotationRelocationStatus.relocated);
      expect(results.single.startCfi, 'epubcfi(/6/4!/4/2/9:9)');
    });

    test('引文找不到 → quoteNotFound', () {
      final pages = <PageContent>[
        _pageFor(<({String text, String cfi})>[
          (text: '完全无关的正文', cfi: 'epubcfi(/6/4!/4/2/9)'),
        ]),
      ];
      final results = AnnotationRelocator.relocate(
        annotations: <ReaderAnnotation>[
          _annotation(
            start: 'epubcfi(/6/4!/4/2/1:0)',
            end: 'epubcfi(/6/4!/4/2/1:4)',
            quote: '找不到的文字',
          ),
        ],
        pages: pages,
      );
      expect(results.single.status, AnnotationRelocationStatus.failed);
      expect(results.single.failure, AnnotationRelocationFailure.quoteNotFound);
    });

    test('空页/空标注返回空列表', () {
      expect(
        AnnotationRelocator.relocate(
          annotations: <ReaderAnnotation>[_annotation(quote: 'x')],
          pages: const <PageContent>[],
        ),
        isEmpty,
      );
      expect(
        AnnotationRelocator.relocate(
          annotations: const <ReaderAnnotation>[],
          pages: <PageContent>[
            _pageFor(<({String text, String cfi})>[
              (text: '正文', cfi: 'epubcfi(/6/4!/4/2/1)'),
            ]),
          ],
        ),
        isEmpty,
      );
    });
  });
}
