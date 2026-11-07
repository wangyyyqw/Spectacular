import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/reader/epub/book_fonts.dart';
import 'package:reader_mobile/reader/epub/book_resources.dart';
import 'package:reader_mobile/reader/epub/chapter_structure.dart';
import 'package:reader_mobile/reader/epub/chapter_styles.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/css_chapter_book.dart';

int _holdWorker(SendPort ready) {
  ready.send(true);
  while (true) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BookResources resources;
  late BookFonts fonts;
  late ChapterStyles styles;
  late ChapterStructureStore structures;

  setUp(() async {
    final document = (await openEpub(
      buildCssChapterBook(body: '<p>清理后重新准备章节结构</p>', css: 'p {color: red}'),
      verifyCrc: false,
    )).document!;
    resources = BookResources(document);
    fonts = BookFonts(resources, onFontsChanged: (_) {});
    styles = ChapterStyles(resources, fonts);
    structures = ChapterStructureStore(
      resources,
      styles,
      ComputedStyle(const {'font-size': '16px'}),
    );
  });

  tearDown(() async {
    structures.close();
    styles.close();
    fonts.close();
    resources.close();
    await structures.preparationsStopped;
    await styles.preparationsStopped;
    await resources.preparationsStopped;
    expect(resources.preparationWorker.activeIsolates, 0);
    expect(resources.preparationWorker.openPortCount, 0);
  });

  test('结构准备升级阅读优先级时穿过样式等待并抢占后台 worker', () async {
    await resources.prepareChapter(0);
    final ready = ReceivePort();
    addTearDown(ready.close);
    final background = resources.preparationWorker.schedule(
      '占用后台解析槽',
      () => ready.sendPort,
      _holdWorker,
      priority: ChapterLayoutPriority.pageCount,
    );
    await ready.first;
    final preempted = expectLater(
      background.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    final handle = structures.schedule(
      0,
      320,
      priority: ChapterLayoutPriority.pageCount,
    );
    await Future<void>.delayed(Duration.zero);
    handle.promote(ChapterLayoutPriority.reading);
    await handle.result;
    await preempted;
    expect(structures.preparations, 1);
  });

  test('清理取消旧准备，同键新结果保留缓存身份并在关闭后释放资源', () async {
    final stale = structures.schedule(0, 320);
    final cancelled = expectLater(
      stale.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    structures.clear();
    final current = structures.schedule(0, 320);

    await cancelled;
    final result = await current.result;
    expect(structures.preparations, 1);
    expect(structures.length, 1);
    expect(await structures.schedule(0, 320).result, same(result));
    expect(structures.hits, 1);
    expect(structures.preparations, 1);

    structures.close();
    resources.close();
    await structures.preparationsStopped;
    await resources.preparationsStopped;
    expect(structures.length, 0);
    expect(resources.preparationWorker.activeIsolates, 0);
    expect(resources.preparationWorker.openPortCount, 0);
    await expectLater(
      structures.schedule(0, 320).result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
  });
}
