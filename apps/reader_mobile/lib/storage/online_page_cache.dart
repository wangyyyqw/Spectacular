import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'db.dart';

class OnlinePageCache {
  OnlinePageCache(this._database);

  final AppDatabase? _database;
  final _memory = <String, String>{};
  static const _limit = 256;

  String key(List<Object?> identity) =>
      sha256.convert(utf8.encode(jsonEncode(identity))).toString();

  Future<Object?> read(String key) async {
    final database = _database;
    String? raw;
    if (database == null) {
      raw = _memory[key];
    } else {
      final row = await database
          .customSelect(
            'SELECT value FROM settings WHERE key = ?',
            variables: [Variable.withString('page-cache.$key')],
          )
          .getSingleOrNull();
      raw = row?.read<String>('value');
    }
    return raw == null ? null : jsonDecode(raw);
  }

  Future<void> write(String key, Object? value) async {
    final raw = jsonEncode(value);
    final database = _database;
    if (database == null) {
      _memory.remove(key);
      _memory[key] = raw;
      if (_memory.length > _limit) _memory.remove(_memory.keys.first);
      return;
    }
    await database.transaction(() async {
      await database.customStatement(
        'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
        ['page-cache.$key', raw],
      );
      await database.customStatement(
        "DELETE FROM settings WHERE rowid IN (SELECT rowid FROM settings WHERE key GLOB 'page-cache.*' ORDER BY rowid DESC LIMIT -1 OFFSET $_limit)",
      );
    });
  }

  Future<T> load<T>({
    required List<Object?> identity,
    required Future<T> Function() fetch,
    required Object? Function(T) encode,
    required T Function(Object?) decode,
    required bool Function(Object) unavailable,
    void Function()? onFallback,
  }) async {
    final cacheKey = key(identity);
    final T value;
    try {
      value = await fetch();
    } catch (error, stack) {
      if (!unavailable(error)) rethrow;
      try {
        final saved = await read(cacheKey);
        if (saved is Map && saved.containsKey('data')) {
          final result = decode(saved['data']);
          onFallback?.call();
          return result;
        }
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
    try {
      await write(cacheKey, {'data': encode(value)});
    } catch (_) {}
    return value;
  }
}
