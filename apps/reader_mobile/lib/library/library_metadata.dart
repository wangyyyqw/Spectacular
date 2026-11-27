part of 'library_store.dart';

typedef _BookMetadata = ({String title, String author, String description});
typedef _BookCover = ({Uint8List bytes, String extension});

/// 详情修改不改变正文资源和 spine，因此只更新文件版本，不重新迁移文本位置。
extension LibraryMetadataOperations on LibraryStore {
  // 写包、提交和失败清理共享一个边界；仅由书库串行队列内的资料入口调用。
  Future<BookEntry> _writeBookMetadata(
    BookRow old, {
    _BookMetadata? metadata,
    _BookCover? cover,
    List<BookTag>? tags,
  }) async {
    await _requireMetadataEditable(old);
    final root = await _bookDirectory(old.uuid);
    final versions = await Directory(p.join(root.path, 'versions'))
        .create(recursive: true);
    final stage = await versions.createTemp('metadata-');
    EpubEditSession? session;
    var committed = false;
    try {
      session = await EpubEditSession.open(File(old.sourcePath!));
      if (session.baseDigest != old.contentRevision) {
        throw const LibraryImportException('书籍文件已变化，请重新导入后修改资料');
      }
      _editBookMetadata(session, metadata, cover, tags);
      final file = File(p.join(stage.path, 'source.epub'));
      await EpubWriter.write(session, file);
      final revision = await hashImportFile(file.path);
      final coverFile = cover == null
          ? null
          : await File(p.join(stage.path, 'cover.${cover.extension}'))
                .writeAsBytes(cover.bytes, flush: true);
      await _db!.transaction(() async {
        await _requireMetadataEditable(old);
        await _verifyImportSnapshot(file, revision);
        await _commitBookMetadata(
          old,
          (file: file, revision: revision, coverPath: coverFile?.path),
          metadata,
          tags,
        );
        if (_syncReaders != 0) {
          throw const LibraryImportException('请先退出阅读或编辑，再修改图书资料');
        }
      });
      committed = true;
      if (cover != null) await _deleteRetiredSource(old.coverPath);
      _notify();
      return _entryFromRow((await _bookRowOfUuid(old.uuid))!);
    } on EpubEditException catch (error) {
      throw LibraryImportException('图书资料未保存：${error.message}');
    } finally {
      session?.close();
      if (!committed) await _discardUncommittedEditStage(stage);
    }
  }

  Future<void> _requireMetadataEditable(BookRow old) async {
    if (_syncReaders != 0) {
      throw const LibraryImportException('请先退出阅读或编辑，再修改图书资料');
    }
    await _editableBook(old.uuid, old.contentRevision);
    await _requireNoEditDraft(old.id);
  }

  void _editBookMetadata(
    EpubEditSession session,
    _BookMetadata? metadata,
    _BookCover? cover,
    List<BookTag>? tags,
  ) {
    final editor = PackageEditor(session);
    if (metadata != null) {
      editor.setMetadata({
        'title': metadata.title,
        'description': metadata.description,
      });
      final authors = OpfParser.parse(session.readText(session.opfPath))
          .meta
          .author;
      if (authors != metadata.author) {
        editor.setMetadataValues('creator', [
          if (metadata.author.isNotEmpty) metadata.author,
        ]);
      }
    }
    if (tags != null) {
      editor.setMetadataValues('subject', [for (final tag in tags) tag.name]);
    }
    if (cover != null) {
      final path = p.posix.join(
        p.posix.dirname(session.opfPath),
        'images',
        'cover-${newSyncId()}.${cover.extension}',
      );
      editor.addResource(
        path,
        cover.bytes,
        'image/${cover.extension == 'jpg' ? 'jpeg' : cover.extension}',
      );
      editor.setCover(path);
    }
  }

  Future<void> _commitBookMetadata(
    BookRow old,
    ({File file, String revision, String? coverPath}) output,
    _BookMetadata? metadata,
    List<BookTag>? tags,
  ) async {
    final db = _db!;
    await (db.update(db.books)..where((row) => row.id.equals(old.id))).write(
      BooksCompanion(
        sourcePath: Value(output.file.path),
        contentDir: Value(
          p.relative(output.file.parent.path, from: (await _root()).path),
        ),
        contentRevision: Value(output.revision),
        title: metadata == null ? const Value.absent() : Value(metadata.title),
        author: metadata == null
            ? const Value.absent()
            : Value(metadata.author),
        description: metadata == null
            ? const Value.absent()
            : Value(metadata.description),
        coverPath: output.coverPath == null
            ? const Value.absent()
            : Value(output.coverPath),
      ),
    );
    if (tags != null) {
      final ids = tags.map((tag) => tag.id).toSet();
      await (db.delete(db.bookTagLinks)..where(
            (row) => row.bookUuid.equals(old.uuid) & row.tagId.isNotIn(ids),
          ))
          .go();
      await db.batch(
        (batch) => batch.insertAll(db.bookTagLinks, [
          for (final tag in tags)
            BookTagLinksCompanion.insert(
              bookUuid: old.uuid,
              tagId: tag.id,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
        ], mode: InsertMode.insertOrIgnore),
      );
    }
    await _retargetMetadataAnchors(old, output.revision);
  }

  Future<void> _retargetMetadataAnchors(BookRow old, String revision) async {
    for (final table in ['reading_progress', 'annotations', 'decorations']) {
      final rows = await _db!
          .customSelect(
            'SELECT rowid AS metadata_row_id, anchor_json FROM $table WHERE book_id = ?',
            variables: [Variable(old.id)],
          )
          .get();
      for (final row in rows) {
        final source = row.readNullable<String>('anchor_json');
        final anchor = AnchorRecord.decode(source);
        if (anchor == null ||
            anchor.effective.revision != old.contentRevision) {
          continue;
        }
        final data = jsonDecode(source!) as Map<String, dynamic>;
        data['current'] = {...anchor.effective.toJson(), 'revision': revision};
        await _db.customStatement(
          'UPDATE $table SET anchor_json = ? WHERE rowid = ?',
          [jsonEncode(data), row.read<int>('metadata_row_id')],
        );
      }
    }
  }
}
