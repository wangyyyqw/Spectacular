part of 'library_store.dart';

Future<Map<String, SyncEntity>> _collectSnapshot(
  _LibrarySyncRepository repository,
  SyncProfile profile,
  SyncAssets assets,
) async {
  final raw = await repository.db.transaction(() async {
    await repository.readIdentities();
    return {
      for (final table in [
        'books',
        'book_id_aliases',
        'settings',
        ..._syncTables,
      ])
        table: await repository.rows(table),
    };
  });
  final result = <String, SyncEntity>{};
  final books = <Object, String>{};
  final uuids = <Object, String>{};
  for (final book in raw['books']!) {
    final aliases = raw['book_id_aliases']!
        .where((row) => row['book_id'] == book['id'])
        .map((row) => row['alias_id'] as String)
        .toList();
    final id = repository.identify(
      'book',
      book['id'] as int,
      syncDigest(aliases.firstOrNull ?? book['uuid']),
    );
    books[book['id'] as int] = id;
    uuids[book['uuid'] as String] = id;
    for (final alias in aliases) {
      uuids[alias] = id;
    }
    result['book/$id'] = await _snapshotBook(
      repository,
      assets,
      book,
      id,
      aliases,
    );
    if (book['last_read_at'] != null) {
      result['activity/$id'] = SyncEntity('activity/$id', {
        'book_id': id,
        'last_read_at': book['last_read_at'],
      });
    }
  }
  for (final tag in raw['book_tags']!) {
    repository.identify('tag', tag['id'] as String, syncDigest(tag['name']));
  }
  for (final group in raw['decoration_rule_groups']!) {
    final fallback = group['is_default'] == 1
        ? (group['book_id'] == null
              ? 'dec-default-global'
              : 'dec-default-book-${books[group['book_id']]}')
        : group['id'] as String;
    repository.identify('rule_group', group['id'] as String, fallback);
  }
  for (final table in _syncTables) {
    if (table == 'user_fonts' && !profile.resources) continue;
    for (final row in raw[table]!) {
      final entity = await _snapshotRow(repository, assets, table, row, {
        ...books,
        ...uuids,
      });
      result[entity.key] = entity;
    }
  }
  await _snapshotSettings(
    result,
    raw['settings']!,
    {...uuids, ...books},
    profile,
    assets,
  );
  await repository.saveIdentities();
  return {
    for (final entity in result.values)
      entity.key: SyncEntity(
        entity.key,
        assets.withRemotePaths(entity.data, syncRecordDirectory(entity, result))
            as Map<String, dynamic>,
        deleted: entity.deleted,
      ),
  };
}

Future<SyncEntity> _snapshotBook(
  _LibrarySyncRepository repository,
  SyncAssets assets,
  Map<String, dynamic> row,
  String id,
  List<String> aliases,
) async {
  final data = {
    for (final key in [
      'uuid',
      'epub_identifier',
      'content_revision',
      'title',
      'author',
      'description',
      'language',
      'created_at',
      'deleted_at',
    ])
      key: row[key],
  };
  data['aliases'] = aliases;
  final refs = repository.bookFiles.putIfAbsent('${row['id']}', () => {});
  for (final key in ['source_path', 'cover_path']) {
    final path = row[key] as String?;
    if (path != null && await File(path).exists()) {
      refs[key] = await assets.stage(
        path,
        digest: key == 'source_path' ? row['content_revision'] as String : null,
        folder: key == 'source_path' ? 'books' : 'covers',
      );
    }
    data[key] = refs[key];
  }
  return SyncEntity('book/$id', data, deleted: row['deleted_at'] != null);
}

