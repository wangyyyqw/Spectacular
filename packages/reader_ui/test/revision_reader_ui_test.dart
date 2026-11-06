import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/decorations.dart';
import 'package:reader_ui/annotations/relocator.dart';
import 'package:reader_ui/panels/annotation_panel.dart';
import 'package:reader_ui/panels/bookmark_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

final _style = ComputedStyle(const {
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'white-space': 'pre-wrap',
});

PageContent _page(List<({String text, String cfi})> contents) {
  final blocks = contents
      .map(
        (item) => PageBlock(
          layout: TextLayoutEngine.layout(
            text: item.text,
            style: _style,
            maxWidth: 240,
          ),
          style: _style,
          startCfi: item.cfi,
        ),
      )
      .toList();
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: [
      for (final block in blocks)
        PageBlockSlice(
          block: block,
          startLine: 0,
          endLine: block.layout.lineCount,
          height: block.layout.height,
        ),
    ],
    usedHeight: blocks.fold(0, (sum, b) => sum + b.layout.height),
    pageHeight: 400,
    topPadding: 0,
  );
}

ReaderAnnotation _annotation({
  String quote = '旧版引用',
  String? status,
  String? anchorData,
  String start = 'epubcfi(/6/2!/4/2/1:0)',
  String end = 'epubcfi(/6/2!/4/2/1:4)',
}) => ReaderAnnotation(
  id: 'annotation',
  type: ReaderAnnotationType.thought,
  startCfi: start,
  endCfi: end,
  quote: quote,
  note: '原笔记正文',
  color: 0xFF90CAF9,
  style: ReaderAnnotationStyle.underline,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 2),
  relocationStatus: status,
  relocationReason: status == 'pending' ? '引用已删除' : null,
  anchorData: anchorData,
);

ReaderBookmark _bookmark() => ReaderBookmark(
  id: 'bookmark',
  cfi: 'epubcfi(/6/2!/4/2/1:100)',
  spineIndex: 0,
  label: '原章节 · 旧书签位置',
  createdAt: DateTime(2026, 1, 1),
  relocationStatus: 'pending',
  relocationReason: '原位置已删除',
);

class _Source implements ReaderChapterSource {
  _Source({double pageHeight = 400, int baseOffset = 0}) {
    final layout = TextLayoutEngine.layout(
      text: '新版第一行\n新版第二行\n新版第三行\n新版第四行\n新版第五行\n新版第六行',
      style: _style,
      maxWidth: 240,
    );
    pages = Paginator(pageHeight: pageHeight)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: layout,
              style: _style,
              startCfi: 'epubcfi(/6/2!/4/2/1:$baseOffset)',
            ),
          ],
        )
        .pages;
  }
  late final List<PageContent> pages;
  @override
  int get chapterCount => 1;
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

class _ResizableSource implements ResizableChapterSource {
  _Source source = _Source(pageHeight: 48);
  @override
  int get chapterCount => source.chapterCount;
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      source.loadChapter(spineIndex);
  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  }) async {
    source = _Source(pageHeight: height);
    return true;
  }
}

class _Bookmarks implements ReaderBookmarkStore, RelocatableBookmarkStore {
  final item = _bookmark();
  final relocations = <String>[];
  @override
  Future<List<ReaderBookmark>> list() async => [item];
  @override
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  }) async => null;
  @override
  Future<void> remove(String id) async {}
  @override
  Future<void> relocate(String id, {required String cfi}) async =>
      relocations.add(cfi);
}

class _Annotations
    implements ReaderAnnotationStore, RelocatableAnnotationStore {
  final item = _annotation(status: 'pending');
  final relocations = <({String start, String end})>[];
  @override
  Future<List<ReaderAnnotation>> list() async => [item];
  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    double? opacity,
    String? note,
  }) async => null;
  @override
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    double? opacity,
    String? note,
    bool clearNote = false,
  }) async {}
  @override
  Future<void> remove(String id) async {}
  @override
  Future<void> relocate(
    String id, {
    required String startCfi,
    required String endCfi,
  }) async => relocations.add((start: startCfi, end: endCfi));
}

Future<ReaderSession> _openReader(
  WidgetTester tester, {
  _Source? source,
  ReaderBookmarkStore? bookmarks,
  ReaderAnnotationStore? annotations,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source ?? _Source(),
          store: MemoryReaderProgressStore(),
          bookId: 'revision',
          contentRevision: 'new',
          bookmarks: bookmarks,
          annotations: annotations,
          padding: EdgeInsets.zero,
          showPageFooter: false,
          onSessionReady: (value) => session = value,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _openRecord(WidgetTester tester, String tab, String row) async {
  await tester.tap(find.byType(ReaderView));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('drawer-tab-$tab')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(row)));
  await tester.pumpAndSettle();
}

