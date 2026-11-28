import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sample = String.fromEnvironment('OCR_SAMPLE_EPUB');
  test('用户样书：选区保存耗时与保存后的正文、阅读位置', () async {
    final output = Directory('dist/paragraph-save');
    await output.create(recursive: true);
    final temporary = await output.createTemp('library-');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await temporary.delete(recursive: true);
    });
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => temporary,
    );
    final book = await library.importFile(sample);
    final source = await EpubChapterSource.openFile(
      File(book.filePath),
      contentVersion: book.contentRevision,
    );
    addTearDown(source.close);
    const spine = 14;
    final chapter = await source.loadAnchorChapter(spine);
    final start = chapter.blockStarts.last;
    final cfi = chapter.cfiAt(start)!;
    final progress = DriftProgressStore(db);
    final unbind = await progress.bindSource(
      book.id,
      source,
      book.contentRevision!,
    );
    addTearDown(unbind);
    await progress.save(
      book.id,
      ReaderProgress(
        spineIndex: spine,
        pageIndex: 0,
        cfi: cfi,
        contentRevision: book.contentRevision,
      ),
    );
    final reader = ReaderSession(
      source: source,
      store: progress,
      bookId: book.id,
      contentRevision: book.contentRevision,
    );
    addTearDown(reader.dispose);
    await reader.open();
    await reader.flushProgress();
    final repository = BookEditRepository(library);
    final watch = Stopwatch()..start();
    final edit = await repository.openParagraph(
      book.id,
      book.contentRevision!,
      File(book.filePath),
      spine,
      cfi,
      chapter.cfiAt(start + 2)!,
      recognizedText: '测试',
      sourceText: chapter.text.substring(start, start + 2),
    );
    addTearDown(edit.session.close);
    final openMs = watch.elapsedMilliseconds;
    watch.reset();
    final stages = <String>[];
    await repository.saveParagraph(
      book.id,
      edit,
      '保存性能验证',
      onStage: (stage) {
        stages.add('${watch.elapsedMilliseconds}ms $stage');
      },
    );
    final saveMs = watch.elapsedMilliseconds;
    final saved = (await library.bookById(book.id))!;
    watch.reset();
    await reader.refreshContent(
      revision: saved.contentRevision!,
      prepare: () async {
        await source.acceptSavedChapter(
          File(saved.filePath),
          contentVersion: saved.contentRevision!,
        );
        unbind();
        final release = await progress.bindSource(
          book.id,
          source,
          saved.contentRevision!,
        );
        addTearDown(release);
      },
    );
    final refreshMs = watch.elapsedMilliseconds;
    expect(reader.source, same(source));
    expect(reader.contentRevision, saved.contentRevision);
    expect(reader.page!.spineIndex, spine);
    expect(source.chapterPlainText(spine), contains('保存性能验证'));
    await reader.flushProgress();
    final next = await EpubChapterSource.openFile(File(saved.filePath));
    addTearDown(next.close);
    expect((await next.loadAnchorChapter(spine)).text, contains('保存性能验证'));
    expect((await progress.load(book.id))!.spineIndex, spine);
    final report =
        '编辑打开：${openMs}ms；保存：${saveMs}ms；原页刷新：${refreshMs}ms\n${stages.join('\n')}';
    debugPrint(report);
    await File('${output.path}/timings.txt').writeAsString(report);
    await File('${output.path}/events.log')
        .writeAsString(await ReaderLog.instance.exportText());
  }, skip: sample.isEmpty ? '需用 OCR_SAMPLE_EPUB 指定用户本地样书' : false);
}
