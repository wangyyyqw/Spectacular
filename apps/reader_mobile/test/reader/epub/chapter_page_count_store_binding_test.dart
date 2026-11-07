import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub/book_page_counter.dart';

import '../support/css_chapter_book.dart';

class _MemoryCountCache implements BookPageCountStore {
  final saved = <String, Map<int, int>>{};
  final loads = <String>[];

  @override
  Future<Map<int, int>> load(String layoutKey) async {
    loads.add(layoutKey);
    return Map.of(saved[layoutKey] ?? {});
  }

  @override
  Future<void> save(String layoutKey, Map<int, int> counts) async {
    saved[layoutKey] = Map.of(counts);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实章节先排版再绑定存储，实测计数覆盖缓存且状态身份不变', () async {
    final source = await openCssChapter(body: '<p>${'真实章节正文' * 80}</p>');
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    final state = source.pageCountState;
    source.setCurrentReadingChapter(0);
    source.setPageCountingActive(true);
    expect(pages, isNotEmpty);
    expect(state.value.isComplete, isTrue);
    expect(state.value.completedPages, pages.length);
    final layoutKey = state.value.layoutKey;
    final cache = _MemoryCountCache()
      ..saved[layoutKey] = {0: pages.length + 99};

    source.setPageCountStore(cache);
    expect(source.pageCountState, same(state));
    source.setPageCountingActive(false);
    await source.flushPageCounts();
    expect(cache.loads, [layoutKey]);
    expect(cache.saved, {
      layoutKey: {0: pages.length},
    });
    source.setPageCountingActive(true);
    expect(state.value.isComplete, isTrue);
    expect(state.value.completedPages, pages.length);
    expect(await source.loadChapter(0), same(pages));
    expect(source.chapterLayoutCount, 1);

    source.setPageCountingActive(false);
    await source.flushPageCounts();
    source.close();
    source.close();
    expect(source.isClosed, isTrue);
    expect(cache.saved[layoutKey], {0: pages.length});
  });
}
