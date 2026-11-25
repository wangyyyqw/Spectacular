import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/startup_splash.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/startup_storage.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void _expectVisibleBrand(WidgetTester tester) {
  final splash = find.byType(StartupSplash);
  expect(splash, findsOneWidget);
  expect(
    find.descendant(of: splash, matching: find.text('墨屿')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: splash, matching: find.byType(Image)),
    findsOneWidget,
  );
  for (final opacity in tester.widgetList<Opacity>(
    find.descendant(of: splash, matching: find.byType(Opacity)),
  )) {
    expect(opacity.opacity, 1, reason: '首帧标识不能全透明，也不能在初始化完成前揭开书架');
  }
}

void main() {
  testWidgets('开屏第一帧即显示标识，不再从透明淡入', (tester) async {
    await tester.pumpWidget(
      ReaderApp(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    _expectVisibleBrand(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首帧之后才初始化，慢启动不显示临时空书架且开屏不重播', (tester) async {
    final database = Completer<AppDatabase?>();
    final storage = StartupStorage(openDatabase: () => database.future);
    addTearDown(storage.dispose);
    var calls = 0;
    await tester.pumpWidget(
      ReaderApp.withStorage(
        storage: storage,
        initialize: () async {
          calls++;
          expect(
            tester.binding.schedulerPhase,
            SchedulerPhase.postFrameCallbacks,
          );
          _expectVisibleBrand(tester);
          await storage.retry();
        },
      ),
    );
    expect(calls, 1);
    final splashState = tester.state(find.byType(StartupSplash));
    await tester.pump(const Duration(seconds: 2));
    _expectVisibleBrand(tester);
    expect(find.byType(HomeShell), findsNothing);
    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsNothing,
    );

    database.complete(null);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump();
    }
    expect(tester.state(find.byType(StartupSplash)), same(splashState));
    expect(
      tester.widget<StartupSplash>(find.byType(StartupSplash)).ready,
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.byType(StartupSplash), findsNothing);
    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsOneWidget,
    );
    expect(calls, 1);
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
    _expectVisibleBrand(tester);
    expect(find.byType(BookshelfPage), findsNothing);
    pending.complete(db);
    await pumpReaderTask(tester, initialized.future);
    await pumpReaderUntil(tester, find.text('启动后保留的书'));
    final shelf = tester.widget<BookshelfPage>(find.byType(BookshelfPage));
    expect(shelf.library, same(library));
    expect(shelf.progressStore, same(storage.progressStore));
    expect(shelf.allowImport, isTrue);
    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsNothing,
    );
    expect(find.byType(StartupSplash), findsNothing);
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
    await tester.pumpAndSettle();
    expect(find.byType(StartupSplash), findsNothing);
    expect(
      find.byKey(const ValueKey('temporary-storage-banner')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
