part of 'library_store.dart';

extension LibrarySynchronization on LibraryStore {
  SyncRepository syncRepository() => _LibrarySyncRepository(this);

  /// 阅读器及其编辑路由关闭、最终进度保存完毕前不应用远端变化。
  void beginSyncRead() => _syncReaders++;
  void endSyncRead() {
    _syncReaders--;
    _notify();
  }

  void setSyncRestore(Future<void> Function(String)? restore) =>
      _syncRestoreBook = restore;
  void setSyncSettingObserver(void Function()? listener) =>
      _syncSettingChanged = listener;

  Future<BookEntry?> bookBySyncId(String id) async {
    if (_isMemory) return bookById(id);
    final row = await resolveBookRow(_db!, id);
    return row == null || row.deletedAt != null ? null : _entryFromRow(row);
  }

  Future<void> ensureSyncBookFile(BookEntry entry) async {
    if (!supportsPersistence || await File(entry.filePath).exists()) return;
    final restore = _syncRestoreBook;
    if (restore == null) throw StateError('本机 EPUB 缺失，请重新导入或配置同步');
    await restore(entry.id);
  }
}

class _LibrarySyncRepository implements SyncRepository {
  _LibrarySyncRepository(this.library);
  final LibraryStore library;
  AppDatabase get db => library._db!;
  final identities = <String, Map<String, String>>{};
  final bookFiles = <String, Map<String, dynamic>>{};

  @override
  bool get available => library.supportsPersistence;
  @override
  bool get busy => library._syncReaders != 0;
  @override
  Stream<void> get changes => db
      .tableUpdates()
      .where((updates) => updates.any((update) => update.table != 'settings'))
      .map((_) {});
  @override
  Future<Directory> directory() => library._root();

  Future<List<Map<String, dynamic>>> rows(String table) async => [
    for (final row
        in await db
            .customSelect(
              table == 'settings'
                  ? "SELECT * FROM settings WHERE key NOT GLOB 'page-cache.*'"
                  : 'SELECT * FROM $table',
            )
            .get())
      Map<String, dynamic>.of(row.data),
  ];

  Future<String> device() async {
    final known = await library.getSetting('sync.device.v1');
    if (known != null && known.isNotEmpty) return known;
    final id = newSyncId();
    await library.setSetting('sync.device.v1', id);
    return id;
  }

  Future<void> readIdentities() async {
    final raw = await library.getSetting('sync.identities.v1');
    identities.clear();
    if (raw != null && raw.isNotEmpty) {
      for (final entry in (jsonDecode(raw) as Map<String, dynamic>).entries) {
        identities[entry.key] = Map<String, String>.from(entry.value as Map);
      }
    }
    final refs = await library.getSetting('sync.bookFiles.v1');
    bookFiles.clear();
    if (refs != null && refs.isNotEmpty) {
      bookFiles.addAll(
        (jsonDecode(refs) as Map<String, dynamic>).map(
          (key, value) =>
              MapEntry(key, Map<String, dynamic>.from(value as Map)),
        ),
      );
    }
  }

  String identify(String type, Object id, String fallback) =>
      identities.putIfAbsent(type, () => {}).putIfAbsent('$id', () => fallback);

  String? localId(String type, String wire) => identities[type]?.entries
      .where((entry) => entry.value == wire)
      .firstOrNull
      ?.key;

  Future<void> saveIdentities() async {
    await library.setSetting('sync.identities.v1', jsonEncode(identities));
    await library.setSetting('sync.bookFiles.v1', jsonEncode(bookFiles));
  }

  @override
  Future<SyncState> load(String collection) async {
    final raw = await library.getSetting('sync.state.$collection');
    return raw == null || raw.isEmpty
        ? SyncState(device: await device())
        : SyncState.decode(raw);
  }

  @override
  Future<void> save(String collection, SyncState state) => db.transaction(
    () => library.setSetting('sync.state.$collection', state.encode()),
  );

  @override
  Future<String?> bookKey(String uuid) async {
    await readIdentities();
    final book = await library._bookRowOfUuid(uuid);
    final id = book == null ? null : identities['book']?['${book.id}'];
    return id == null ? null : 'book/$id';
  }

  @override
  Future<void> clearBookFile(String uuid) =>
      library._enqueueOperation(() async {
        if (busy) throw StateError('请先退出阅读或编辑');
        final book = await library._bookRowOfUuid(uuid);
        if (book == null || book.deletedAt != null) throw StateError('书籍不在书架中');
        final path = book.sourcePath;
        final root = p.join((await directory()).path, 'books');
        if (path == null || !p.isWithin(p.normalize(root), p.normalize(path))) {
          throw StateError('不能清理非本应用持有的 EPUB');
        }
        final file = File(path);
        if (await file.exists()) await file.delete();
        library._notify();
      });

  @override
  Future<Map<String, SyncEntity>> snapshot(
    SyncProfile profile,
    SyncAssets assets,
  ) => _collectSnapshot(this, profile, assets);

  @override
  Future<void> apply(
    String collection,
    List<SyncRecord> records,
    SyncState state,
    SyncAssets assets,
    SyncProfile profile,
  ) => library._enqueueOperation(() async {
    if (busy) throw StateError('阅读或编辑尚未关闭，远端数据保留待接收');
    await readIdentities();
    library._syncTransaction = true;
    try {
      await db.transaction(
        () => _applySyncRecords(
          this,
          collection,
          records,
          state,
          assets,
          profile,
        ),
      );
    } finally {
      library._syncTransaction = false;
    }
    library._notify();
  });
}

const _syncTables = [
  'reading_progress',
  'annotations',
  'decorations',
  'decoration_rule_groups',
  'decoration_rules',
  'book_reviews',
  'reading_sessions',
  'shelf_groups',
  'shelf_group_books',
  'book_tags',
  'book_tag_links',
  'user_fonts',
];

bool _portableSyncSetting(String key) =>
    (key.startsWith('reader.') &&
        !const {
          'reader.tts',
          'reader.inkMode',
          'reader.keepScreenOn',
          'reader.volumeKeyPaging',
          'reader.tapZones',
        }.contains(key)) ||
    const {
      'app.themeMode',
      'app.themePreset',
      'app.fontFamily',
      'bookshelf.sort',
      'bookshelf.showTitles',
      'bookshelf.grid',
    }.contains(key);
