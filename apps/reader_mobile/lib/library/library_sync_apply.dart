part of 'library_store.dart';

Future<void> _applySyncRecords(
  _LibrarySyncRepository repository,
  String collection,
  List<SyncRecord> records,
  SyncState state,
  SyncAssets assets,
  SyncProfile profile,
) async {
  for (final record in records.where((record) => record.type == 'book')) {
    await _applySyncBook(repository, record, assets);
  }
  final order = [
    'shelf_groups',
    'book_tags',
    'decoration_rule_groups',
    ..._syncTables.where(
      (table) => !const {
        'shelf_groups',
        'book_tags',
        'decoration_rule_groups',
      }.contains(table),
    ),
  ];
  for (final type in [
    'activity',
    ...order,
    'setting',
    'book_color',
    'decoration_selection',
  ]) {
    for (final record in records.where((record) => record.type == type)) {
      await _applySyncRow(repository, record, assets, state);
    }
  }
  if (records.any(
    (record) => record.type == 'list' || record.type == 'list_member',
  )) {
    await _applySyncLists(repository, state);
  }
  if (records.any((record) => record.type == 'decoration_style')) {
    await repository.library.setSetting(
      'decoration.styles',
      jsonEncode({
        for (final record in state.heads.values)
          if (record.type == 'decoration_style' && !record.deleted)
            record.id: await assets.resolve(record.data),
      }),
    );
  }
  await repository.saveIdentities();
  final snapshot = await repository.snapshot(profile, assets);
  for (final record in records) {
    final local = snapshot[record.key];
    state.baselines[record.key] = local?.digest ?? record.digest;
  }
  if (repository.busy) throw StateError('阅读器已打开，本轮远端提交已回滚');
  await repository.save(collection, state);
}

Future<BookRow?> _findSyncBook(
  _LibrarySyncRepository repository,
  String id,
  Map<String, dynamic> data,
) async {
  final local = repository.localId('book', id);
  if (local != null) {
    return (repository.db.select(
      repository.db.books,
    )..where((table) => table.id.equals(int.parse(local)))).getSingleOrNull();
  }
  for (final uuid in [data['uuid'], ...?data['aliases'] as List?]) {
    if (uuid is! String) continue;
    final row = await repository.library._bookRowOfUuid(uuid);
    if (row != null) return row;
  }
  return null;
}

Future<void> _applySyncBook(
  _LibrarySyncRepository repository,
  SyncRecord record,
  SyncAssets assets,
) async {
  var book = await _findSyncBook(repository, record.id, record.data);
  if (!record.deleted) {
    book = await _restoreSyncContent(repository, record, book, assets);
  }
  await _writeSyncBookMetadata(repository, record, book, assets);
}

Future<BookRow> _restoreSyncContent(
  _LibrarySyncRepository repository,
  SyncRecord record,
  BookRow? book,
  SyncAssets assets,
) async {
  final ref = record.data['source_path'];
  if (ref is! Map || ref['\$file'] != record.data['content_revision']) {
    throw const FormatException('EPUB 对象与图书版本不一致');
  }
  final path = await assets.resolve(ref) as String;
  if (book == null) {
    final imported = await repository.library._import(
      _ImportPayload.file(path),
    );
    return (await repository.library._bookRowOfUuid(imported.id))!;
  }
  if (book.contentRevision != record.data['content_revision']) {
    return _replaceSyncBook(repository, book, path);
  }
  if (book.sourcePath == null || !await File(book.sourcePath!).exists()) {
    await _restoreSyncFile(repository, book, path);
  }
  return book;
}

