import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_ui/reader_session.dart';

import '../../reader_core/test/audit/audit_epub_fixture.dart';

Future<EpubChapterSource> _source() => const EpubFormatOpener().openBytes(
  auditZip({
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
    'next.xhtml': auditChapter('next', '下一章正文。' * 100),
  }),
  options: const ReaderOpenOptions(
    contentWidth: 366.6666666666667,
    contentHeight: 773.1694444444443,
  ),
);

Future<ReaderSession> _session(EpubChapterSource source, int pageIndex) async {
  final store = MemoryReaderProgressStore();
  await store.save(
    '两阶段预取',
    ReaderProgress(spineIndex: 0, pageIndex: pageIndex),
  );
  final session = ReaderSession(source: source, store: store, bookId: '两阶段预取');
  addTearDown(() async {
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
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式 EPUB 到 80% 只预解析，四页储备不足时才排版并复用原文', () async {
    final source = await _source();
    final decorated = <int>[];
    source.setChapterPreparer((spine) async => decorated.add(spine));
    final session = await _session(source, 14);
    final original = session.page;
    expect(session.chapterPageCount, 20);
    await session.preparseNextChapter();
    expect(source.anchorPreparationCount, 1, reason: '15/20 未达到 80%');
    expect(source.chapterLayoutCount, 1);
    expect(session.page, same(original));

    expect(await session.next(), isTrue);
    final atThreshold = session.page;
    final progress = session.progress;
    await session.preparseNextChapter();
    expect(source.anchorPreparationCount, 2);
    expect(source.chapterLayoutCount, 1, reason: '16/20 只解析原文');
    expect(decorated, [0]);
    expect(session.page, same(atThreshold));
    expect(session.progress, progress);
    expect(await session.prefetchTurnChapter(true), isNull);
    expect(source.chapterLayoutCount, 1, reason: '前方四页已就绪，不排版邻章');

    expect(await session.next(), isTrue);
    final first = await session.prefetchTurnChapter(true);
    expect(first!.spineIndex, 1);
    expect(source.anchorPreparationCount, 2, reason: '排版复用预解析结构');
    expect(source.chapterLayoutCount, 2);
    expect(decorated, [0, 1]);
    while (session.page!.pageIndex < 19) {
      expect(await session.next(), isTrue);
    }
    final crossing = await session.preparePageTurn(true);
    expect(crossing!.target.content, same(first));
    expect(session.commitPageTurn(crossing), isTrue);
    expect(source.chapterLayoutCount, 2);
    expect(session.readingCfi, source.anchorChapter(1).cfiAt(0));
    await session.flushProgress();
  });

  test('取消尚未完成的预解析后可以重试，不回写正文或错误', () async {
    final source = await _source();
    final session = await _session(source, 15);
    final original = session.page;
    final pending = session.preparseNextChapter();
    session.cancelPendingLoads();
    await pending;
    expect(session.page, same(original));
    expect(session.error, isNull);
    expect(source.chapterLayoutCount, 1);
    await session.preparseNextChapter();
    expect(source.anchorPreparationCount, 2);
    expect(source.chapterLayoutCount, 1);
    await session.flushProgress();
  });

  // 夹具与连续交互保持线性，避免拆分后掩盖任务重启；清理阶段始终释放准备门。
  test('正式 EPUB 在 18→19→20 连续翻页后接管尚未完成的邻章预取', () async {
    final source = await _source();
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
