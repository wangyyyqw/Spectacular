import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/stats_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/startup_storage.dart';

import 'support/test_epub.dart';
import 'support/reader_pump.dart';

import 'package:reader_ui/reader_session.dart';

/// 内存存储（零 IO）：加载圈转一帧即出内容，固定 pump 即可。
Future<void> _settle(WidgetTester tester, {int frames = 4}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _tapStorageAction(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await _settle(tester);
}

void main() {
  test('宿主可导入核心契约', () {
    expect(CancelToken().isCancelled, isFalse);
  });

  testWidgets('应用壳：四底栏切换，书架空态与导入入口', (tester) async {
    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: progress),
    );
    await _settle(tester);

    for (final label in <String>['书架', '统计', '书评', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.byTooltip('导入 EPUB'), findsOneWidget);

    await tester.tap(find.text('统计'));
    await _settle(tester);
    expect(find.text('图书时长'), findsOneWidget);

    await tester.tap(find.text('书评'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('notes-tab')), findsOneWidget);
    expect(find.byTooltip('刷新笔记'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await _settle(tester);
    expect(find.text('导入书籍后可以在这里写书评'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await _settle(tester);
    expect(find.text('书架排序'), findsOneWidget);
  });

  testWidgets('书架：导入后出现书籍卡片，可进入阅读并返回', (tester) async {
    final library = LibraryStore.memory();
    final entry = await library.importBytes(
      buildTestEpub(title: '山海小记', author: '测试作者'),
      fallbackTitle: 'sample.epub',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async => <String>[entry.filePath],
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('山海小记'), findsWidgets);
    expect(find.text('测试作者'), findsNothing, reason: '书架只显示书名');
    final cover = tester.widget<AspectRatio>(
      find.byKey(const ValueKey<String>('book-card-cover')),
    );
    expect(cover.aspectRatio, closeTo(3 / 4, 0.001));

    await tester.tap(find.text('山海小记').first);
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey<String>('reader-page')),
    );
    // 正文由 Canvas 绘制（无 Text 组件）：断言 ReaderPage 已挂载。
    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);

    // 阅读页无 AppBar 返回键：直接 pop 根导航（等价系统返回）。
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _settle(tester);
    expect(find.byTooltip('导入 EPUB'), findsOneWidget);
  });

  testWidgets('启动失败在四页持续提示临时模式，重试与诊断失败仍可再操作', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    var exports = 0;
    final retry = Completer<AppDatabase?>();
    final diagnostic = Completer<void>();
    final storage = StartupStorage(
      log: ReaderLog(),
      openDatabase: () {
        attempts++;
        if (attempts == 1) throw StateError('测试数据库打不开');
        return retry.future;
      },
      onExportDiagnostics: () => ++exports == 1
          ? diagnostic.future
          : Future<void>.value(),
    );
    addTearDown(storage.dispose);
    expect(await storage.retry(), isFalse);
    await tester.pumpWidget(ReaderApp.withStorage(storage: storage));
    await _settle(tester);
    final oldLibrary = storage.library;
    final oldHome = tester.state(find.byType(HomeShell));
    expect(find.text('本地数据库不可用，当前为临时模式'), findsOneWidget);
    expect(find.textContaining('持久化不可用'), findsOneWidget);
    expect(find.text('书架还是空的'), findsNothing);
    expect(tester.widget<BookshelfPage>(find.byType(BookshelfPage)).allowImport,
        isFalse);
    for (final label in ['统计', '书评', '我的', '书架']) {
      await tester.tap(find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(label),
      ));
      await _settle(tester);
      expect(_key('temporary-storage-banner'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await _tapStorageAction(tester, 'storage-retry');
    expect(tester.widget<TextButton>(_key('storage-retry')).onPressed, isNull);
    await _tapStorageAction(tester, 'storage-retry');
    expect(attempts, 2);
    retry.complete(null);
    await _settle(tester);
    expect(find.text('本地数据库仍不可用，请稍后重试'), findsOneWidget);
    expect(storage.library, same(oldLibrary));
    expect(oldHome.mounted, isTrue);

    await _tapStorageAction(tester, 'storage-export-diagnostics');
    expect(tester.widget<TextButton>(_key('storage-retry')).onPressed, isNull);
    diagnostic.completeError(StateError('测试导出失败'));
    await _settle(tester);
    expect(tester.widget<TextButton>(_key('storage-export-diagnostics')).onPressed,
        isNotNull);
    await _tapStorageAction(tester, 'storage-export-diagnostics');
    expect(exports, 2);
    expect(storage.isTemporary, isTrue);
    expect(_key('temporary-storage-banner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正式启动入口重试成功后重新绑定书库与真实阅读进度', (tester) async {
    final directory = Directory.systemTemp.createTempSync('startup-widget');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      directory.deleteSync(recursive: true);
    });
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final entry = await pumpReaderTask(
      tester,
      library.importBytes(buildTestEpub(title: '原书库中的书')),
    );
    await pumpReaderTask(
      tester,
      DriftProgressStore(db).save(
        entry.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 1, readingPercent: 0.65),
      ),
    );
    var attempts = 0;
    final storage = StartupStorage(
      log: ReaderLog(),
      openDatabase: () async => ++attempts == 1 ? null : db,
      createLibrary: (_) => library,
    );
    addTearDown(storage.dispose);
    expect(await storage.retry(), isFalse);
    await tester.pumpWidget(ReaderApp.withStorage(storage: storage));
    await _settle(tester);
    final oldHome = tester.state(find.byType(HomeShell));
    final oldShelf = tester.state(find.byType(BookshelfPage));
    expect(_key('temporary-storage-banner'), findsOneWidget);

    await tester.tap(_key('storage-retry'));
    await pumpReaderUntil(tester, find.text('原书库中的书'));

    expect(_key('temporary-storage-banner'), findsNothing);
    expect(oldHome.mounted, isFalse);
    expect(oldShelf.mounted, isFalse, reason: '旧开书器与导入队列必须随页面销毁');
    final shelf = tester.widget<BookshelfPage>(find.byType(BookshelfPage));
    final stats = tester.widget<StatsPage>(
      find.byType(StatsPage, skipOffstage: false),
    );
    expect(shelf.library, same(library));
    expect(stats.library, same(library));
    expect(shelf.progressStore, same(storage.progressStore));
    expect(stats.progressStore, same(storage.progressStore));
    expect(shelf.progressStore, isA<DriftProgressStore>());
    expect(shelf.allowImport, isTrue);
    expect(find.textContaining('65%'), findsOneWidget);
    expect(File(entry.filePath).existsSync(), isTrue);
    expect(tester.widget<IconButton>(_key('bookshelf-import')).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
