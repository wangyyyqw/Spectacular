import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'prototype_db.g.dart';

/// 最小书籍表：v2 在 v1 基础上增加 [author]。
class Books extends Table {
  /// 主键。
  IntColumn get id => integer().autoIncrement()();

  /// 书名。
  TextColumn get title => text()();

  /// 作者，v2 新增，允许为空。
  TextColumn get author => text().nullable()();
}

/// P0-16 的 drift 原型库：验证建库、读写与 v1→v2 迁移。
@DriftDatabase(tables: [Books])
class PrototypeDb extends _$PrototypeDb {
  /// 创建原型库。
  PrototypeDb(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(books, books.author);
      }
    },
  );

  /// 打开 App 文档目录下的默认库文件。
  static Future<PrototypeDb> openDefault() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'prototype.sqlite'));
    return PrototypeDb(NativeDatabase(file));
  }
}
