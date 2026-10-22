import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_mobile/storage/prototype_db.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P0-16 drift 建库、读写与 v1→v2 迁移', (tester) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'p0_16_drift.sqlite'));
    if (file.existsSync()) {
      file.deleteSync();
    }

    // 手工构造 v1 库：只有 id/title，user_version=1。
    final raw = sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 1');
    raw.execute(
      'CREATE TABLE books (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'title TEXT NOT NULL)',
    );
    raw.execute("INSERT INTO books (title) VALUES ('旧书')");
    raw.close();

    final db = PrototypeDb(NativeDatabase(file));
    addTearDown(db.close);

    final migrated = await db.select(db.books).get();
    final columns = await db.customSelect('PRAGMA table_info(books)').get();
    final columnNames = columns
        .map((row) => row.data['name'])
        .whereType<String>()
        .toList();

    await db
        .into(db.books)
        .insert(BooksCompanion.insert(title: '新书', author: const Value('作者')));
    final all = await db.select(db.books).get();

    // 全新内存库：验证 onCreate 路径。
    final fresh = PrototypeDb(NativeDatabase.memory());
    addTearDown(fresh.close);
    await fresh
        .into(fresh.books)
        .insert(BooksCompanion.insert(title: '内存书', author: const Value('甲')));
    final freshRows = await fresh.select(fresh.books).get();

    // ignore: avoid_print
    print(
      'P0-16 platform=${defaultTargetPlatform.name} '
      'migrated_rows=${migrated.length} all_rows=${all.length} '
      'columns=$columnNames fresh_rows=${freshRows.length}',
    );

    expect(migrated, hasLength(1));
    expect(migrated.first.title, '旧书');
    expect(migrated.first.author, null);
    expect(columnNames, contains('author'));
    expect(all, hasLength(2));
    expect(freshRows, hasLength(1));
  });
}
