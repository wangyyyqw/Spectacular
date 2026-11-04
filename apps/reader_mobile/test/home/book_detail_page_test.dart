import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

class _FakeCoverLibrary extends LibraryStore {
  _FakeCoverLibrary() : super.memory();

  bool replaced = false;

  @override
  Future<BookEntry> replaceCover(
    String id,
    Uint8List bytes, {
    required String extension,
  }) async {
    replaced = true;
    return (await bookById(id))!;
  }
}

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-detail-page');
    db = AppDatabase(NativeDatabase.memory());
    store = LibraryStore(database: db, directoryProvider: () async => dir);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('详情页可编辑资料、新建标签并切换标签', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '旧书名', identifier: 'detail-edit'),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-title-field')),
      '新书名',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-author-field')),
      '新作者',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-description-field')),
      '新的简介',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-save')));
    await tester.pumpAndSettle();

    late BookEntry updated;
    await tester.runAsync(() async {
      updated = (await store.bookById(entry.id))!;
    });
    expect(updated.title, '新书名');
    expect(updated.author, '新作者');
    expect(updated.description, '新的简介');

    final tagField = find.byKey(
      const ValueKey<String>('book-detail-new-tag-field'),
    );
    await tester.scrollUntilVisible(
      tagField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(tagField, '科幻');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('book-detail-add-tag')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-add-tag')));
    await tester.pumpAndSettle();

    late List<BookTag> tags;
    await tester.runAsync(() async {
      tags = await store.bookTags(entry.id);
    });
    expect(tags.single.name, '科幻');
    final chip = find.byKey(
      ValueKey<String>('book-detail-tag-${tags.single.id}'),
    );
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tags = await store.bookTags(entry.id);
    });
    expect(tags, isEmpty, reason: '再次点击标签应取消关联');
  });

  testWidgets('详情页更换封面调用存储并提示成功', (tester) async {
    final coverStore = _FakeCoverLibrary();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await coverStore.importBytes(
        buildTestEpub(title: '换封面', identifier: 'detail-cover'),
      );
    });
    final png = Uint8List.fromList(<int>[1, 2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: coverStore,
          pickCover: () async => (bytes: png, extension: 'png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('book-detail-change-cover')),
    );
    await tester.pumpAndSettle();

    expect(coverStore.replaced, isTrue);
    expect(find.text('封面已更新'), findsOneWidget);
  });
}
