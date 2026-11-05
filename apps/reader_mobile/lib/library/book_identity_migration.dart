import 'dart:io';

import 'package:drift/drift.dart';
import 'package:reader_core/epub/book_identity.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/opf.dart';

import '../storage/db.dart';

/// 无 OPF 的兼容文档没有原始标识，不能把解析器占位符算进书籍身份。
String originalEpubIdentifier(EpubDocumentImpl document) {
  final source = document.archive.readString(document.opfPath);
  if (source == null) return '';
  try {
    return OpfParser.parse(source).meta.identifier;
  } catch (_) {
    return '';
  }
}

/// 保持数字外键和原文件路径，仅事务更新对外标识及字符串关联。
Future<int> migrateBookIdentities(AppDatabase db) async {
  final rows = await (db.select(
    db.books,
  )..where((table) => table.identityVersion.equals(0))).get();
  var migrated = 0;
  var failed = false;
  for (final row in rows) {
    final path = row.sourcePath;
    // 已删除或原书缺失时无法恢复原始元数据，保留旧 ID 等待原文件恢复。
    if (path == null || !await File(path).exists()) continue;
    try {
      await _migrateBook(db, row, File(path));
      migrated++;
    } catch (_) {
      failed = true;
    }
  }
  if (failed) throw const FormatException('部分书籍标识迁移未完成，已保留原书及关联数据');
  return migrated;
}

Future<void> _migrateBook(AppDatabase db, BookRow row, File source) async {
  final result = await openEpub(await source.readAsBytes(), verifyCrc: false);
  final document = result.document;
  if (document == null) throw const FormatException('原书无法解析');
  final meta = document.meta;
  final identifier = originalEpubIdentifier(document);
  final id = generateBookId(
    title: meta.title,
    author: meta.author,
    identifier: identifier,
  );
  await db.transaction(() async {
    final conflict =
        await (db.select(db.books)..where(
              (table) => table.uuid.equals(id) & table.id.isNotValue(row.id),
            ))
            .getSingleOrNull();
    if (conflict != null) throw const FormatException('书籍标识冲突');
    await rekeyBook(db, row, id, identifier);
  });
}

/// 调用方必须放在事务中，整数主键保持不变。
Future<void> rekeyBook(
  AppDatabase db,
  BookRow row,
  String id,
  String identifier,
) async {
  await (db.update(db.books)..where((table) => table.id.equals(row.id))).write(
    BooksCompanion(
      uuid: Value(id),
      epubIdentifier: Value(identifier),
      identityVersion: const Value(1),
      legacyUuid: Value(row.legacyUuid ?? row.uuid),
    ),
  );
  if (id == row.uuid) return;
  await (db.update(db.shelfGroupBooks)
        ..where((table) => table.bookUuid.equals(row.uuid)))
      .write(ShelfGroupBooksCompanion(bookUuid: Value(id)));
  await (db.update(db.bookTagLinks)
        ..where((table) => table.bookUuid.equals(row.uuid)))
      .write(BookTagLinksCompanion(bookUuid: Value(id)));
}
