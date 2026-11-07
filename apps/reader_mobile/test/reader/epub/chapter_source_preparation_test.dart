import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/css_chapter_book.dart';

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
    await expectLater(
      source.scheduleChapter(0).result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(source.chapterLayoutCount, 0);
  });
}
