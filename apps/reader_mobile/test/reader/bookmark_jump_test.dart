import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('书签 CFI 跳转：翻章后回到原位，重排后仍能定位（P4-13）', () async {
    final source = await openTestChapterSource(_corpusBook('toc-ncx.epub'));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'bookmark-jump',
    );
    await session.open();

    // 到第 2 章，记下当前页 CFI。
    await session.jumpToChapter(1);
    final cfi = session.currentCfi;
    expect(cfi, isNotNull, reason: '页面块应带 CFI');
    final spine = session.progress!.spineIndex;
    final page = session.progress!.pageIndex;

    // 离开到别的章。
    await session.jumpToChapter(2);
    expect(session.progress!.spineIndex, isNot(spine));

    // 按书签 CFI 跳回。
    expect(await session.jumpToCfi(cfi!), isTrue);
    expect(session.progress!.spineIndex, spine);
    expect(session.progress!.pageIndex, page);

    // 重排（字号变化）后再按书签 CFI 跳转，仍定位到同一章。
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 22, lineHeight: 1.8),
    );
    await session.applyOverrides(
      const ReaderOverrides(fontSize: 22, lineHeight: 1.8),
    );
    await session.jumpToChapter(0);
    expect(await session.jumpToCfi(cfi), isTrue);
    expect(session.progress!.spineIndex, spine, reason: '重排后 CFI 仍可定位');
    session.dispose();
  });

  test('非法 CFI 跳转返回 false 且不动位置', () async {
    final source = await openTestChapterSource(_corpusBook('toc-ncx.epub'));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'bookmark-bad',
    );
    await session.open();
    final before = session.progress;
    expect(await session.jumpToCfi('not-a-cfi'), isFalse);
    expect(session.progress, before);
    session.dispose();
  });
}
