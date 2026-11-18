part of 'library_store.dart';

class _LibrarySweepPaths {
  _LibrarySweepPaths(this.booksDirectory);

  final Directory booksDirectory;
  final files = <String>{};
  final deferredBookIds = <String>{};
  final _digests = <String, String>{};

  Future<void> resolveReferences(AppDatabase db, List<BookRow> books) async {
    for (final book in books) {
      final source = await _resolve(
        book.sourcePath,
        book.uuid,
        revision: book.contentRevision,
      );
      final cover = await _resolve(book.coverPath, book.uuid);
      if (source.present || cover.present) {
        await (db.update(db.books)..whereSamePrimaryKey(book)).write(
          BooksCompanion(sourcePath: source, coverPath: cover),
        );
      }
    }
    final owners = {for (final book in books) book.id: book.uuid};
    await _collectEditPaths(db, owners);
  }

  Future<void> _collectEditPaths(
    AppDatabase db,
    Map<int, String> owners,
  ) async {
    for (final draft in await db.select(db.editDrafts).get()) {
      final owner = owners[draft.bookId];
      final source = await _resolve(
        draft.sourcePath,
        owner,
        revision: draft.baseRevision,
      );
      final directory = await _resolve(
        draft.directory,
        owner,
        draftDirectory: true,
      );
      if (source.present || directory.present) {
        await (db.update(db.editDrafts)..whereSamePrimaryKey(draft)).write(
          EditDraftsCompanion(sourcePath: source, directory: directory),
        );
      }
    }
    for (final version in await db.select(db.editVersions).get()) {
      final source = await _resolve(
        version.sourcePath,
        owners[version.bookId],
        revision: version.revision,
      );
      if (source.present) {
        await (db.update(db.editVersions)..whereSamePrimaryKey(version)).write(
          EditVersionsCompanion(sourcePath: source),
        );
      }
    }
  }

  Future<Value<String>> _resolve(
    String? stored,
    String? owner, {
    String? revision,
    bool draftDirectory = false,
  }) async {
    final local = _localPath(stored);
    if (local != null) {
      final file = File(draftDirectory ? p.join(local, 'draft.json') : local);
      files.add(file.path);
      if (await file.exists()) {
        if (p.equals(stored!, local)) return const Value.absent();
        if (revision == null) return Value(local);
        final digest = _digests[local] ??= await hashImportFile(local);
        if (digest == revision) return Value(local);
      }
    }
    if (revision != null || draftDirectory) {
      if (owner != null) deferredBookIds.add(owner);
      if (local != null) {
        final relative = p.relative(local, from: booksDirectory.path);
        deferredBookIds.add(p.split(relative).first);
      }
    }
    return const Value.absent();
  }

  String? _localPath(String? stored) {
    if (stored == null || !p.isAbsolute(stored)) return null;
    final path = p.normalize(stored);
    if (p.isWithin(booksDirectory.path, path)) return path;
    final parts = p.split(path);
    final books = parts.lastIndexOf('books');
    if (books < 0 || books + 1 == parts.length) return null;
    return p.joinAll([booksDirectory.path, ...parts.skip(books + 1)]);
  }
}
