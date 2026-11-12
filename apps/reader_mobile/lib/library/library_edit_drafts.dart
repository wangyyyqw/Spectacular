part of 'library_store.dart';

extension LibraryEditDraftOperations on LibraryStore {
  Future<T> _editQueue<T>(Future<T> Function() operation) {
    if (_isMemory) throw const LibraryImportException('当前模式不支持书籍编辑');
    final previous = LibraryStore._databaseImportQueues[_db!];
    final result = previous == null
        ? operation()
        : previous.then((_) => operation());
    _importQueue = result.then<void>((_) {}, onError: (Object _) {});
    LibraryStore._databaseImportQueues[_db] = _importQueue;
    return result;
  }

  Future<BookRow> _editableBook(String id, [String? expectedRevision]) async {
    final book = await _bookRowOfUuid(id);
    if (book == null || book.deletedAt != null || book.sourcePath == null) {
      throw const LibraryImportException('书籍不存在，无法编辑');
    }
    if (expectedRevision != null && book.contentRevision != expectedRevision) {
      throw const LibraryImportException(
        '书籍版本已变化，草稿尚未覆盖当前版本',
        errorCode: 'E_STALE_REVISION',
      );
    }
    return book;
  }

  Future<BookEditDraft?> loadEditDraft(
    String bookId, {
    bool allowStale = false,
  }) => _editQueue(() async {
    final book = await _editableBook(bookId);
    final row = await (_db!.select(
      _db.editDrafts,
    )..where((table) => table.bookId.equals(book.id))).getSingleOrNull();
    if (row == null) return null;
    if (!allowStale) await _editableBook(bookId, row.baseRevision);
    final directory = Directory(row.directory);
    final json = jsonDecode(
      await File(p.join(row.directory, 'draft.json')).readAsString(),
    );
    return BookEditDraft(
      baseRevision: row.baseRevision,
      sourceFile: File(row.sourcePath),
      data: json as Map<String, dynamic>,
      directory: directory,
    );
  });

  Future<void> persistEditDraft(
    String bookId,
    String expectedRevision,
    EditDraftSerializer serialize,
  ) => _editQueue(() async {
    final book = await _editableBook(bookId, expectedRevision);
    final root = await _bookDirectory(book.uuid);
    final directory = await Directory(p.join(root.path, 'drafts'))
        .create(recursive: true);
    final stage = await directory.createTemp('snapshot-');
    var committed = false;
    try {
      await _writeEditDraft(stage, serialize);
      await _commitEditDraft(book, stage);
      committed = true;
      await _sweepEditDrafts([book]);
    } finally {
      if (!committed && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  });

  Future<void> _writeEditDraft(
    Directory stage,
    EditDraftSerializer serialize,
  ) async {
    final data = serialize((path, bytes) {
      final name = '${sha256.convert(bytes)}.blob';
      File(p.join(stage.path, name)).writeAsBytesSync(bytes, flush: true);
      return name;
    });
    await File(p.join(stage.path, 'draft.json'))
        .writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> _commitEditDraft(BookRow book, Directory stage) =>
      _db!.transaction(() async {
        await _editableBook(book.uuid, book.contentRevision);
        await _db
            .into(_db.editDrafts)
            .insertOnConflictUpdate(
              EditDraftsCompanion.insert(
                bookId: Value(book.id),
                baseRevision: book.contentRevision,
                sourcePath: book.sourcePath!,
                directory: stage.path,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      });

  Future<void> discardEditDraft(String bookId) => _editQueue(() async {
    final book = await _editableBook(bookId);
    await (_db!.delete(
      _db.editDrafts,
    )..where((t) => t.bookId.equals(book.id))).go();
    await _sweepEditDrafts([book]);
  });

  Future<List<BookEditVersion>> editVersions(String bookId) =>
      _editQueue(() async {
        final book = await _editableBook(bookId);
        final rows = await (_db!.select(
          _db.editVersions,
        )..where((table) => table.bookId.equals(book.id))).get();
        return [
          for (final row in rows)
            BookEditVersion(
              kind: row.kind,
              sourceFile: File(row.sourcePath),
              revision: row.revision,
              summary: row.summary,
              createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
            ),
        ];
      });

  Future<Set<String>> _protectedEditFiles() async {
    final rows = await _db!.select(_db.editVersions).get();
    final drafts = await _db.select(_db.editDrafts).get();
    return {
      for (final row in rows) p.normalize(row.sourcePath),
      for (final row in drafts) p.normalize(row.sourcePath),
      for (final row in drafts) p.join(row.directory, 'draft.json'),
    };
  }

  Future<void> _sweepEditDrafts(List<BookRow> books) async {
    final rows = await _db!.select(_db.editDrafts).get();
    final active = {for (final row in rows) p.normalize(row.directory)};
    for (final book in books) {
      final directory = _safeBookDirectory(await _root(), book.uuid);
      if (directory == null) continue;
      final drafts = Directory(p.join(directory.path, 'drafts'));
      if (!await drafts.exists()) continue;
      await for (final child in drafts.list(followLinks: false)) {
        if (child is! Directory || active.contains(p.normalize(child.path))) {
          continue;
        }
        try {
          await child.delete(recursive: true);
        } on FileSystemException {
          /* 占用快照由下次扫描回收。 */
        }
      }
    }
  }
}
