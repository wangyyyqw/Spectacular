part of 'library_store.dart';

void _checkImportCancelled(bool Function()? cancelled) {
  if (cancelled?.call() == true) {
    throw const LibraryImportException('已取消导入', errorCode: 'E_CANCELLED');
  }
}

BookEntry _withImportOutcome(BookEntry book, BookImportOutcome outcome) =>
    BookEntry(
      id: book.id,
      title: book.title,
      author: book.author,
      description: book.description,
      filePath: book.filePath,
      addedAt: book.addedAt,
      lastReadAt: book.lastReadAt,
      spineCount: book.spineCount,
      readabilityLevel: book.readabilityLevel,
      coverPath: book.coverPath,
      contentRevision: book.contentRevision,
      importOutcome: outcome,
    );

/// 覆盖流程与普通导入共用数据库队列；整数外键、原始锚点和用户资料永留。
extension LibraryRevisionOperations on LibraryStore {
  /// 长按详情展示迁移失败原因，阅读数据列表负责手动重新定位。
  Future<List<String>> pendingLocationReasons(String bookId) async {
    if (_isMemory) return [];
    final book = await _bookRowOfUuid(bookId);
    if (book == null) return [];
    final rows = await (_db!.select(
      _db.annotations,
    )..where((table) => table.bookId.equals(book.id))).get();
    final decorations = await (_db.select(
      _db.decorations,
    )..where((table) => table.bookId.equals(book.id))).get();
    return [
      for (final row in rows)
        if (AnchorRecord.decode(row.anchorJson)?.status == 'pending')
          '${row.type == 2 ? '书签' : '标注'}：${AnchorRecord.decode(row.anchorJson)?.reason ?? '需重新定位'}',
      for (final row in decorations)
        if (AnchorRecord.decode(row.anchorJson)?.status == 'pending')
          '装饰：${AnchorRecord.decode(row.anchorJson)?.reason ?? '需重新定位'}',
    ];
  }

