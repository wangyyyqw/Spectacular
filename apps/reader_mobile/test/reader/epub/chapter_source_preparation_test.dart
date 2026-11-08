import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/css_chapter_book.dart';
import '../../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实章节共享准备，取消单个等待者不影响另一请求', () async {
    final source = await openCssChapter(body: '<p>共享原文准备</p>');
    addTearDown(source.close);
    final cancelled = source.scheduleChapter(0);
    final survivor = source.scheduleChapter(0);
    cancelled.cancel();
    await expectLater(cancelled.result, throwsA(isA<ChapterLoadCancelled>()));
    expect(await survivor.result, isNotEmpty);
    expect(source.chapterLayoutCount, 1);
    expect(source.anchorPreparationCount, 1);
  });

  test('准备期间改变字号只允许最新请求提交', () async {
    final source = await openCssChapter(body: '<p>字号取消准备</p>');
    addTearDown(source.close);
    final stale = source.scheduleChapter(0);
    await source.applyOverrides(const ReaderOverrides(fontSize: 24));
    final latest = source.scheduleChapter(0);
    await expectLater(stale.result, throwsA(isA<ChapterLoadCancelled>()));
    final pages = await latest.result;
    expect(pages, isNotEmpty);
    expect(pages.first.slices.first.block.style!.fontSize, 24);
    expect(source.chapterLayoutCount, 1);
  });

  test('关闭准备中的章节源及时取消且不再提交，越界保留空章语义', () async {
    final source = await openCssChapter(body: '<p>关闭原文准备</p>');
    addTearDown(source.close);
    expect(await source.loadChapter(-1), isEmpty);
    expect(await source.loadChapter(source.chapterCount), isEmpty);
    final pending = source.scheduleChapter(0);
    source.close();
    await expectLater(pending.result, throwsA(isA<ChapterLoadCancelled>()));
    await source.preparationsStopped;
    await expectLater(
      source.scheduleChapter(0).result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(source.chapterLayoutCount, 0);
  });

  test('正式源后台计页写满结构缓存后重载当前章仍命中', () async {
    final source = await EpubChapterSource.open(
      buildMultiChapterEpub(
        chapters: [for (var i = 0; i < 6; i++) '第 ${i + 1} 章正文' * 40],
      ),
      contentWidth: 300,
      contentHeight: 500,
      verifyCrc: false,
    );
    addTearDown(source.close);

    final current = await source.loadChapter(3);
    source.setCurrentReadingChapter(3);
    final preparations = source.anchorPreparationCount;
    expect(source.chapterLayoutCount, 1);

    final handles = [
      for (final spine in [0, 1, 2, 4, 5])
        source.scheduleChapter(
          spine,
          priority: ChapterLayoutPriority.pageCount,
        ),
    ];
    for (final handle in handles) {
      unawaited(
        handle.result.then((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (source.anchorPreparationCount < preparations + handles.length &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(source.anchorPreparationCount, preparations + handles.length);
    final layouts = source.chapterLayoutCount;
    for (final handle in handles) {
      handle.cancel();
    }

    final reopened = await source.loadChapter(3);
    expect(identical(reopened, current), isTrue);
    expect(source.chapterLayoutCount, layouts);
    expect(
      source.anchorPreparationCount,
      preparations + handles.length,
      reason: '后台计页不应挤出当前阅读章结构',
    );
  });
}