Future<void> _restoreSyncFile(
  _LibrarySyncRepository repository,
  BookRow book,
  String path,
) async {
  final fallback = p.join(
    (await repository.library._bookDirectory(book.uuid)).path,
    'source.epub',
  );
  final pathRoot = p.join((await repository.directory()).path, 'books');
  final original = book.sourcePath;
  if (original != null &&
      !p.isWithin(p.normalize(pathRoot), p.normalize(original))) {
    throw StateError('不能覆盖非本应用持有的文件');
  }
  final file = File(original ?? fallback);
  await file.parent.create(recursive: true);
  await File(path).copy(file.path);
  await repository.db.customStatement(
    'UPDATE books SET source_path = ? WHERE id = ?',
    [file.path, book.id],
  );
}

Future<void> _writeSyncBookMetadata(
  _LibrarySyncRepository repository,
  SyncRecord record,
  BookRow? book,
  SyncAssets assets,
) async {
  final data = record.data;
  final values = {
    for (final key in [
      'epub_identifier',
      'content_revision',
      'title',
      'author',
      'description',
      'language',
      'created_at',
    ])
      key: data[key],
  };
  values['deleted_at'] = record.deleted
      ? data['deleted_at'] ?? DateTime.now().millisecondsSinceEpoch
      : null;
  // 并发删除仅隐藏本地最新内容，不能把保留文件的摘要改回旧版。
  if (record.deleted && book != null) values.remove('content_revision');
  if (data['cover_path'] != null) {
    values['cover_path'] = await assets.resolve(data['cover_path']);
  }
  if (book == null) {
    values.addAll({
      'uuid': data['uuid'],
      'content_dir': 'books/${data['uuid']}',
    });
    final id = await _insertSyncRow(repository, 'books', values);
    book = (await (repository.db.select(
      repository.db.books,
    )..where((table) => table.id.equals(id))).getSingle());
  } else {
    await _updateSyncRow(repository, 'books', values, {'id': book.id});
  }
  repository.identities.putIfAbsent('book', () => {})['${book.id}'] = record.id;
  repository.bookFiles['${book.id}'] = {
    'source_path': data['source_path'],
    'cover_path': data['cover_path'],
  };
}

Future<BookRow> _replaceSyncBook(
  _LibrarySyncRepository repository,
  BookRow book,
  String path,
) async {
  final bytes = (await readRevisionFileSnapshot(path)).bytes;
  final analysis = await analyzeImport(bytes);
  final parsed = await openAnalyzed(bytes, analysis);
  if (parsed.document == null) throw const FormatException('远端 EPUB 解析失败');
  try {
    final updated = await repository.library._replaceRevision(
      book,
      bytes,
      parsed,
      analysis: analysis,
    );
    return (await repository.library._bookRowOfUuid(updated.id))!;
  } finally {
    parsed.document!.archive.close();
  }
}

Future<int> _localSyncBook(
  _LibrarySyncRepository repository,
  String wire,
) async {
  final id = repository.localId('book', wire);
  if (id == null) throw const FormatException('阅读记录的图书尚未恢复');
  return int.parse(id);
}

Future<void> _applySyncRow(
  _LibrarySyncRepository repository,
  SyncRecord record,
  SyncAssets assets,
  SyncState state,
) async {
  if (record.type == 'decoration_selection') {
    final id = await _localSyncBook(repository, record.id);
    await repository.library.setSetting(
      'decoration.globalSelection.$id',
      record.deleted || record.data['ids'] == null
          ? ''
          : jsonEncode(record.data['ids']),
    );
    return;
  }
  if (record.type == 'book_color') {
    return _applySyncColor(repository, record);
  }
  if (record.type == 'setting') {
    return _applySyncSetting(repository, record, assets);
  }
  final data = Map<String, dynamic>.from(
    await assets.resolve(record.data) as Map,
  );
  await _mapSyncBooks(repository, data);
  if (record.type == 'activity') {
    if (!record.deleted) {
      await _updateSyncRow(
        repository,
        'books',
        {'last_read_at': data['last_read_at']},
        {'id': data['book_id']},
      );
    }
    return;
  }
  await _mapSyncRowIdentity(repository, record, data);
  await _rehomeSyncRule(repository, record, data, state);
  final info = await repository.db
      .customSelect('PRAGMA table_info(${record.type})')
      .get();
  _validateSyncColumns(data, info);
  final primary = {
    for (final row in info)
      if (row.read<int>('pk') != 0 &&
          data.containsKey(row.read<String>('name')))
        row.read<String>('name'): data[row.read<String>('name')],
  };
  if (record.deleted || _removedSyncRelation(record, state)) {
    if (primary.isNotEmpty) {
      await repository.db.customStatement(
        'DELETE FROM ${record.type} WHERE ${primary.keys.map((key) => '$key = ?').join(' AND ')}',
        primary.values.toList(),
      );
    }
  } else {
    await _rebaseSyncAnchor(repository, record.type, data, assets);
    await _upsertSyncData(repository, record, data, primary);
  }
}

