import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_ui/reader_session.dart';

import '../../reader_core/test/audit/audit_epub_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 夹具与连续交互保持线性，避免拆分后掩盖任务重启；清理阶段始终释放准备门。
  test('正式 EPUB 在 18→19→20 连续翻页后接管尚未完成的邻章预取', () async {
    final bytes = auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/>'
          '</rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
          'unique-identifier="id"><metadata '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">chapter-prefetch</dc:identifier>'
          '<dc:title>连续跨章预取回归</dc:title></metadata><manifest>'
          '<item id="current" href="current.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '<item id="next" href="next.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="current"/>'
          '<itemref idref="next"/></spine></package>',
      'current.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '${List.generate(20, (i) => '<p style="break-before:page">本章第 ${i + 1} 页正文。</p>').join()}'
          '</body></html>',
      'next.xhtml': auditChapter('next', '下一章正文。'),
    });
    final source = await const EpubFormatOpener().openBytes(
      bytes,
      options: const ReaderOpenOptions(
        contentWidth: 366.6666666666667,
        contentHeight: 773.1694444444443,
      ),
    );
    final started = Completer<void>();
    final release = Completer<void>();
    final preparedSpines = <int>[];
    source.setChapterPreparer((spine) async {
      preparedSpines.add(spine);
      if (spine == 1) {
        started.complete();
        await release.future;
      }
    });
    final store = MemoryReaderProgressStore();
    await store.save(
      '连续跨章',
      const ReaderProgress(
        spineIndex: 0,
        pageIndex: 17,
        contentRevision: '预取回归',
      ),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: '连续跨章',
      contentRevision: '预取回归',
    );
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      session.dispose();
      source.close();
      await source.preparationsStopped;
    });
    await session.open(
      overrides: const ReaderOverrides(
        fontSize: 18,
        lineHeight: 1.6,
        paragraphSpacing: 10,
      ),
      contentWidth: 366.6666666666667,
      contentHeight: 773.1694444444443,
      contentTopInset: 56.075,
      contentSideInsets: (left: 8.8, right: 8.53333333333336),
    );
    expect(session.chapterPageCount, 20);
    expect(session.page!.pageIndex, 17);
    var prefetchFinished = false;
    final pending = [
      session.prefetchTurnChapter(true).then((page) {
        prefetchFinished = true;
        return page;
      }),
    ];
    await started.future;

    for (var pageIndex = 18; pageIndex <= 19; pageIndex++) {
      final turn = await session.preparePageTurn(true);
      expect(session.commitPageTurn(turn!), isTrue);
      expect(
        (session.page!.spineIndex, session.page!.pageIndex),
        (0, pageIndex),
      );
      pending.add(session.prefetchTurnChapter(true));
      await Future<void>.delayed(Duration.zero);
      expect(prefetchFinished, isFalse, reason: '相同方向翻页不能提前取消邻章准备');
      expect(preparedSpines, [0, 1]);
      expect(source.chapterLayoutCount, 1);
    }

    final crossing = session.preparePageTurn(true);
    release.complete();
    final turn = await crossing;
    await Future.wait(pending);
    expect(preparedSpines, [0, 1]);
    expect(source.chapterLayoutCount, 2, reason: '本章与邻章各构块一次');
    expect(session.commitPageTurn(turn!), isTrue);
    expect((session.page!.spineIndex, session.page!.pageIndex), (1, 0));
    expect(session.readingCfi, isNotNull);
    await session.flushProgress();
  });
}
