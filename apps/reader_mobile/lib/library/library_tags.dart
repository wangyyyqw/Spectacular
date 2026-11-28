part of 'library_store.dart';

typedef _PreparedTagRemoval = ({
  BookRow book,
  List<BookTag> tags,
  _PreparedBookMetadata output,
});

extension LibraryTagOperations on LibraryStore {
  /// 全局删除标签：所有本地书先完成写包，再一次提交书籍版本和关联。
  Future<void> deleteTag(String tagId) =>
      _enqueueOperation(() => _deleteTag(tagId));

  Future<void> _deleteTag(String tagId) async {
    if (_isMemory) {
      var changed = _memoryTags.remove(tagId) != null;
      for (final tags in _memoryBookTags.values) {
        changed = tags.remove(tagId) || changed;
      }
      if (changed) _notify();
      return;
    }
    final books = await _taggedLocalBooks(tagId);
    for (final book in books) {
      await _requireMetadataEditable(book);
    }
    final prepared = <_PreparedTagRemoval>[];
    var committed = false;
    try {
      for (final book in books) {
        final tags = (await bookTags(book.uuid))
            .where((tag) => tag.id != tagId)
            .toList();
        prepared.add((
          book: book,
          tags: tags,
          output: await _prepareBookMetadata(book, tags: tags),
        ));
      }
      final changed = await _commitTagRemovals(tagId, prepared);
      committed = true;
      if (changed) _notify();
    } finally {
      if (!committed) {
        for (final item in prepared) {
          await _discardUncommittedEditStage(item.output.directory);
        }
      }
    }
  }

  Future<List<BookRow>> _taggedLocalBooks(String tagId) async {
    final db = _db!;
    final links = await (db.select(
      db.bookTagLinks,
    )..where((row) => row.tagId.equals(tagId))).get();
    if (links.isEmpty) return [];
    final books =
        await (db.select(db.books)
              ..where(
                (row) =>
                    row.uuid.isIn(links.map((link) => link.bookUuid)) &
                    row.deletedAt.isNull() &
                    row.sourcePath.isNotNull(),
              )
              ..orderBy([(row) => OrderingTerm(expression: row.id)]))
            .get();
    // 清理本机文件仍保留源路径；没有可用文件的书只清关联，不下载或恢复。
    return [
      for (final book in books)
        if (await File(book.sourcePath!).exists()) book,
    ];
  }

  Future<bool> _commitTagRemovals(
    String tagId,
    List<_PreparedTagRemoval> prepared,
  ) => _db!.transaction(() async {
    // 较早暂存的书在等待其他书时也可能被外部修改，切换前统一复核。
    for (final item in prepared) {
      await _requireMetadataEditable(item.book);
      await _verifyImportSnapshot(
        File(item.book.sourcePath!),
        item.book.contentRevision,
      );
    }
    for (final item in prepared) {
      await _commitPreparedBookMetadata(
        item.book,
        item.output,
        null,
        item.tags,
      );
    }
    final db = _db;
    final removedLinks = await (db.delete(
      db.bookTagLinks,
    )..where((row) => row.tagId.equals(tagId))).go();
    final removedTags = await (db.delete(
      db.bookTags,
    )..where((row) => row.id.equals(tagId))).go();
    if (prepared.isNotEmpty && _syncReaders != 0) {
      throw const LibraryImportException('请先退出阅读或编辑，再修改图书资料');
    }
    return removedLinks > 0 || removedTags > 0;
  });
}