Future<void> _applySyncColor(
  _LibrarySyncRepository repository,
  SyncRecord record,
) async {
  final id = await _localSyncBook(repository, record.id);
  final book = await (repository.db.select(
    repository.db.books,
  )..where((row) => row.id.equals(id))).getSingle();
  final raw = await repository.library.getSetting('stats.book_colors');
  final colors = raw == null
      ? <String, dynamic>{}
      : jsonDecode(raw) as Map<String, dynamic>;
  if (record.deleted) {
    colors.remove(book.uuid);
  } else {
    colors[book.uuid] = {'p': book.coverPath, 'c': record.data['color']};
  }
  await repository.library.setSetting('stats.book_colors', jsonEncode(colors));
}

Future<void> _applySyncSetting(
  _LibrarySyncRepository repository,
  SyncRecord record,
  SyncAssets assets,
) async {
  if (!_portableSyncSetting(record.id)) throw const FormatException('不允许同步此设置');
  if (record.deleted) {
    await repository.db.customStatement('DELETE FROM settings WHERE key = ?', [
      record.id,
    ]);
  } else {
    final value = await assets.resolve(record.data['value']);
    await repository.library.setSetting(
      record.id,
      value is String ? value : jsonEncode(value),
    );
  }
}

Future<void> _mapSyncBooks(
  _LibrarySyncRepository repository,
  Map<String, dynamic> data,
) async {
  if (data['book_id'] != null) {
    data['book_id'] = await _localSyncBook(
      repository,
      data['book_id'] as String,
    );
  }
  if (data['book_uuid'] == null) return;
  final id = await _localSyncBook(repository, data['book_uuid'] as String);
  data['book_uuid'] = (await (repository.db.select(
    repository.db.books,
  )..where((table) => table.id.equals(id))).getSingle()).uuid;
}

void _validateSyncColumns(Map<String, dynamic> data, List<QueryRow> info) {
  final columns = {for (final row in info) row.read<String>('name')};
  if (data.keys.any((key) => !columns.contains(key))) {
    throw const FormatException('同步记录包含未知数据库字段');
  }
  for (final column in info) {
    final name = column.read<String>('name');
    final value = data[name];
    if (value == null || name.endsWith('_json')) continue;
    final type = column.read<String>('type');
    if ((type == 'TEXT' && value is! String) ||
        (type == 'INTEGER' && value is! int && value is! bool) ||
        (type == 'REAL' && value is! num)) {
      throw const FormatException('同步字段类型与数据库不一致');
    }
  }
}

bool _removedSyncRelation(SyncRecord record, SyncState state) {
  final parent = switch (record.type) {
    'shelf_group_books' => 'shelf_groups/${record.data['group_id']}',
    'book_tag_links' => 'book_tags/${record.data['tag_id']}',
    _ => null,
  };
  return parent != null && state.heads[parent]?.deleted == true;
}