  Future<BookEntry> updateBytes(
    String bookId,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) {
    if (_isMemory) {
      throw const LibraryImportException('当前模式不支持强制更新');
    }
    final db = _db!;
    Future<BookEntry> update() async {
      _checkImportCancelled(isCancelled);
      final old = await _bookRowOfUuid(bookId);
      if (old == null || old.deletedAt != null) {
        throw const LibraryImportException('书籍不存在');
      }
      final analysisTrace = readerTraceEnabled
          ? ReaderTrace.instance.start(ReaderTraceName.import, bookId: old.uuid)
          : null;
      final analysis = await analyzeImport(bytes);
      analysisTrace?.stop();
      _checkImportCancelled(isCancelled);
      final openTrace = readerTraceEnabled
          ? ReaderTrace.instance.start(ReaderTraceName.import, bookId: old.uuid)
          : null;
      final parsed = await openAnalyzed(bytes, analysis);
      openTrace?.stop();
      if (parsed.document == null) {
        throw LibraryImportException(
          '无法更新：${parsed.report.message ?? '文件损坏'}',
          errorCode: parsed.report.errorCode,
        );
      }
      try {
        return await _replaceRevision(
          old,
          bytes,
          parsed,
          analysis: analysis,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      } finally {
        parsed.document!.archive.close();
      }
    }

    final previous = LibraryStore._databaseImportQueues[db];
    final result = previous == null ? update() : previous.then((_) => update());
    _importQueue = result.then<void>((_) {}, onError: (Object _) {});
    LibraryStore._databaseImportQueues[db] = _importQueue;
    return result;
  }

  // 暂存、取消与提交后清理共享一个 finally 边界；保留线性协调流程避免误删已提交文件。
  Future<BookEntry> _replaceRevision(
    BookRow old,
    Uint8List bytes,
    EpubOpenResult parsed, {
    required ImportAnalysis analysis,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final document = parsed.document!;
    final identifier = originalEpubIdentifier(document);
    final id = generateBookId(
      title: document.meta.title,
      author: document.meta.author,
      identifier: identifier,
    );
    await _checkRevisionConflict(old.id, id);
    final revision = analysis.revision;
    final oldFile = old.sourcePath == null ? null : File(old.sourcePath!);
    final oldExists = oldFile != null && await oldFile.exists();
    // 已存版本号与新文件一致时，无需再读入并哈希整本旧书。
    if (oldExists && old.contentRevision == revision) {
      return _withImportOutcome(
        _entryFromRow(old),
        BookImportOutcome.unchanged,
      );
    }
    final oldBytes = oldExists ? await oldFile.readAsBytes() : null;
    _checkImportCancelled(isCancelled);
    if (oldBytes != null && sha256.convert(oldBytes).toString() == revision) {
      return _withImportOutcome(
        _entryFromRow(old),
        BookImportOutcome.unchanged,
      );
    }
    final directory = await _bookDirectory(id);
    final stage = Directory(
      p.join(
        directory.path,
        'versions',
        '$revision-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    var committed = false;
    try {
      await stage.create(recursive: true);
      final file = File(p.join(stage.path, 'source.epub'));
      await file.writeAsBytes(bytes, flush: true);
      onProgress?.call(0.5);
      final migration = await _prepareRevision(
        old,
        oldBytes,
        bytes,
        revision: revision,
      );
      _checkImportCancelled(isCancelled);
      final counts = analysis.charCounts!;
      final weights = ProgressWeights.fromCharCounts(
        counts,
        excluded: document.progressExcludedSpineIndexes,
      );
      onProgress?.call(0.85);
      await _commitRevision(
        migration,
        _RevisionCommit(parsed, file, weights, counts),
        isCancelled: isCancelled,
      );
      committed = true;
      // 数据库已指向可读的新文件后才删除旧 EPUB；失败留给启动扫描。
      await _deleteRetiredSource(old.sourcePath);
      onProgress?.call(1);
      _notify();
      return _withImportOutcome(
        _entryFromRow((await _bookRowOfUuid(id))!),
        BookImportOutcome.updated,
      );
    } finally {
      if (!committed && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  }

  Future<void> _checkRevisionConflict(int oldId, String id) async {
    final conflict =
        await (_db!.select(_db.books)..where(
              (table) => table.uuid.equals(id) & table.id.isNotValue(oldId),
            ))
            .getSingleOrNull();
    if (conflict != null) {
      throw const LibraryImportException(
        '新书籍标识已属于另一条书架记录，未更新',
        errorCode: 'E_REVISION_CONFLICT',
      );
    }
  }

  Future<_RevisionMigration> _prepareRevision(
    BookRow old,
    Uint8List? oldBytes,
    Uint8List bytes, {
    required String revision,
  }) async {
    final db = _db!;
    final annotations = await (db.select(
      db.annotations,
    )..where((table) => table.bookId.equals(old.id))).get();
    final decorations = await (db.select(
      db.decorations,
    )..where((table) => table.bookId.equals(old.id))).get();
    final progress = await (db.select(
      db.readingProgress,
    )..where((table) => table.bookId.equals(old.id))).getSingleOrNull();
    if (annotations.isEmpty && decorations.isEmpty && progress == null) {
      return _RevisionMigration(
        _RevisionBooks(
          old,
          null,
          AnchorBook(revision: revision, chapters: const []),
        ),
        _RevisionUserData(annotations, decorations, progress),
        const <String, AnchorRecord>{},
        null,
        const <String, AnchorRecord>{},
      );
    }
    // 有旧文件却无法解析时拒绝更新，不能把异常当作正常的待确认结果。
    final oldBook = oldBytes == null
        ? null
        : await buildRevisionAnchorBook(oldBytes);
    final newBook = await buildRevisionAnchorBook(bytes);
    final migrated = _migrateRevisionAnnotations(annotations, oldBook, newBook);
    final position = await _migrateRevisionProgress(
      progress,
      oldBook,
      newBook,
      oldBytes,
    );
    return _RevisionMigration(
      _RevisionBooks(old, oldBook, newBook),
      _RevisionUserData(annotations, decorations, progress),
      migrated,
      position,
      _migrateRevisionDecorations(decorations, oldBook, newBook),
    );
  }

  Map<String, AnchorRecord> _migrateRevisionAnnotations(
    List<AnnotationRow> annotations,
    AnchorBook? oldBook,
    AnchorBook newBook,
  ) {
    final migrated = <String, AnchorRecord>{};
    for (final annotation in annotations) {
      final record = _historicalAnnotation(annotation, oldBook);
      migrated[annotation.id] = RevisionRelocator.relocate(
        oldBook: oldBook ?? AnchorBook(revision: 'missing', chapters: []),
        newBook: newBook,
        record: record,
      );
    }
    return migrated;
  }

  Map<String, AnchorRecord> _migrateRevisionDecorations(
    List<DecorationRow> decorations,
    AnchorBook? oldBook,
    AnchorBook newBook,
  ) {
    final migrated = <String, AnchorRecord>{};
    for (final row in decorations) {
      migrated[row.id] = RevisionRelocator.relocate(
        oldBook: oldBook ?? AnchorBook(revision: 'missing', chapters: []),
        newBook: newBook,
        record: _historicalDecoration(row, oldBook),
      );
    }
    _resolveDecorationCollisions(decorations, migrated);
    return migrated;
  }

  void _resolveDecorationCollisions(
    List<DecorationRow> rows,
    Map<String, AnchorRecord> records,
  ) {
    while (true) {
      final ranges = <String, String>{};
      final collisions = <String>{};
      for (final row in rows) {
        final record = records[row.id]!;
        final start = record.isResolved
            ? record.effective.start.cfi
            : row.startCfi;
        final end = record.isResolved
            ? record.effective.end?.cfi ?? start
            : row.endCfi;
        final previous = ranges['$start\n$end'];
        if (previous != null) collisions.addAll([row.id, previous]);
        ranges['$start\n$end'] = row.id;
      }
      var changed = false;
      for (final id in collisions) {
        final record = records[id]!;
        if (!record.isResolved) continue;
        records[id] = AnchorRecord(
          original: record.original,
          status: 'pending',
          reason: '多个装饰定位到同一原文区间，需重新定位',
        );
        changed = true;
      }
      if (!changed) return;
    }
  }

  Future<AnchorRecord?> _migrateRevisionProgress(
    ProgressRow? progress,
    AnchorBook? oldBook,
    AnchorBook newBook,
    Uint8List? oldBytes,
  ) async {
    if (progress == null) return null;
    var record = AnchorRecord.decode(progress.anchorJson);
    if (record == null && oldBook != null && oldBytes != null) {
      final cfi = progress.locatorCfi.startsWith('epubcfi(')
          ? progress.locatorCfi
          : await _recoverHistoricalCfi(oldBytes, progress);
      final anchor = cfi == null
          ? null
          : oldBook.capture(
              cfi,
              approximate: !progress.locatorCfi.startsWith('epubcfi('),
            );
      if (anchor != null) record = AnchorRecord(original: anchor);
    }
    record ??= AnchorRecord(
      original: _missingLocation(
        progress.locatorCfi,
        spineIndex: progress.spineIndex ?? 0,
      ),
    );
    return RevisionRelocator.relocate(
      oldBook: oldBook ?? AnchorBook(revision: 'missing', chapters: []),
      newBook: newBook,
      record: record,
      progress: true,
    );
  }

  Future<String?> _recoverHistoricalCfi(
    Uint8List bytes,
    ProgressRow row,
  ) async {
    final source = await EpubChapterSource.open(bytes);
    final memory = MemoryReaderProgressStore();
    await memory.save(
      'historical',
      ReaderProgress(
        spineIndex: row.spineIndex ?? 0,
        pageIndex: row.pageIndex ?? 0,
      ),
    );
    final session = ReaderSession(
      source: source,
      store: memory,
      bookId: 'historical',
    );
    try {
      final settings = await ReaderSettingsStore(this).load();
      final size = _historicalContentSize(settings);
      await session.open(
        overrides: settings.overrides,
        contentWidth: size.width,
        contentHeight: size.height,
        contentTopInset: size.topInset,
      );
      return session.currentCfi;
    } finally {
      session.dispose();
      source.close();
    }
  }

  ({double width, double height, double topInset}) _historicalContentSize(
    ReaderSettings settings,
  ) {
    final view = PlatformDispatcher.instance.views.firstOrNull;
    final ratio = view?.devicePixelRatio ?? 1;
    final width = (view?.physicalSize.width ?? 320) / ratio;
    final height = (view?.physicalSize.height ?? 480) / ratio;
    final margins = settings.margins;
    final padding = margins?.toBodyPadding(
      showFurniture: true,
      headerHeight: PageFurniture.headerHeight,
      footerHeight: PageFurniture.footerHeight,
    );
    final side = padding == null
        ? settings.horizontalPadding * 2
        : padding.horizontal;
    final vertical = padding == null
        ? 32 +
              PageFurniture.reservedHeight +
              ((view?.viewPadding.top ?? 0) + (view?.viewPadding.bottom ?? 0)) /
                  ratio
        : padding.vertical;
    return (
      width: math.max(80, width - side),
      height: math.max(120, height - vertical),
      topInset: padding?.top ?? 16,
    );
  }

  /// 版本校验、文件指向及全部用户位置仍统一在同一事务提交。
  Future<void> _commitRevision(
    _RevisionMigration migration,
    _RevisionCommit commit, {
    bool Function()? isCancelled,
  }) async {
    final document = commit.parsed.document!;
    final identifier = originalEpubIdentifier(document);
    final id = generateBookId(
      title: document.meta.title,
      author: document.meta.author,
      identifier: identifier,
    );
    await _db!.transaction(() async {
      _checkImportCancelled(isCancelled);
      await _verifyRevisionSnapshot(migration);
      await _checkRevisionConflict(migration.old.id, id);
      await _switchRevisionBook(migration, commit, id, identifier);
      await _writeRevisionStructure(migration.old.id, commit);
      await _writeRevisionUserData(migration);
      // 事务内部的异步写入期间仍可取消，提交前最后核对并整体回滚。
      _checkImportCancelled(isCancelled);
    });
  }

  Future<void> _switchRevisionBook(
    _RevisionMigration migration,
    _RevisionCommit commit,
    String id,
    String identifier,
  ) async {
    final db = _db!;
    final old = migration.old;
    await rekeyBook(db, old, id, identifier);
    if (old.uuid != id) {
      await db
          .into(db.bookIdAliases)
          .insertOnConflictUpdate(
            BookIdAliasesCompanion.insert(aliasId: old.uuid, bookId: old.id),
          );
    }
    await (db.update(
      db.books,
    )..where((table) => table.id.equals(old.id))).write(
      BooksCompanion(
        sourcePath: Value(commit.file.path),
        contentDir: Value(
          p.relative(commit.file.parent.path, from: (await _root()).path),
        ),
        contentRevision: Value(migration.newBook.revision),
        spineCount: Value(commit.parsed.document!.spine.length),
        charCount: Value(commit.weights.totalCharacters),
        layoutVersion: Value(old.layoutVersion + 1),
        level: Value(commit.parsed.report.readabilityLevel),
        warnings: Value(jsonEncode(commit.parsed.report.warnings)),
      ),
    );
  }

  Future<void> _writeRevisionStructure(
    int bookId,
    _RevisionCommit commit,
  ) async {
    final db = _db!;
    await (db.delete(
      db.spineItems,
    )..where((table) => table.bookId.equals(bookId))).go();
    await (db.delete(
      db.chapters,
    )..where((table) => table.bookId.equals(bookId))).go();
    await (db.delete(
      db.importReports,
    )..where((table) => table.bookId.equals(bookId))).go();
    final document = commit.parsed.document!;
    await _writeSpineItems(
      bookId,
      document.spine,
      commit.counts,
      commit.weights,
    );
    await _writeRevisionToc(bookId, document);
    await _writeImportReports(bookId, commit.parsed.report);
  }

  Future<void> _verifyRevisionSnapshot(_RevisionMigration migration) async {
    final db = _db!;
    final current = await (db.select(
      db.books,
    )..where((table) => table.id.equals(migration.old.id))).getSingleOrNull();
    final old = migration.old;
    if (current == null ||
        current.uuid != old.uuid ||
        current.deletedAt != null ||
        current.sourcePath != old.sourcePath ||
        current.contentRevision != old.contentRevision ||
        current.layoutVersion != old.layoutVersion) {
      throw const LibraryImportException(
        '书籍版本已变化，请重试更新',
        errorCode: 'E_STALE_REVISION',
      );
    }
    final annotations = await (db.select(
      db.annotations,
    )..where((table) => table.bookId.equals(old.id))).get();
    final decorations = await (db.select(
      db.decorations,
    )..where((table) => table.bookId.equals(old.id))).get();
    final progress = await (db.select(
      db.readingProgress,
    )..where((table) => table.bookId.equals(old.id))).getSingleOrNull();
    if (jsonEncode(annotations.map((row) => row.toJson()).toList()) !=
            jsonEncode(
              migration.annotations.map((row) => row.toJson()).toList(),
            ) ||
        jsonEncode(decorations.map((row) => row.toJson()).toList()) !=
            jsonEncode(
              migration.decorations.map((row) => row.toJson()).toList(),
            ) ||
        jsonEncode(progress?.toJson()) !=
            jsonEncode(migration.progress?.toJson())) {
      throw const LibraryImportException(
        '阅读数据已变化，请重试更新',
        errorCode: 'E_STALE_REVISION',
      );
    }
  }

  Future<void> _writeRevisionToc(int bookId, EpubDocumentImpl document) async {
    var order = 0;
    Future<void> write(List<TocEntry> entries, int depth) async {
      for (final entry in entries) {
        await _db!
            .into(_db.chapters)
            .insert(
              ChaptersCompanion.insert(
                bookId: bookId,
                depth: Value(depth),
                title: entry.title,
                href: document.spine[entry.spineIndex].href,
                cfi: Value(entry.cfi?.serialize()),
                orderIndex: order++,
              ),
            );
        await write(entry.children, depth + 1);
      }
    }

    await write(document.toc, 1);
  }

  Future<void> _writeRevisionUserData(_RevisionMigration migration) async {
    final db = _db!;
    for (final old in migration.annotations) {
      final record = migration.migrated[old.id]!;
      final anchor = record.effective;
      await (db.update(
        db.annotations,
      )..where((table) => table.id.equals(old.id))).write(
        AnnotationsCompanion(
          anchorJson: Value(record.encode()),
          startCfi: record.isResolved
              ? Value(anchor.start.cfi)
              : const Value.absent(),
          endCfi: record.isResolved
              ? Value(anchor.end?.cfi ?? anchor.start.cfi)
              : const Value.absent(),
        ),
      );
    }
    await _writeRevisionDecorations(migration);
    await _writeRevisionProgress(migration);
  }

  Future<void> _writeRevisionDecorations(_RevisionMigration migration) async {
    final db = _db!;
    for (final row in migration.decorations) {
      await (db.update(db.decorations)
            ..where((table) => table.id.equals(row.id)))
          .write(DecorationsCompanion(startCfi: Value('revision:${row.id}')));
    }
    for (final row in migration.decorations) {
      final record = migration.migratedDecorations[row.id]!;
      final anchor = record.effective;
      await (db.update(
        db.decorations,
      )..where((table) => table.id.equals(row.id))).write(
        DecorationsCompanion(
          anchorJson: Value(record.encode()),
          startCfi: Value(record.isResolved ? anchor.start.cfi : row.startCfi),
          endCfi: Value(
            record.isResolved
                ? anchor.end?.cfi ?? anchor.start.cfi
                : row.endCfi,
          ),
        ),
      );
    }
  }

  Future<void> _writeRevisionProgress(_RevisionMigration migration) async {
    final progress = migration.progress;
    final position = migration.position;
    if (progress == null || position == null) return;
    final point = position.effective.start;
    final resetFinished =
        progress.finished &&
        migration.oldBook != null &&
        RevisionRelocator.hasAddedReadableContent(
          migration.oldBook!,
          migration.newBook,
        );
    await (_db!.update(
      _db.readingProgress,
    )..where((table) => table.bookId.equals(progress.bookId))).write(
      ReadingProgressCompanion(
        anchorJson: Value(position.encode()),
        locatorCfi: Value(point.cfi),
        spineIndex: Value(point.spineIndex),
        pageIndex: const Value(0),
        percent: Value(_revisionProgressPercent(migration.newBook, point)),
        finished: Value(resetFinished ? false : progress.finished),
      ),
    );
  }

  double _revisionProgressPercent(AnchorBook book, AnchorPoint point) {
    final readable = book.chapters
        .where((chapter) => chapter.readable)
        .toList();
    final total = readable.fold<int>(
      0,
      (sum, chapter) => sum + chapter.text.length,
    );
    final before = readable
        .where((chapter) => chapter.spineIndex < point.spineIndex)
        .fold<int>(0, (sum, chapter) => sum + chapter.text.length);
    return total == 0 ? 0 : (before + point.charOffset) / total * 100;
  }

  Future<void> _deleteRetiredSource(String? path) async {
    if (path == null) return;
    final rows = await _db!.select(_db.books).get();
    if (rows.any((row) => row.sourcePath == path || row.coverPath == path)) {
      return;
    }
    final root = await _root();
    final normalized = p.normalize(path);
    if (!p.isWithin(p.join(root.path, 'books-v1'), normalized) &&
        !p.isWithin(p.join(root.path, 'books'), normalized)) {
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 当前有效文件已切换，旧文件由启动扫描再次清理。
    }
  }
}

class _RevisionCommit {
  _RevisionCommit(this.parsed, this.file, this.weights, this.counts);
  final EpubOpenResult parsed;
  final File file;
  final ProgressWeights weights;
  final List<int> counts;
}

class _RevisionBooks {
  _RevisionBooks(this.old, this.oldBook, this.newBook);
  final BookRow old;
  final AnchorBook? oldBook;
  final AnchorBook newBook;
}

class _RevisionMigration {
  _RevisionMigration(
    this.books,
    this.userData,
    this.migrated,
    this.position,
    this.migratedDecorations,
  );
  final _RevisionBooks books;
  final _RevisionUserData userData;
  final Map<String, AnchorRecord> migrated;
  final AnchorRecord? position;
  final Map<String, AnchorRecord> migratedDecorations;
  List<AnnotationRow> get annotations => userData.annotations;
  List<DecorationRow> get decorations => userData.decorations;
  ProgressRow? get progress => userData.progress;
  BookRow get old => books.old;
  AnchorBook? get oldBook => books.oldBook;
  AnchorBook get newBook => books.newBook;
}

class _RevisionUserData {
  _RevisionUserData(this.annotations, this.decorations, this.progress);
  final List<AnnotationRow> annotations;
  final List<DecorationRow> decorations;
  final ProgressRow? progress;
}

AnchorRecord _historicalDecoration(DecorationRow row, AnchorBook? book) {
  final saved = AnchorRecord.decode(row.anchorJson);
  if (saved != null) return saved;
  final anchor = book?.capture(row.startCfi, endCfi: row.endCfi);
  if (anchor != null &&
      normalizeAnchorText(anchor.quote) == normalizeAnchorText(row.quote)) {
    return AnchorRecord(original: anchor);
  }
  final original = (book ?? AnchorBook(revision: 'missing', chapters: []))
      .legacyRange(
        startCfi: row.startCfi,
        endCfi: row.endCfi,
        quote: row.quote,
        contextBefore: row.contextBefore ?? '',
        contextAfter: row.contextAfter ?? '',
      );
  return AnchorRecord(
    original: original ?? _missingLocation(row.startCfi, endCfi: row.endCfi),
    status: 'pending',
    reason: '旧文件或内容锚点缺失，需重新定位',
  );
}

AnchorRecord _historicalAnnotation(AnnotationRow row, AnchorBook? book) {
  final saved = AnchorRecord.decode(row.anchorJson);
  if (saved != null) return saved;
  final anchor = book?.capture(
    row.startCfi,
    endCfi: row.type == 2 ? null : row.endCfi,
  );
  if (anchor != null &&
      (row.type == 2 ||
          normalizeAnchorText(anchor.quote) ==
              normalizeAnchorText(row.quote))) {
    return AnchorRecord(original: anchor);
  }
  final legacy = row.type == 2
      ? null
      : AnchorBook(revision: 'missing', chapters: []).legacyRange(
          startCfi: row.startCfi,
          endCfi: row.endCfi,
          quote: row.quote,
          contextBefore: row.contextBefore ?? '',
          contextAfter: row.contextAfter ?? '',
        );
  return AnchorRecord(
    original:
        legacy ??
        _missingLocation(
          row.startCfi,
          endCfi: row.type == 2 ? null : row.endCfi,
        ),
    status: 'pending',
    reason: '旧文件或内容锚点缺失，需重新定位',
  );
}

LocationAnchor _missingLocation(
  String cfi, {
  String? endCfi,
  int spineIndex = 0,
}) {
  AnchorPoint point(String value) => AnchorPoint(
    cfi: value,
    spineIndex: spineIndex,
    href: '',
    title: '',
    chapterFingerprint: '',
    paragraphFingerprint: '',
    charOffset: 0,
    chapterLength: 0,
    quote: '',
    contextBefore: '',
    contextAfter: '',
  );
  return LocationAnchor(
    revision: 'missing',
    start: point(cfi),
    end: endCfi == null ? null : point(endCfi),
    quote: '',
    approximate: true,
  );
}
