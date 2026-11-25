import 'dart:io';

import 'package:reader_core/editing.dart';

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
