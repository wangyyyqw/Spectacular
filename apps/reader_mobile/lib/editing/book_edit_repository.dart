import 'dart:io';

import 'package:reader_core/editing.dart';

import '../diagnostics/reader_log.dart';
import '../library/book_edit_models.dart';
import '../library/library_store.dart';

export '../library/book_edit_models.dart';

/// 编辑工作流只通过书库提交，避免绕过版本校验与阅读数据迁移。
class BookEditRepository {
  BookEditRepository(this.library);

  final LibraryStore library;

  /// 打包前识别已换版或删除的书籍，避免失效基线只显示底层文件错误。
  Future<void> verifyRevision(String bookId, String expectedRevision) async {
    final current = await library.bookById(bookId);
    if (current == null || current.contentRevision != expectedRevision) {
      throw const LibraryImportException(
        '书籍版本已变化，请保留当前输入并重新打开书籍',
        errorCode: 'E_STALE_REVISION',
      );
    }
  }

  Future<BookEditDraft?> openDraft(String bookId) =>
      library.loadEditDraft(bookId);

  /// 过期草稿只能独立导出，不可绕过 commitEditedFile 的版本检查。
  Future<BookEditDraft?> readDraftForRecovery(String bookId) =>
      library.loadEditDraft(bookId, allowStale: true);

  Future<void> saveDraft(
    String bookId,
    String expectedRevision,
    EditDraftSerializer serialize,
  ) => library.persistEditDraft(bookId, expectedRevision, serialize);

  Future<void> discardDraft(String bookId) => library.discardEditDraft(bookId);

  Future<EpubParagraphEdit> openParagraph(
    String bookId,
    String revision,
    File source,
    int spineIndex,
    String startCfi,
    String endCfi,
  ) async {
    await verifyRevision(bookId, revision);
    if (await openDraft(bookId) != null) {
      throw const EpubEditException('本书有未完成的编辑草稿，请先在编辑器保存或放弃草稿');
    }
    final session = await EpubEditSession.open(source);
    try {
      if (session.baseDigest != revision) {
        throw const EpubEditException('书籍文件已变化，请重新打开书籍');
      }
      return EpubParagraphEdit.fromSelection(
        session,
        spineIndex,
        startCfi,
        endCfi,
      );
    } catch (_) {
      session.close();
      rethrow;
    }
  }

  Future<void> saveParagraph(
    String bookId,
    EpubParagraphEdit edit,
    String input,
  ) async {
    final session = edit.session;
    if (input == edit.initialText) return;
    edit.apply(input);
    Directory? temporary;
    try {
      await verifyRevision(bookId, session.baseDigest);
      temporary = await Directory.systemTemp.createTemp('reader-paragraph-');
      final file = File('${temporary.path}/edited.epub');
      await EpubWriter.write(session, file);
      await library.commitEditedFile(
        bookId,
        session.baseDigest,
        file,
        session.summary,
        requireNoDraft: true,
        preserveBookMetadata: true,
      );
    } catch (_) {
      session.undo();
      rethrow;
    } finally {
      try {
        await temporary?.delete(recursive: true);
      } on FileSystemException catch (error, stack) {
        recordAppError(
          'paragraph_edit_cleanup_failed',
          error,
          stackTrace: stack,
        );
      }
    }
  }

  Future<BookEntry> commitEditedFile(
    String bookId,
    String expectedRevision,
    File file,
    EpubEditSummary changeSummary,
  ) => library.commitEditedFile(bookId, expectedRevision, file, changeSummary);

  Future<List<BookEditVersion>> versions(String bookId) =>
      library.editVersions(bookId);

  Future<BookEntry> restoreOriginal(String bookId, String expectedRevision) =>
      library.restoreEditVersion(bookId, expectedRevision, 'original');

  Future<BookEntry> restorePrevious(String bookId, String expectedRevision) =>
      library.restoreEditVersion(bookId, expectedRevision, 'previous');
}
