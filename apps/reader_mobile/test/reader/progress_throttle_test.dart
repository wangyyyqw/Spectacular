import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

/// 找 test_corpus 里的样书（多页，能真正翻页）。
Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

/// 记录写入次数的内存进度存储。
class _CountingStore implements ReaderProgressStore {
  final Map<String, ReaderProgress> items = <String, ReaderProgress>{};
  int writes = 0;

  @override
  Future<ReaderProgress?> load(String bookId) async => items[bookId];

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    writes += 1;
    items[bookId] = progress;
  }

  @override
  Future<void> clear(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async => Map.of(items);
}

/// 同一段文字跨两页，且两页重叠包含保存行；真机冷启动曾因此退一页。
class _OverlappingBoundarySource implements ReaderChapterSource {
  static const String _cfi = 'epubcfi(/6/2!/4/2/1)';

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: 'alpha\nbeta\ngamma',
      style: style,
      maxWidth: 120,
    );
    final block = PageBlock.styled(
      layout: layout,
      style: style,
      containingWidth: 120,
      startCfi: _cfi,
    );
    PageContent page(int index, int startLine) => PageContent(
      spineIndex: 0,
      pageIndex: index,
      slices: <PageBlockSlice>[
        PageBlockSlice(
          block: block,
          startLine: startLine,
          endLine: layout.lineCount,
          height: 48,
        ),
      ],
      usedHeight: 48,
      pageHeight: 200,
      topPadding: 0,
    );
    return <PageContent>[page(0, 0), page(1, 1)];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 使用 app 层的章节源（真实 EPUB 分页）。
  late ReaderSession session;
  late _CountingStore store;

  Future<void> openSource() async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    store = _CountingStore();
    session = ReaderSession(
      source: source,
      store: store,
      bookId: 'throttle-book',
      persistInterval: const Duration(milliseconds: 60),
    );
    await session.open();
  }

  test('连续翻页按间隔合并写库（P4-10）', () async {
    await openSource();
    final start = session.progress!;
    var moved = 0;
    // 快速连续翻 10 页（不等待节流窗口）。
    for (var i = 0; i < 10; i++) {
      final changed = await session.next();
      if (!changed) {
        break;
      }
      moved += 1;
    }
    expect(moved, greaterThan(0), reason: '测试书应能翻页');
    expect(
      store.writes,
      lessThanOrEqualTo(1),
      reason: '节流窗口内连续翻页只写一次（首次变化立即写）',
    );
    // 等节流窗口后再翻一页，应触发 trailing 写入。
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await session.next();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(store.writes, inInclusiveRange(1, 3));
    expect(session.progress, isNot(start));
    session.dispose();
  });

  test('flushProgress 立即落盘（退出/切后台）', () async {
    await openSource();
    await session.next();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final before = store.writes;
    await session.next();
    await session.flushProgress();
    expect(store.writes, greaterThan(before));
    expect(store.items['throttle-book'], session.progress);
    session.dispose();
  });

  test('值未变化不写库（去重口径）', () async {
    await openSource();
    final writesAfterOpen = store.writes;
    await session.flushProgress();
    expect(store.writes, writesAfterOpen, reason: '位置没变不重复写');
    session.dispose();
  });

  test('同版本保存后按页码恢复到最后阅读页', () async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    store = _CountingStore();
    session = ReaderSession(
      source: source,
      store: store,
      bookId: 'restore-exact-page',
      contentRevision: 'revision-1',
    );
    await session.open();
    expect(await session.next(), isTrue);
    final saved = session.progress!;
    await session.flushProgress();
    session.dispose();

    final reopened = ReaderSession(
      source: source,
      store: store,
      bookId: 'restore-exact-page',
      contentRevision: 'revision-1',
    );
    await reopened.open();
    expect(reopened.progress, saved, reason: '同版本且排版未变时应恢复到保存的精确页');
    reopened.dispose();
  });

  test('同版本冷启动优先保留包含 CFI 的精确页', () async {
    final source = _OverlappingBoundarySource();
    store = _CountingStore();
    session = ReaderSession(
      source: source,
      store: store,
      bookId: 'restore-overlapping-boundary',
      contentRevision: 'revision-1',
    );
    await session.open();
    expect(await session.next(), isTrue);
    expect(session.progress?.pageIndex, 1);
    final saved = session.progress!;
    await session.flushProgress();
    session.dispose();

    final reopened = ReaderSession(
      source: _OverlappingBoundarySource(),
      store: store,
      bookId: 'restore-overlapping-boundary',
      contentRevision: 'revision-1',
    );
    await reopened.open();
    expect(reopened.progress, saved, reason: '保存页包含 CFI 时不能因前一页也包含同一行而回退');
    reopened.dispose();
  });
}