void main() {
  test('未读完进度恢复到末页后，重排不标记读完，离开再返回才读完', () async {
    final source = _ResizableSource();
    final last = source.source.pages.last;
    final slice = last.slices.first;
    final offset = slice.block.layout.lines[slice.startLine].start;
    final cfi = 'epubcfi(/6/2!/4/2/1:$offset)';
    final store = MemoryReaderProgressStore();
    await store.save(
      'book',
      ReaderProgress(
        spineIndex: 0,
        pageIndex: last.pageIndex,
        cfi: cfi,
        contentRevision: 'new',
      ),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'book',
      contentRevision: 'new',
    );
    await session.open();
    expect(session.progress!.finished, isFalse);
    expect(await session.next(), isFalse);
    await session.jumpToCfi(cfi);
    expect(session.progress!.finished, isFalse, reason: '同页跳转不算离开末页');
    await session.applyContentSize(width: 240, height: 72);
    expect(session.progress!.pageIndex, source.source.pages.length - 1);
    await session.flushProgress();
    expect((await store.load('book'))!.finished, isFalse);
    expect(await session.previous(), isTrue);
    expect(await session.next(), isTrue);
    expect(session.progress!.finished, isTrue);
    session.dispose();
  });

  test('没有已存进度的新书到达末页仍标记读完', () async {
    final session = ReaderSession(
      source: _Source(),
      store: MemoryReaderProgressStore(),
      bookId: 'new-book',
    );
    await session.open();
    expect(session.progress!.finished, isTrue);
    session.dispose();
  });

  test('同版本恢复优先使用真实CFI，保存时保留块基址偏移', () async {
    final source = _Source(pageHeight: 48, baseOffset: 10);
    final store = MemoryReaderProgressStore();
    final target = source.pages[1].slices.first;
    final offset = 10 + target.block.layout.lines[target.startLine].start;
    await store.save(
      'book',
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        cfi: 'epubcfi(/6/2!/4/2/1:$offset)',
        contentRevision: 'same',
        approximate: true,
      ),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'book',
      contentRevision: 'same',
    );
    await session.open();
    expect(session.progress!.pageIndex, 1);
    expect(session.currentCfi, 'epubcfi(/6/2!/4/2/1:$offset)');
    expect(session.approximateRestoration, isTrue);
    await session.next();
    await session.flushProgress();
    final saved = (await store.load('book'))!;
    expect(saved.contentRevision, 'same');
    expect(saved.cfi, session.currentCfi);
    expect(saved.approximate, isFalse);
    session.dispose();
  });

  test('不同内容版本不使用旧CFI和旧页号快取', () async {
    final store = MemoryReaderProgressStore();
    await store.save(
      'book',
      const ReaderProgress(
        spineIndex: 0,
        pageIndex: 2,
        cfi: 'epubcfi(/6/2!/4/2/1:24)',
        contentRevision: 'old',
        finished: true,
      ),
    );
    final session = ReaderSession(
      source: _Source(pageHeight: 48),
      store: store,
      bookId: 'book',
      contentRevision: 'new',
    );
    await session.open();
    expect(session.progress!.pageIndex, 0);
    expect(session.progress!.finished, isFalse);
    expect(session.approximateRestoration, isTrue);
    session.dispose();
  });

  test('CFI合法但内容不同不能绘制，重复引用不选第一条', () {
    final page = _page([
      (text: '新的文字重复引用再重复引用', cfi: 'epubcfi(/6/2!/4/2/1:0)'),
    ]);
    final results = AnnotationRelocator.relocate(
      annotations: [
        _annotation(),
        _annotation(
          quote: '重复引用',
          start: 'epubcfi(/6/2!/4/2/9:0)',
          end: 'epubcfi(/6/2!/4/2/9:4)',
        ),
      ],
      pages: [page],
    );
    expect(results.every((item) => !item.isResolved), isTrue);
    expect(results.last.failure, AnnotationRelocationFailure.ambiguousQuote);
  });

  test('有持久化锚点也必须核对当前文本，待确认不绘制不命中', () {
    final old = AnchorBook(
      revision: 'same',
      chapters: [
        AnchorChapter(
          spineIndex: 0,
          href: '',
          blocks: [
            const AnchorBlock(cfi: 'epubcfi(/6/2!/4/2/1:0)', text: '旧版引用'),
          ],
        ),
      ],
    );
    final record = AnchorRecord(
      original: old.capture(
        'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:4)',
      )!,
    );
    final page = _page([(text: '新版第一行', cfi: 'epubcfi(/6/2!/4/2/1:0)')]);
    final result = AnnotationRelocator.relocate(
      annotations: [
        _annotation(status: 'verified', anchorData: record.encode()),
      ],
      pages: [page],
      contentRevision: 'same',
    );
    expect(result.single.isResolved, isFalse);
    final pending = _annotation(quote: '新版第一行', status: 'pending');
    expect(AnnotationDecorations.linesFor(page, [pending]), isEmpty);
    expect(
      AnnotationDecorations.annotationAt(page, const Offset(10, 10), [pending]),
      isNull,
    );
  });

  test('跨块中间文字完整绘制，CFI块基址不成为绘制偏移', () {
    final page = _page([
      (text: '甲乙', cfi: 'epubcfi(/6/2!/4/2/1:10)'),
      (text: '中间正文', cfi: 'epubcfi(/6/2!/4/2/3:0)'),
      (text: '丙丁', cfi: 'epubcfi(/6/2!/4/2/5:0)'),
    ]);
    final lines = AnnotationDecorations.linesFor(page, [
      _annotation(
        start: 'epubcfi(/6/2!/4/2/1:11)',
        end: 'epubcfi(/6/2!/4/2/5:1)',
        quote: '乙中间正文丙',
      ),
    ]);
    expect(
      lines
          .map(
            (line) =>
                line.line.text.substring(line.startOffset, line.endOffset),
          )
          .join(),
      '乙中间正文丙',
    );
  });

  testWidgets('近似恢复在续读时提示用户', (tester) async {
    final store = MemoryReaderProgressStore();
    await store.save(
      'book',
      const ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        contentRevision: 'new',
        approximate: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: _Source(),
            store: store,
            bookId: 'book',
            contentRevision: 'new',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('阅读位置已近似恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('待确认列表保留原引用、笔记、书签标签和失败原因', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationPanel(
            annotations: [_annotation(status: 'pending')],
            onSelect: (_) {},
            onEdit: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('待修复 · 点击关联原文'), findsOneWidget);
    expect(find.text('旧版引用'), findsOneWidget);
    expect(find.text('原笔记正文'), findsOneWidget);
    expect(find.text('引用已删除'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkPanel(
            bookmarks: [_bookmark()],
            onSelect: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('原章节 · 旧书签位置'), findsOneWidget);
    expect(find.textContaining('待确认'), findsOneWidget);
    expect(find.textContaining('原位置已删除'), findsOneWidget);
  });

  testWidgets('待确认书签不跳旧位置，取消无写入，确认仅调用定位接口', (tester) async {
    final bookmarks = _Bookmarks();
    final session = await _openReader(tester, bookmarks: bookmarks);
    final current = session.currentCfi;
    await _openRecord(tester, 'bookmarks', 'bookmark-row-bookmark');
    expect(session.currentCfi, current);
    expect(find.text('重新定位书签'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(bookmarks.relocations, isEmpty);
    await _openRecord(tester, 'bookmarks', 'bookmark-row-bookmark');
    await tester.tap(find.text('重新定位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消定位'));
    await tester.pumpAndSettle();
    expect(bookmarks.relocations, isEmpty);
    await _openRecord(tester, 'bookmarks', 'bookmark-row-bookmark');
    await tester.tap(find.text('重新定位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用当前位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(bookmarks.relocations, isEmpty);
    await tester.tap(find.text('使用当前位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认关联'));
    await tester.pumpAndSettle();
    expect(bookmarks.relocations, [current]);
    expect(bookmarks.item.label, '原章节 · 旧书签位置');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('待确认笔记选择新版文字并确认，原正文、样式及时间不改', (tester) async {
    final source = _Source();
    final annotations = _Annotations();
    await _openReader(tester, source: source, annotations: annotations);
    await _openRecord(tester, 'annotations', 'annotation-row-annotation');
    expect(find.textContaining('原笔记正文'), findsOneWidget);
    await tester.tap(find.text('重新定位'));
    await tester.pumpAndSettle();
    final line = TextHitTester.lineBoxes(source.pages.first).last;
    await tester.longPressAt(
      tester.getTopLeft(find.byType(ReaderView)) +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('关联此处'));
    await tester.pumpAndSettle();
    expect(find.text('新版位置'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(annotations.relocations, isEmpty);
    await tester.tap(find.text('关联此处'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认关联'));
    await tester.pumpAndSettle();
    expect(annotations.relocations, hasLength(1));
    expect(EpubCfi.parse(annotations.relocations.single.start), isNotNull);
    expect(annotations.item.quote, '旧版引用');
    expect(annotations.item.note, '原笔记正文');
    expect(annotations.item.style, ReaderAnnotationStyle.underline);
    expect(annotations.item.createdAt, DateTime(2026, 1, 1));
    await tester.pumpWidget(const SizedBox());
  });
}