/// 离线规则仍指向已删除分组时沿用本地的“移入默认组”行为，不丢弃规则正文。
Future<void> _rehomeSyncRule(
  _LibrarySyncRepository repository,
  SyncRecord record,
  Map<String, dynamic> data,
  SyncState state,
) async {
  if (record.type != 'decoration_rules' || record.deleted) return;
  final parent =
      state.heads['decoration_rule_groups/${record.data['group_id']}'];
  if (parent?.deleted != true) return;
  final wire = parent!.data['book_id'] as String?;
  final id = wire == null ? null : await _localSyncBook(repository, wire);
  final local = id == null ? 'dec-default-global' : 'dec-default-book-$id';
  final time = DateTime.now().millisecondsSinceEpoch;
  await repository.db.customStatement(
    'INSERT OR IGNORE INTO decoration_rule_groups '
    '(id, book_id, name, is_default, sort_order, created_at, updated_at) VALUES (?,?,?,1,?,?,?)',
    [local, id, '默认组', 0x7fffffff, time, time],
  );
  repository.identities.putIfAbsent('rule_group', () => {})[local] =
      wire == null ? 'dec-default-global' : 'dec-default-book-$wire';
  data['group_id'] = local;
}

Future<void> _mapSyncRowIdentity(
  _LibrarySyncRepository repository,
  SyncRecord record,
  Map<String, dynamic> data,
) async {
  if (record.type == 'book_tags') {
    final local = repository.localId('tag', record.id) ?? record.id;
    data['id'] = local;
    repository.identities.putIfAbsent('tag', () => {})[local] = record.id;
  } else if (record.type == 'decoration_rule_groups') {
    final fallback = data['is_default'] == 1
        ? (data['book_id'] == null
              ? 'dec-default-global'
              : 'dec-default-book-${data['book_id']}')
        : record.id;
    final local = repository.localId('rule_group', record.id) ?? fallback;
    data['id'] = local;
    repository.identities.putIfAbsent('rule_group', () => {})[local] =
        record.id;
  } else if (record.type == 'decoration_rules') {
    data['group_id'] =
        repository.localId('rule_group', data['group_id'] as String) ??
        data['group_id'];
  } else if (record.type == 'book_tag_links') {
    data['tag_id'] =
        repository.localId('tag', data['tag_id'] as String) ?? data['tag_id'];
  } else if (record.type == 'reading_sessions') {
    final local = repository.localId('session', record.id);
    if (local != null) data['id'] = int.parse(local);
  } else if (record.type == 'decorations') {
    final local = repository.localId('decoration', record.id) ?? record.id;
    data['id'] = local;
    repository.identities.putIfAbsent('decoration', () => {})[local] =
        record.id;
  } else if (record.type == 'user_fonts') {
    final row = await (repository.db.select(
      repository.db.userFonts,
    )..where((table) => table.family.equals(record.id))).getSingleOrNull();
    if (row != null) data['id'] = row.id;
  }
}

Future<void> _upsertSyncData(
  _LibrarySyncRepository repository,
  SyncRecord record,
  Map<String, dynamic> data,
  Map<String, dynamic> primary,
) async {
  if (primary.isNotEmpty) {
    final found = await repository.db
        .customSelect(
          'SELECT 1 FROM ${record.type} WHERE ${primary.keys.map((key) => '$key = ?').join(' AND ')}',
          variables: primary.values.map((value) => Variable(value)).toList(),
        )
        .get();
    if (found.isNotEmpty) {
      await _updateSyncRow(repository, record.type, data, primary);
      return;
    }
  }
  final id = await _insertSyncRow(repository, record.type, data);
  if (record.type == 'reading_sessions') {
    repository.identities.putIfAbsent('session', () => {})['$id'] = record.id;
  }
}

Future<int> _insertSyncRow(
  _LibrarySyncRepository repository,
  String table,
  Map<String, dynamic> data,
) async {
  await repository.db.customStatement(
    'INSERT INTO $table (${data.keys.join(',')}) '
    'VALUES (${data.keys.map((_) => '?').join(',')})',
    _syncSqlValues(data.values),
  );
  return (await repository.db
          .customSelect('SELECT last_insert_rowid() AS id')
          .getSingle())
      .read<int>('id');
}

