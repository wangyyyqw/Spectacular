part of 'library_store.dart';

/// TXT 先生成并验证 EPUB，再沿用书库的统一提交入口。
extension LibraryTxtOperations on LibraryStore {
  Future<BookEntry> importTxtFile(
    String path, {
    String? fallbackTitle,
    String? encoding,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) => _enqueueOperation(
    () => _importTxt(
      source: File(path),
      fallbackTitle: fallbackTitle ?? p.basename(path),
      encoding: encoding,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
  );

  Future<BookEntry> importTxtBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    String? encoding,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) => _enqueueOperation(
    () => _importTxt(
      bytes: bytes,
      fallbackTitle: fallbackTitle,
      encoding: encoding,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
  );

  Future<BookEntry> _importTxt({
    File? source,
    Uint8List? bytes,
    String? fallbackTitle,
    String? encoding,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _checkImportCancelled(isCancelled);
    final stage = await Directory.systemTemp.createTemp('spectacular-txt-');
    try {
      final input = File(p.join(stage.path, 'input.txt'));
      if (source != null) {
        await source.copy(input.path);
      } else {
        await input.writeAsBytes(bytes!, flush: true);
      }
      final digest = await hashImportFile(input.path);
      _checkImportCancelled(isCancelled);
      final existing = await _existingTxtBook('$txtIdentifierPrefix$digest');
      if (existing != null) {
        onProgress?.call(1);
        return _withImportOutcome(existing, BookImportOutcome.unchanged);
      }
      final rulesJson = await getSetting(txtChapterRulesSettingKey);
      final rules = rulesJson == null
          ? <ChapterRule>[]
          : [
              for (final value in jsonDecode(rulesJson) as List)
                ChapterRule.fromJson(value as Map<String, dynamic>),
            ];
      final converted = await TxtEpubConverter.convertFile(
        input,
        File(p.join(stage.path, 'converted.epub')),
        title: p.basenameWithoutExtension(fallbackTitle ?? '未命名书籍'),
        encoding: encoding,
        options: ChapterDetectionOptions(
          autoRules: rules.where((rule) => rule.autoEnabled).toList(),
        ),
        onProgress: (value) => onProgress?.call(value * 0.65),
        isCancelled: isCancelled,
      );
      _checkImportCancelled(isCancelled);
      if (converted.sourceDigest != digest) throw _changedImportSource;
      return await _import(
        _isMemory
            ? _ImportPayload.bytes(await converted.file.readAsBytes())
            : _ImportPayload.file(converted.filePath),
        onProgress: (value) => onProgress?.call(0.65 + value * 0.35),
        isCancelled: isCancelled,
      );
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<BookEntry?> _existingTxtBook(String identifier) async {
    if (_isMemory) {
      for (final entry in _memoryEntries.values) {
        final opened = await openEpub(_memoryBytes[entry.id]!);
        try {
          if (opened.document?.meta.identifier == identifier) return entry;
        } finally {
          opened.document?.archive.close();
        }
      }
      return null;
    }
    final rows =
        await (_db!.select(_db.books)..where(
              (table) =>
                  table.epubIdentifier.equals(identifier) &
                  table.deletedAt.isNull(),
            ))
            .get();
    for (final row in rows) {
      if (row.sourcePath != null && await File(row.sourcePath!).exists()) {
        return _entryFromRow(row);
      }
    }
    return null;
  }
}
