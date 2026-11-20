part of 'library_store.dart';

extension LibraryEditingOperations on LibraryStore {
  /// 独立文件先落盘、验证，再以单事务切换；调用方的文件从不被移动或删除。
  Future<BookEntry> commitEditedFile(
    String bookId,
    String expectedRevision,
    File file,
    EpubEditSummary changeSummary, {
    bool preserveTextPositions = false,
    Map<String, String> elementCfiMap = const {},
    bool requireNoDraft = false,
    bool Function()? isCancelled,
  }) => _editQueue(
    () => _commitEditedFile(
      bookId,
      expectedRevision,
      file,
      changeSummary,
      preserveTextPositions: preserveTextPositions,
      elementCfiMap: elementCfiMap,
      requireNoDraft: requireNoDraft,
      isCancelled: isCancelled,
    ),
  );

  Future<BookEntry> restoreEditVersion(
    String bookId,
    String expectedRevision,
    String kind,
  ) => _editQueue(() async {
    final book = await _editableBook(bookId, expectedRevision);
    final version =
        await (_db!.select(_db.editVersions)..where(
              (table) => table.bookId.equals(book.id) & table.kind.equals(kind),
            ))
            .getSingleOrNull();
    if (version == null) throw const LibraryImportException('没有可恢复的版本');
    return _commitEditedFile(
      bookId,
      expectedRevision,
      File(version.sourcePath),
      const EpubEditSummary(changedPaths: {}, cssOnly: false),
    );
  });

  Future<BookEntry> _commitEditedFile(
    String bookId,
    String expectedRevision,
    File input,
    EpubEditSummary summary, {
    bool preserveTextPositions = false,
    Map<String, String> elementCfiMap = const {},
    bool requireNoDraft = false,
    bool Function()? isCancelled,
  }) async {
    _checkImportCancelled(isCancelled);
    final old = await _editableBook(bookId, expectedRevision);
    if (requireNoDraft) await _requireNoEditDraft(old.id);
    final root = await _bookDirectory(old.uuid);
    final versions = await Directory(p.join(root.path, 'versions'))
        .create(recursive: true);
    final stage = await versions.createTemp('edit-');
    var committed = false;
    try {
      final file = await _copyEditFile(
        input,
        File(p.join(stage.path, 'source.epub')),
      );
      committed = await _saveEditedStage(
        old,
        file,
        summary,
        preserveTextPositions: preserveTextPositions,
        elementCfiMap: elementCfiMap,
        requireNoDraft: requireNoDraft,
        isCancelled: isCancelled,
      );
      if (committed) _notify();
      return _withImportOutcome(
        _entryFromRow((await _bookRowOfUuid(old.uuid))!),
        committed ? BookImportOutcome.updated : BookImportOutcome.unchanged,
      );
    } finally {
      if (!committed && await stage.exists()) {
        await _discardUncommittedEditStage(stage);
      }
    }
  }

  Future<bool> _saveEditedStage(
    BookRow old,
    File file,
    EpubEditSummary summary, {
    bool preserveTextPositions = false,
    Map<String, String> elementCfiMap = const {},
    bool requireNoDraft = false,
    bool Function()? isCancelled,
  }) async {
    final analyzed = await _analyzeEdit(old, file, summary);
    _checkImportCancelled(isCancelled);
    if (analyzed.analysis.revision == old.contentRevision) return false;
    final parsed = await openAnalyzedFile(file.path, analyzed.analysis);
    try {
      if (parsed.document == null) {
        throw LibraryImportException(
          '无法保存编辑：${parsed.report.message ?? '文件损坏'}',
          errorCode: parsed.report.errorCode,
        );
      }
      final migration = await _prepareEditedRevision(
        old,
        file,
        revision: analyzed.analysis.revision,
        cssOnly: analyzed.cssOnly,
        preserveTextPositions: preserveTextPositions,
        elementCfiMap: elementCfiMap,
      );
      final commit = await _editCommit(parsed, file, analyzed.analysis);
      await _commitEditedRevision(
        migration,
        commit,
        analyzed.cssOnly,
        summary,
        preserveBookMetadata: preserveTextPositions,
        requireNoDraft: requireNoDraft,
        isCancelled: isCancelled,
      );
      return true;
    } finally {
      parsed.document?.archive.close();
    }
  }