Future<void> _updateSyncRow(
  _LibrarySyncRepository repository,
  String table,
  Map<String, dynamic> data,
  Map<String, dynamic> primary,
) => repository.db.customStatement(
  'UPDATE $table SET ${data.keys.map((key) => '$key = ?').join(',')} '
  'WHERE ${primary.keys.map((key) => '$key = ?').join(' AND ')}',
  [..._syncSqlValues(data.values), ...primary.values],
);

List<Object?> _syncSqlValues(Iterable<Object?> values) => [
  for (final value in values)
    value is Map || value is List
        ? jsonEncode(value)
        : value is bool
        ? (value ? 1 : 0)
        : value,
];

Future<void> _rebaseSyncAnchor(
  _LibrarySyncRepository repository,
  String table,
  Map<String, dynamic> data,
  SyncAssets assets,
) async {
  final raw = data['anchor_json'];
  if (raw == null || data['book_id'] == null) return;
  final record = AnchorRecord.decode(raw is String ? raw : jsonEncode(raw));
  if (record == null) throw const FormatException('同步内容锚点无效');
  final book = await (repository.db.select(
    repository.db.books,
  )..where((row) => row.id.equals(data['book_id'] as int))).getSingle();
  if (record.effective.revision == book.contentRevision) return;
  final oldFile = File(p.join(assets.cache.path, record.effective.revision));
  final newFile = book.sourcePath == null ? null : File(book.sourcePath!);
  final AnchorRecord migrated;
  if (newFile == null || !await newFile.exists()) {
    migrated = AnchorRecord(
      original: record.original,
      status: 'pending',
      reason: '图书已移除，内容位置保留',
    );
  } else {
    final old = await oldFile.exists()
        ? await buildRevisionAnchorBook(
            await oldFile.readAsBytes(),
            revision: record.effective.revision,
          )
        : null;
    final current = await buildRevisionAnchorBook(
      await newFile.readAsBytes(),
      revision: book.contentRevision,
    );
    migrated = RevisionRelocator.relocate(
      oldBook: old ?? AnchorBook(revision: 'missing', chapters: []),
      newBook: current,
      record: record,
      progress: table == 'reading_progress',
    );
  }
  data['anchor_json'] = migrated.toJson();
  if (!migrated.isResolved) return;
  if (table == 'reading_progress') {
    data['locator_cfi'] = migrated.effective.start.cfi;
  } else {
    data['start_cfi'] = migrated.effective.start.cfi;
    data['end_cfi'] =
        migrated.effective.end?.cfi ?? migrated.effective.start.cfi;
  }
}

Future<void> _applySyncLists(
  _LibrarySyncRepository repository,
  SyncState state,
) async {
  final lists = <Map<String, dynamic>>[];
  for (final record in state.heads.values.where(
    (item) => item.type == 'list' && !item.deleted,
  )) {
    final members =
        state.heads.values
            .where(
              (item) =>
                  item.type == 'list_member' &&
                  !item.deleted &&
                  item.data['list'] == record.id,
            )
            .toList()
          ..sort((a, b) {
            final order = (a.data['order'] as int).compareTo(
              b.data['order'] as int,
            );
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    final ids = <String>[];
    for (final member in members) {
      final local = repository.localId('book', member.data['book'] as String);
      if (local == null) continue;
      final book = await (repository.db.select(
        repository.db.books,
      )..where((row) => row.id.equals(int.parse(local)))).getSingle();
      ids.add(book.uuid);
    }
    lists.add({...record.data, 'bookIds': ids});
  }
  await repository.library.setSetting(
    BookListStore.settingKey,
    jsonEncode(lists),
  );
}
