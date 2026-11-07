import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub/chapter_layout_cache.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

typedef _ReadLayout = ({List<PageContent> pages, int layouts});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChapterLayoutCache.recent.clear);
  tearDown(ChapterLayoutCache.recent.clear);

  test('同内容版本重开时基础 CSS 变量不同不能复用旧字号页面', () async {
    ComputedStyle style(String size) => ComputedStyle(
      const {'font-size': '16px'},
      customProperties: {'--size': size},
    );
    final before = style('16px');
    final after = style('32px');
    expect(const ReaderOverrides().apply(before), same(before));
    expect(const ReaderOverrides().apply(after).customProperties, {
      '--size': '32px',
    });
    await _expectReopenedLayout(
      'p { font-size: var(--size); margin: 0; }',
      before,
      after,
      (style) => style.fontSize,
      (16.0, 32.0),
    );
  });

  test('同数值行高但继承方式不同不能复用旧页面', () async {
    final before = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
    });
    final after = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '24px',
    });
    expect(before.lineHeight, after.lineHeight);
    expect(before.unitlessLineHeightFactor, 1.5);
    expect(after.unitlessLineHeightFactor, isNull);
    await _expectReopenedLayout(
      'p { font-size: 32px; margin: 0; }',
      before,
      after,
      (style) => style.lineHeight,
      (48.0, 24.0),
    );
  });

  test('原始声明相同但父级行高继承不同不能复用旧页面', () async {
    ComputedStyle inherited(String lineHeight) => ComputedStyle(const {
      'font-size': '16px',
    }, parent: ComputedStyle({'font-size': '16px', 'line-height': lineHeight}));
    final before = inherited('1.5');
    final after = inherited('24px');
    expect(before.values, after.values);
    expect(before.explicitProperties, after.explicitProperties);
    expect(before.customProperties, after.customProperties);
    expect(before.unitlessLineHeightFactor, 1.5);
    expect(after.unitlessLineHeightFactor, isNull);
    await _expectReopenedLayout(
      'p { font-size: 32px; margin: 0; }',
      before,
      after,
      (style) => style.lineHeight,
      (48.0, 24.0),
    );
  });

  test('基础样式集合插入顺序不同仍复用同一完成页面', () async {
    final before = _orderedStyle(false);
    final after = _orderedStyle(true);
    expect(before.values, after.values);
    expect(before.customProperties, after.customProperties);
    expect(before.explicitProperties, after.explicitProperties);
    expect(before.values.keys.toList(), isNot(after.values.keys.toList()));
    final bytes = buildCssChapterBook(
      body: '<p>基准正文</p>',
      css: 'p { font-size: var(--size); margin: 0; }',
    );
    final first = await _read(bytes, before, '同值不同顺序');
    final reopened = await _read(bytes, after, '同值不同顺序');
    expect(first.layouts, 1);
    expect(_textStyle(first.pages).fontSize, 20);
    expect(reopened.layouts, 0);
    expect(reopened.pages, same(first.pages));
  });

  test('只改变阅读器文字与背景颜色仍复用布局', () async {
    final source = await EpubChapterSource.open(
      buildCssChapterBook(body: '<p>基准正文</p>'),
      style: ComputedStyle(const {'font-size': '21px'}),
      contentVersion: '仅阅读颜色变化',
      verifyCrc: false,
    );
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    final first = await source.loadChapter(0);
    expect(_textStyle(first).fontSize, 21);
    expect(source.chapterLayoutCount, 1);
    await source.applyOverrides(
      const ReaderOverrides(
        textColor: Color(0xFF123456),
        backgroundColor: Color(0xFFFEDCBA),
      ),
    );
    final recolored = await source.loadChapter(0);
    expect(recolored, same(first));
    expect(source.chapterLayoutCount, 1);
  });
}

ComputedStyle _orderedStyle(bool reverse) {
  const values = {
    'font-size': '16px',
    'line-height': '1.5',
    'text-align': 'left',
  };
  const custom = {'--size': '20px', '--unused': '0px'};
  const declared = ['text-align', 'text-spacing-trim'];
  return ComputedStyle(
    Map.fromEntries(
      reverse ? values.entries.toList().reversed : values.entries,
    ),
    customProperties: Map.fromEntries(
      reverse ? custom.entries.toList().reversed : custom.entries,
    ),
    explicitProperties: (reverse ? values.keys.toList().reversed : values.keys)
        .toSet(),
    declaredTextProperties: (reverse ? declared.reversed : declared).toSet(),
  );
}

Future<void> _expectReopenedLayout(
  String css,
  ComputedStyle before,
  ComputedStyle after,
  double Function(ComputedStyle) metric,
  (double, double) expected,
) async {
  expect(before.layoutFingerprint, after.layoutFingerprint);
  final bytes = buildCssChapterBook(body: '<p>${'基准正文' * 80}</p>', css: css);
  final first = await _read(bytes, before, '基础样式同版本');
  final cold = await _read(bytes, after, '基础样式冷排对照');
  expect(first.layouts, 1);
  expect(cold.layouts, 1);
  expect(metric(_textStyle(first.pages)), expected.$1);
  expect(metric(_textStyle(cold.pages)), expected.$2);
  expect(_geometry(first.pages), isNot(equals(_geometry(cold.pages))));

  final reopened = await _read(bytes, after, '基础样式同版本');
  expect(
    metric(_textStyle(reopened.pages)),
    expected.$2,
    reason:
        '关闭后同版本重开必须按本次基础样式排版；'
        '本次实际排版次数=${reopened.layouts}，'
        '与旧页面同一对象=${identical(reopened.pages, first.pages)}',
  );
  expect(_geometry(reopened.pages), _geometry(cold.pages));
  expect(reopened.pages, isNot(same(first.pages)));
  expect(reopened.layouts, 1);
}

Future<_ReadLayout> _read(
  Uint8List bytes,
  ComputedStyle style,
  String version,
) async {
  final source = await EpubChapterSource.open(
    bytes,
    style: style,
    contentVersion: version,
    verifyCrc: false,
  );
  try {
    final pages = await source.loadChapter(0);
    return (pages: pages, layouts: source.chapterLayoutCount);
  } finally {
    source.close();
    await source.preparationsStopped;
  }
}

ComputedStyle _textStyle(List<PageContent> pages) => pages
    .expand((page) => page.slices)
    .firstWhere((slice) => slice.block.layout.text.contains('基准正文'))
    .block
    .style!;

List<Object> _geometry(List<PageContent> pages) => [
  for (final page in pages) ...[
    (page.usedHeight, page.pageHeight, page.topPadding),
    for (final slice in page.slices) ...[
      (slice.startLine, slice.endLine, slice.height),
      for (final line in slice.block.layout.lines)
        (line.start, line.end, line.top, line.height, line.baseline),
    ],
  ],
];