  Future<void> _requireNoEditDraft(int bookId) async {
    final draft = await (_db!.select(
      _db.editDrafts,
    )..where((row) => row.bookId.equals(bookId))).getSingleOrNull();
    if (draft != null) {
      throw const LibraryImportException('本书有未完成的编辑草稿，请先在编辑器保存或放弃草稿');
    }
  }

  Future<void> _discardUncommittedEditStage(Directory stage) async {
    final books = await _db!.select(_db.books).get();
    if (books.any(
      (book) =>
          book.sourcePath != null && p.isWithin(stage.path, book.sourcePath!),
    )) {
      return;
    }
    await stage.delete(recursive: true);
  }

  Future<File> _copyEditFile(File input, File target) async {
    await input.copy(target.path);
    final handle = await target.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    return target;
  }

  Future<({ImportAnalysis analysis, bool cssOnly})> _analyzeEdit(
    BookRow old,
    File file,
    EpubEditSummary summary,
  ) async {
    final spine =
        await (_db!.select(_db.spineItems)
              ..where((t) => t.bookId.equals(old.id))
              ..orderBy([(t) => OrderingTerm.asc(t.spineIndex)]))
            .get();
    return analyzeEditedFile(
      file.path,
      oldPath: old.sourcePath!,
      cssOnly: summary.cssOnly,
      knownCounts: [for (final row in spine) row.charCount ?? 0],
    );
  }

  Future<_RevisionCommit> _editCommit(
    EpubOpenResult parsed,
    File file,
    ImportAnalysis analysis,
  ) async {
    final counts = analysis.charCounts!;
    return _RevisionCommit(
      parsed,
      file,
      ProgressWeights.fromCharCounts(
        counts,
        excluded: parsed.document!.progressExcludedSpineIndexes,
      ),
      counts,
      await _restoreRevisionCover(file.parent, analysis.summary!),
    );
  }

  Future<_RevisionMigration> _prepareEditedRevision(
    BookRow old,
    File file, {
    required String revision,
    required bool cssOnly,
    bool preserveTextPositions = false,
    Map<String, String> elementCfiMap = const {},
  }) async {
    final data = await _editUserData(old.id);
    if (cssOnly ||
        (data.annotations.isEmpty &&
            data.decorations.isEmpty &&
            data.progress == null)) {
      return _RevisionMigration(
        _RevisionBooks(
          old,
          null,
          AnchorBook(revision: revision, chapters: const []),
        ),
        data,
        const {},
        null,
        const {},
      );
    }
    final oldBook = await buildRevisionAnchorBookFile(
      File(old.sourcePath!),
      revision: old.contentRevision,
    );
    final next = await buildRevisionAnchorBookFile(file, revision: revision);
    return _RevisionMigration(
      _RevisionBooks(old, oldBook, next),
      data,
      _migrateRevisionAnnotations(
        data.annotations,
        oldBook,
        next,
        preserveTextPositions: preserveTextPositions,
        elementCfiMap: elementCfiMap,
      ),
      _migrateRevisionProgress(
        data.progress,
        oldBook,
        next,
        preserveTextPositions: preserveTextPositions,
        elementCfiMap: elementCfiMap,
      ),
      _migrateRevisionDecorations(
        data.decorations,
        oldBook,
        next,
        preserveTextPositions: preserveTextPositions,
        elementCfiMap: elementCfiMap,
      ),
    );
  }

  Future<_RevisionUserData> _editUserData(int bookId) async {
    final db = _db!;
    final annotations = await (db.select(
      db.annotations,
    )..where((t) => t.bookId.equals(bookId))).get();
    final decorations = await (db.select(
      db.decorations,
    )..where((t) => t.bookId.equals(bookId))).get();
    final progress = await (db.select(
      db.readingProgress,
    )..where((t) => t.bookId.equals(bookId))).getSingleOrNull();
    return _RevisionUserData(annotations, decorations, progress);
  }

