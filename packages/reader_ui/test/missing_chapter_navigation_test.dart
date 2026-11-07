import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_session.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _page(int spine, int page) {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: '第 $spine 章第 $page 页',
    style: style,
    maxWidth: 280,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: page,
    slices: [
      PageBlockSlice(
        block: PageBlock(layout: layout, style: style),
        startLine: 0,
        endLine: layout.lineCount,
        height: 300,
      ),
    ],
    usedHeight: 300,
    pageHeight: 300,
    topPadding: 0,
  );
}

class _MissingSource
    implements ReaderChapterSource, MissingChapterSource, TocChapterSource {
  _MissingSource(this.missing);

  final Set<int> missing;

  @override
  int get chapterCount => 5;

  @override
  bool isChapterMissing(int spineIndex) => missing.contains(spineIndex);

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async =>
      missing.contains(spineIndex)
      ? const <PageContent>[]
      : [for (var page = 0; page < 2; page++) _page(spineIndex, page)];

  @override
  List<TocEntry> get toc => <TocEntry>[
    const TocEntry(title: '第一章', spineIndex: 0),
    const TocEntry(title: '缺章二', spineIndex: 1, missing: true),
    const TocEntry(title: '第三章', spineIndex: 2),
    const TocEntry(title: '缺章四', spineIndex: 3, missing: true),
    const TocEntry(title: '第五章', spineIndex: 4),
  ];
}

void main() {
  test('冷开目标缺章优先后一章，末尾缺章回退前一章', () async {
    final source = _MissingSource(<int>{1, 3});
    final store = MemoryReaderProgressStore();
    await store.save(
      'missing-next',
      const ReaderProgress(spineIndex: 1, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'missing-next',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(session.progress?.spineIndex, 2);

    final tailSource = _MissingSource(<int>{1, 3, 4});
    final tailStore = MemoryReaderProgressStore();
    await tailStore.save(
      'missing-tail',
      const ReaderProgress(spineIndex: 4, pageIndex: 0),
    );
    final tail = ReaderSession(
      source: tailSource,
      store: tailStore,
      bookId: 'missing-tail',
    );
    addTearDown(tail.dispose);
    await tail.open();
    expect(tail.progress?.spineIndex, 2);
  });

  test('前后翻页与章节跳转跳过缺章且保留原目录层级', () async {
    final source = _MissingSource(<int>{1, 3});
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'missing-nav',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(session.progress?.spineIndex, 0);
    expect(await session.next(), isTrue);
    expect(session.progress?.spineIndex, 0);
    expect(session.progress?.pageIndex, 1);
    expect(await session.next(), isTrue);
    expect(session.progress?.spineIndex, 2);
    expect(session.progress?.pageIndex, 0);
    expect(await session.previous(), isTrue);
    expect(session.progress?.spineIndex, 0);
    expect(await session.jumpToChapter(1), isTrue);
    expect(session.progress?.spineIndex, 2, reason: '目标缺章时向后找');
    expect(await session.jumpToChapter(3), isTrue);
    expect(session.progress?.spineIndex, 4, reason: '目标缺章时向后找');
    expect(await session.jumpToChapter(4), isTrue);
    expect(session.progress?.spineIndex, 4);
    expect(await session.jumpToChapter(1), isTrue);
    expect(session.progress?.spineIndex, 2, reason: '向前跳至缺章仍优先后续正文');
    expect(await session.jumpToCfi('epubcfi(/6/8!/4/2:0)'), isTrue);
    expect(session.progress?.spineIndex, 4);
    expect(
      session.toc.where((entry) => entry.missing).map((e) => e.spineIndex),
      [1, 3],
    );
  });

  test('连续缺章一次跳过，未知加载异常仍按错误处理', () async {
    final source = _MissingSource(<int>{1, 2, 3});
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'missing-consecutive',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(await session.next(), isTrue);
    expect(await session.next(), isTrue);
    expect(session.progress?.spineIndex, 4);

    final failing = _ThrowingSource();
    final failedSession = ReaderSession(
      source: failing,
      store: MemoryReaderProgressStore(),
      bookId: 'missing-unknown-error',
    );
    addTearDown(failedSession.dispose);
    await failedSession.open();
    expect(failedSession.error, isA<StateError>());
    expect('${failedSession.error}', contains('章节损坏'));
  });

  testWidgets('缺失目录项保留原文案与层级，可展开子项但禁止导航', (tester) async {
    final selected = <TocEntry>[];
    final entries = <TocEntry>[
      const TocEntry(
        title: '缺章二',
        spineIndex: 1,
        missing: true,
        children: <TocEntry>[TocEntry(title: '子节', spineIndex: 2)],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TocPanel(
            entries: entries,
            currentSpineIndex: 0,
            onSelect: selected.add,
          ),
        ),
      ),
    );
    expect(find.text('缺章二（章节缺失）'), findsOneWidget);
    expect(find.text('子节'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('toc-toggle-1-缺章二')));
    await tester.pump();
    expect(find.text('子节'), findsOneWidget);
    await tester.tap(find.text('缺章二（章节缺失）'));
    await tester.pump();
    expect(selected, isEmpty);
  });

  test('全书没有可读章节时给出明确错误', () async {
    final source = _MissingSource(<int>{0, 1, 2, 3, 4});
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'missing-all',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(session.hasContent, isFalse);
    expect(session.error, isA<StateError>());
    expect('${session.error}', contains('全书没有可读章节'));
  });
}

class _ThrowingSource
    implements ReaderChapterSource, MissingChapterSource, TocChapterSource {
  @override
  int get chapterCount => 2;

  @override
  bool isChapterMissing(int spineIndex) => false;

  @override
  late final List<TocEntry> toc = <TocEntry>[
    const TocEntry(title: '坏章', spineIndex: 0),
    const TocEntry(title: '好章', spineIndex: 1),
  ];

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 0) {
      throw StateError('章节损坏');
    }
    return <PageContent>[_page(spineIndex, 0)];
  }
}
