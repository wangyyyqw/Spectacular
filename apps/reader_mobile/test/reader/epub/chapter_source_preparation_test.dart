import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/layout/paginator.dart' show PageFootnote;

import '../support/css_chapter_book.dart';
import '../../support/test_epub.dart';

import 'package:reader_core/source/chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同步定位只读取准备结果，冷章节必须先异步准备', () async {
    final source = await openCssChapter(body: '<p>原文定位契约</p>');
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    expect(() => source.anchorChapter(0), throwsStateError);
    expect(source.anchorPreparationCount, 0);

    final chapter = await source.loadAnchorChapter(0);
    expect(source.anchorChapter(0), same(chapter));
    final cfi = chapter.cfiAt(0)!;
    expect(source.readingPercentForCfi(cfi), 0);
    expect(source.anchorPreparationCount, 1);
  });

  test('定位准备其他章节不淘汰实际当前阅读章', () async {
    final source = await EpubChapterSource.open(
      buildMultiChapterEpub(
        chapters: [for (var i = 0; i < 6; i++) '第 $i 章正文' * 40],
      ),
    );
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    await source.loadChapter(3);
    source.setCurrentReadingChapter(3);
    final cfi = source.anchorChapter(3).cfiAt(60);
    for (final spine in [0, 1, 2, 4, 5]) {
      await source.loadAnchorChapter(spine);
    }
    expect(source.anchorChapter(3).cfiAt(60), cfi);
    expect(source.readingPercentForCfi(cfi), isNotNull);
    expect(source.anchorPreparationCount, 6);
  });

  test('视口定位准备尚未完成时百分比返回不可定位且不同步重解析', () async {
    final source = await openCssChapter(body: '<p>宽度变化后的原文位置</p>');
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    final chapter = await source.loadAnchorChapter(0);
    final cfi = chapter.cfiAt(5)!;
    final original = source.readingPercentForCfi(cfi);
    final preparations = source.anchorPreparationCount;
    await source.applyContentSize(width: 260, height: 500);
    expect(source.readingPercentForCfi(cfi), isNull);
    expect(source.anchorPreparationCount, preparations);
    expect(() => source.anchorChapter(0), throwsStateError);
    await source.loadAnchorChapter(0);
    expect(source.readingPercentForCfi(cfi), original);
    expect(source.anchorPreparationCount, preparations + 1);
  });

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

  test('资源缓存淘汰后当前章重排仍消费冻结的注释和原文', () async {
    final source = await EpubChapterSource.open(
      buildMultiChapterEpub(
        rawBody: true,
        chapters: [
          '<p>当前正文<a role="doc-noteref" href="#note">[1]</a></p>'
              '<aside id="note" role="doc-footnote">冻结的注释内容</aside>',
          for (var i = 1; i < 4; i++) '<p>第 $i 章正文</p>',
        ],
      ),
    );
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    await source.loadChapter(0);
    for (var spine = 1; spine < 4; spine++) {
      await source
          .scheduleChapter(spine, priority: ChapterLayoutPriority.prefetch)
          .result;
    }
    final prepared = source.anchorPreparationCount;
    await source.applyOverrides(const ReaderOverrides(fontSize: 20));
    final pages = await source.loadChapter(0);
    expect(source.anchorPreparationCount, prepared);
    expect(
      pages
          .expand((page) => page.slices)
          .expand((slice) => slice.block.footnotes),
      contains(
        isA<PageFootnote>().having((note) => note.text, '注释正文', '冻结的注释内容'),
      ),
    );
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

  test('正式源后台预取写满结构缓存后重载当前章仍命中', () async {
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
          priority: ChapterLayoutPriority.background,
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
      reason: '后台预取不应挤出当前阅读章结构',
    );
  });
}