  Future<void> _commitEditedRevision(
    _RevisionMigration migration,
    _RevisionCommit commit,
    bool cssOnly,
    EpubEditSummary summary, {
    bool preserveBookMetadata = false,
    bool requireNoDraft = false,
    bool Function()? isCancelled,
  }) => _db!.transaction(() async {
    _checkImportCancelled(isCancelled);
    if (requireNoDraft) await _requireNoEditDraft(migration.old.id);
    await _verifyRevisionSnapshot(migration);
    await _retainEditHistory(migration.old, summary);
    final document = commit.parsed.document!;
    await _switchRevisionBook(
      migration,
      commit,
      migration.old.uuid,
      originalEpubIdentifier(document),
    );
    await (_db.update(
      _db.books,
    )..where((t) => t.id.equals(migration.old.id))).write(
      BooksCompanion(
        title: preserveBookMetadata
            ? const Value.absent()
            : Value(document.meta.title),
        author: preserveBookMetadata
            ? const Value.absent()
            : Value(document.meta.author),
        language: preserveBookMetadata
            ? const Value.absent()
            : Value(document.meta.language),
        coverPath: preserveBookMetadata
            ? const Value.absent()
            : Value(commit.restoredCover),
      ),
    );
    await _writeRevisionStructure(migration.old.id, commit);
    if (cssOnly) {
      await _writeCssRevisionUserData(migration);
    } else {
      await _writeRevisionUserData(migration, document);
    }
    await (_db.delete(
      _db.editDrafts,
    )..where((t) => t.bookId.equals(migration.old.id))).go();
    _checkImportCancelled(isCancelled);
  });

  Future<void> _retainEditHistory(BookRow old, EpubEditSummary summary) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    EditVersionsCompanion version(String kind) => EditVersionsCompanion.insert(
      bookId: old.id,
      kind: kind,
      revision: old.contentRevision,
      sourcePath: old.sourcePath!,
      summary: kind == 'original'
          ? '首次编辑前原版'
          : '保存前版本（${summary.changedPaths.length} 个资源变更）',
      createdAt: now,
    );
    await _db!
        .into(_db.editVersions)
        .insert(version('original'), mode: InsertMode.insertOrIgnore);
    await _db
        .into(_db.editVersions)
        .insertOnConflictUpdate(version('previous'));
  }

  Future<void> _writeCssRevisionUserData(_RevisionMigration migration) async {
    final db = _db!;
    String? retarget(String? value) => _cssRevisionAnchor(
      value,
      migration.old.contentRevision,
      migration.newBook.revision,
    );
    for (final row in migration.annotations) {
      await (db.update(
        db.annotations,
      )..where((t) => t.id.equals(row.id))).write(
        AnnotationsCompanion(anchorJson: Value(retarget(row.anchorJson))),
      );
    }
    for (final row in migration.decorations) {
      await (db.update(
        db.decorations,
      )..where((t) => t.id.equals(row.id))).write(
        DecorationsCompanion(anchorJson: Value(retarget(row.anchorJson))),
      );
    }
    await _writeCssProgress(migration);
  }

  Future<void> _writeCssProgress(_RevisionMigration migration) async {
    final db = _db!;
    final progress = migration.progress;
    if (progress != null) {
      await (db.update(
        db.readingProgress,
      )..where((t) => t.bookId.equals(progress.bookId))).write(
        ReadingProgressCompanion(
          anchorJson: Value(
            _cssRevisionAnchor(
              progress.anchorJson,
              migration.old.contentRevision,
              migration.newBook.revision,
            ),
          ),
          pageIndex: const Value(0),
        ),
      );
    }
  }

  String? _cssRevisionAnchor(String? source, String before, String after) {
    final record = AnchorRecord.decode(source);
    if (record == null || record.effective.revision != before) return source;
    final data = jsonDecode(source!) as Map<String, dynamic>;
    data['current'] = {...record.effective.toJson(), 'revision': after};
    data.remove('layoutFingerprint');
    data.remove('scrollOffset');
    return jsonEncode(data);
  }
}