Future<SyncEntity> _snapshotRow(
  _LibrarySyncRepository repository,
  SyncAssets assets,
  String table,
  Map<String, dynamic> raw,
  Map<Object, String> identifiers,
) async {
  final data = Map<String, dynamic>.of(raw);
  if (data['book_id'] != null) data['book_id'] = identifiers[data['book_id']];
  if (data['book_uuid'] != null) {
    data['book_uuid'] = identifiers[data['book_uuid']];
  }
  if (table == 'book_tags') {
    data['id'] = repository.identities['tag']![data['id']];
  }
  if (table == 'decoration_rule_groups') {
    data['id'] = repository.identities['rule_group']![data['id']];
  }
  if (table == 'decoration_rules') {
    data['group_id'] = repository.identities['rule_group']![data['group_id']];
  }
  if (table == 'book_tag_links') {
    data['tag_id'] = repository.identities['tag']![data['tag_id']];
  }
  if (table == 'reading_progress') {
    data.remove('page_index');
    final anchor = data['anchor_json'];
    if (anchor is String) {
      data['anchor_json'] = (jsonDecode(anchor) as Map<String, dynamic>)
        ..remove('layoutFingerprint')
        ..remove('scrollOffset');
    }
  }
  for (final key in data.keys.where((key) => key.endsWith('_json')).toList()) {
    if (data[key] is String) data[key] = jsonDecode(data[key] as String);
  }
  final String id;
  if (table == 'reading_sessions') {
    id = repository.identify(
      'session',
      data.remove('id') as int,
      '${await repository.device()}-${newSyncId()}',
    );
  } else if (table == 'user_fonts') {
    data.remove('id');
    id = data['family'] as String;
  } else if (table == 'decorations') {
    id = repository.identify(
      'decoration',
      data['id'] as String,
      syncDigest([data['book_id'], data['start_cfi'], data['end_cfi']]),
    );
    data['id'] = id;
  } else {
    id = '${data['id'] ?? data['book_id'] ?? data['book_uuid']}';
  }
  final key = table == 'book_tag_links' ? '$id:${data['tag_id']}' : id;
  return SyncEntity(
    '$table/$key',
    Map<String, dynamic>.from(await assets.capture(data) as Map),
  );
}

Future<void> _snapshotSettings(
  Map<String, SyncEntity> result,
  List<Map<String, dynamic>> settings,
  Map<Object, String> books,
  SyncProfile profile,
  SyncAssets assets,
) async {
  for (final row in settings) {
    final key = row['key'] as String;
    if (key == 'decoration.styles') {
      for (final entry in (jsonDecode(
        row['value'] as String,
      ) as Map<String, dynamic>).entries) {
        result['decoration_style/${entry.key}'] = SyncEntity(
          'decoration_style/${entry.key}',
          Map<String, dynamic>.from(await assets.capture(entry.value) as Map),
        );
      }
    } else if (key.startsWith('decoration.globalSelection.')) {
      final book = books[int.tryParse(key.split('.').last)];
      if (book == null) continue;
      final value = row['value'] as String;
      result['decoration_selection/$book'] = SyncEntity(
        'decoration_selection/$book',
        {'ids': value.isEmpty ? null : jsonDecode(value)},
      );
    } else if (key == 'stats.book_colors') {
      final colors = jsonDecode(row['value'] as String) as Map<String, dynamic>;
      for (final entry in colors.entries) {
        final book = books[entry.key];
        if (book == null) continue;
        final color = (entry.value as Map)['c'];
        if (color is! int) continue;
        result['book_color/$book'] = SyncEntity('book_color/$book', {
          'color': color,
        });
      }
    } else if (key == BookListStore.settingKey) {
      for (final list in jsonDecode(row['value'] as String) as List) {
        final item = Map<String, dynamic>.from(list as Map);
        final ids = (item.remove('bookIds') as List)
            .where(books.containsKey)
            .toList();
        final id = item['id'] as String;
        result['list/$id'] = SyncEntity('list/$id', item);
        for (var index = 0; index < ids.length; index++) {
          final book = books[ids[index]]!;
          final member = 'list_member/$id:$book';
          result[member] = SyncEntity(member, {
            'list': id,
            'book': book,
            'order': index,
          });
        }
      }
    } else if (_portableSyncSetting(key) &&
        syncKeyEnabled('setting/$key', profile)) {
      result['setting/$key'] = SyncEntity('setting/$key', {
        'value': await assets.capture(
          decodeSyncSetting(row['value'] as String),
          fileValue: key == 'reader.backgroundId',
        ),
      });
    }
  }
}
