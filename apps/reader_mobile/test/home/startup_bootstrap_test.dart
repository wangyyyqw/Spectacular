import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/startup_storage.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets('首帧布局后初始化，慢启动不显示临时空书架且仅报告一次就绪', (tester) async {
    final database = Completer<AppDatabase?>();
    final storage = StartupStorage(openDatabase: () => database.future);
    addTearDown(storage.dispose);
    var calls = 0;
    var ready = 0;
    await tester.pumpWidget(
      ReaderApp.withStorage(
        storage: storage,
        onStartupReady: () => ready++,
        initialize: () async {
          calls++;
          expect(
            tester.binding.schedulerPhase,
            SchedulerPhase.postFrameCallbacks,
          );
          expect(find.byType(HomeShell), findsNothing);
          await storage.retry();
        },
      ),
    );
    expect(calls, 1);
    expect(ready, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(HomeShell), findsNothing);
    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsNothing,
    );

    database.complete(null);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump();
    }

    await pumpReaderUntilComplete(tester, () => ready == 1);

    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsOneWidget,
    );
    expect(calls, 1);
    expect(ready, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初始化完成后直接绑定真实书库与已保存进度', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'startup-first-frame',
    );
    final db = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
      directory.deleteSync(recursive: true);
    });
    final book = await pumpReaderTask(
      tester,
      library.importBytes(buildTestEpub(title: '启动后保留的书')),
    );
    await pumpReaderTask(
      tester,
      DriftProgressStore(db).save(
        book.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 1, readingPercent: .65),
      ),
    );
    final pending = Completer<AppDatabase?>();
    final storage = StartupStorage(
      openDatabase: () => pending.future,
      createLibrary: (_) => library,
    );
    addTearDown(storage.dispose);
    final initialized = Completer<void>();
    await tester.pumpWidget(
      ReaderApp.withStorage(
        storage: storage,
        initialize: () async {
          await storage.retry();
          initialized.complete();
        },
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byType(BookshelfPage), findsNothing);
    pending.complete(db);
    await pumpReaderTask(tester, initialized.future);
    await pumpReaderUntil(tester, find.text('启动后保留的书'));
    final shelf = tester.widget<BookshelfPage>(find.byType(BookshelfPage));
    expect(shelf.library, same(library));
    // 宿主使用阅微追踪包装器，继续通过正式存储入口核对已保存的位置。
    expect(shelf.allowImport, isTrue);
    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsNothing,
    );

    final saved = await pumpReaderTask(
      tester,
      shelf.progressStore.load(book.id),
    );
    expect(saved?.readingPercent, .65);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初始化异常也能进入临时恢复界面，不永久卡在开屏', (tester) async {
    final storage = StartupStorage();
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      ReaderApp.withStorage(
        storage: storage,
        initialize: () async => throw StateError('初始化失败'),
      ),
    );
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('temporary-storage-banner')),
    );

    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
