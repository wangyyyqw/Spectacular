import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_sheet.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-detail');
    db = AppDatabase(NativeDatabase.memory());
    store = LibraryStore(database: db, directoryProvider: () async => dir);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('长按面板保留书籍资料，不展示导入报告和关闭按钮', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(buildWarningEpub());
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetailSheet(entry: entry, library: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('告警书'), findsWidgets);
    expect(find.text('内容完整'), findsNothing);
    expect(find.text('导入'), findsNothing);
    expect(find.text('最近阅读'), findsNothing);
    expect(find.text('E_MANIFEST_MEDIA_TYPE_INFERRED'), findsNothing);
    expect(find.textContaining('缺少 media-type'), findsNothing);
    expect(find.text('导入报告'), findsNothing);
    expect(find.text('关闭'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('book-detail-reading-chart')),
      findsNothing,
    );
  });

  testWidgets('长按菜单分为操作卡与删除卡，行间用缩进分隔线', (tester) async {
    final entry = BookEntry(
      id: 'style-book',
      title: '样式样本',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: BookDetailSheet(entry: entry, library: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('book-detail-actions'));
    final deletePanel = find.byKey(
      const ValueKey('book-detail-actions-delete'),
    );
    final scheme = Theme.of(
      tester.element(find.byKey(const ValueKey('book-detail-open-page'))),
    ).colorScheme;
    for (final card in [panel, deletePanel]) {
      final material = tester.widget<Material>(card);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      expect(shape.side.color, scheme.outlineVariant);
      expect(material.color, scheme.surface);
    }
    expect(
      find.descendant(of: panel, matching: find.byType(Divider)),
      findsWidgets,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(VerticalDivider)),
      findsWidgets,
    );
    expect(find.descendant(of: panel, matching: find.text('删除')), findsNothing);
    expect(
      find.descendant(of: deletePanel, matching: find.text('删除')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppIcon && widget.glyph == AppGlyph.chevronRight,
        ),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按进入详情抽屉，关闭后保留原书架与书籍资料', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(buildTestEpub(title: '详情抽屉样本'));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BookshelfPage(
          library: store,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('book-card-${entry.id}'));
    await tester.longPress(card);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-detail-open-page')));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsNothing);
    expect(card, findsOneWidget);
    expect((await store.bookById(entry.id))!.title, entry.title);
    expect(await store.list(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets('书架导出传入本书原文件并报告保存结果：$fail', (tester) async {
      late BookEntry entry;
      await tester.runAsync(() async {
        entry = await store.importBytes(buildTestEpub(title: '原书/导出:测试'));
      });
      const channel = MethodChannel(
        'com.spectacular.reader_mobile/epub_export',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        expect(call.method, 'saveToDownloads');
        expect(call.arguments, {
          'sourcePath': entry.filePath,
          'fileName': '原书_导出_测试.epub',
        });
        if (fail) {
          throw PlatformException(code: 'E_EXPORT_WRITE', message: '空间不足');
        }
        return 'content://media/external/downloads/123';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          home: BookshelfPage(
            library: store,
            progressStore: MemoryReaderProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(ValueKey('book-card-${entry.id}')));
      await tester.pumpAndSettle();
      expect(find.text('多选'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('book-detail-export')));
      await tester.runAsync(() async {
        for (var i = 0; i < 30 && !called; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(find.text(fail ? '导出失败：空间不足' : '已导出：原书_导出_测试.epub'), findsNothing);
      expect(await store.list(), hasLength(1));
      expect(File(entry.filePath).existsSync(), isTrue);
    });
  }

  testWidgets('无报告的书保留封面和未知作者，不显示报告空状态', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      spineCount: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetailSheet(entry: entry, library: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无修复或告警'), findsNothing);
    expect(find.text('未知作者'), findsOneWidget);
    expect(find.text('已读 0 / 3 章'), findsNothing);
    expect(find.text('已读 0 分钟'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('book-detail-chapter-progress')),
      findsOneWidget,
    );
    final coverSize = tester.getSize(
      find.byKey(const ValueKey<String>('book-detail-cover')),
    );
    expect(coverSize, const Size(80, 108));
  });

  testWidgets('元信息底部显示章节进度条，隐藏内容等级与日期', (tester) async {
    final semantics = tester.ensureSemantics();
    final entry = BookEntry(
      id: 'reading-book',
      title: '章节进度',
      author: '测试作者',
      filePath: '',
      addedAt: DateTime(2026, 11, 1),
      lastReadAt: DateTime(2026, 11, 20),
      spineCount: 15,
      readabilityLevel: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetailSheet(
            entry: entry,
            library: store,
            progress: const ReaderProgress(spineIndex: 3, pageIndex: 2),
            readingDuration: const Duration(hours: 2, minutes: 15),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已读 4 / 15 章'), findsNothing);
    expect(find.bySemanticsLabel('已读 4 / 15 章'), findsOneWidget);
    final progressBarFinder = find.byKey(
      const ValueKey('book-detail-chapter-progress'),
    );
    final progressBar = tester.widget<LinearProgressIndicator>(
      progressBarFinder,
    );
    expect(progressBar.value, closeTo(4 / 15, 1e-9));
    expect(progressBar.minHeight, 3);
    final progressBarRect = tester.getRect(progressBarFinder);
    final titleRect = tester.getRect(find.text('章节进度'));
    final authorRect = tester.getRect(find.text('测试作者'));
    final duration = find.text('已读 2 小时 15 分');
    expect(duration, findsOneWidget);
    final durationRect = tester.getRect(duration);
    expect(authorRect.top - titleRect.bottom, greaterThan(8));
    expect(durationRect.top - authorRect.bottom, greaterThan(8));
    expect(durationRect.top, greaterThan(authorRect.bottom));
    expect(progressBarRect.top - durationRect.bottom, greaterThan(8));
    final cover = tester.getRect(
      find.byKey(const ValueKey('book-detail-cover')),
    );
    final metadata = tester.getRect(
      find.byKey(const ValueKey('book-detail-metadata')),
    );
    expect(metadata.top, closeTo(cover.top, 0.1));
    expect(metadata.bottom, closeTo(cover.bottom, 0.1));
    expect(metadata.height, closeTo(cover.height, 0.1));
    expect(progressBarRect.width, closeTo(metadata.width, 0.1));
    expect(progressBarRect.bottom, closeTo(cover.bottom, 0.1));
    expect(find.text('内容部分降级'), findsNothing);
    expect(find.text('章节'), findsNothing);
    expect(find.text('导入'), findsNothing);
    expect(find.text('最近阅读'), findsNothing);
    expect(find.text('2026-11-01'), findsNothing);
    expect(find.text('2026-11-20'), findsNothing);
    semantics.dispose();
  });

  testWidgets('书架长按汇总本书全部短会话，不混入其他书的时长', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(buildTestEpub(title: '计时书籍'));
      final other = await store.importBytes(buildTestEpub(title: '其他书籍'));
      final sessions = store.readingSessionStore()!;
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final startedAt = DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        10,
      );
      for (final (bookId, minutes) in [
        (entry.id, 60),
        (entry.id, 15),
        (entry.id, 1),
        (other.id, 120),
      ]) {
        await sessions.add(
          bookId: bookId,
          startedAt: startedAt,
          endedAt: startedAt.add(Duration(minutes: minutes)),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: store,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(ValueKey('book-card-${entry.id}')));
    await tester.pumpAndSettle();
    expect(find.text('已读 1 小时 16 分'), findsOneWidget);
    expect(find.text('已读 0 / 1 章'), findsNothing);
    expect(
      find.byKey(const ValueKey('book-detail-chapter-progress')),
      findsOneWidget,
    );
    final chart = find.byKey(
      const ValueKey<String>('book-detail-reading-chart'),
    );
    final cover = find.byKey(const ValueKey<String>('book-detail-cover'));
    expect(chart, findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(
      tester.getRect(chart).top,
      greaterThan(tester.getRect(cover).bottom),
    );
  });

  testWidgets('窄屏和放大文字下操作两两同行，遮罩和下拉仍可关闭', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = BookEntry(
      id: 'layout-book',
      title: '用于检查窄屏长书名换行和封面对齐的阅读作品',
      author: '用于检查单行省略的很长作者姓名',
      filePath: '',
      addedAt: DateTime(2026),
    );
    for (final (size, scale) in [
      (const Size(384, 2560 / 3), 1.0),
      (const Size(320, 640), 1.3),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => BookDetailSheet(entry: entry, library: store),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final cover = tester.getRect(
        find.byKey(const ValueKey('book-detail-cover')),
      );
      final metadata = tester.getRect(
        find.byKey(const ValueKey('book-detail-metadata')),
      );
      expect(metadata.top, closeTo(cover.top, 0.1));
      expect(metadata.bottom, closeTo(cover.bottom, 0.1));
      for (final (left, right) in [
        ('book-detail-booklists', 'book-detail-open-page'),
        ('book-detail-create-group', 'book-detail-pin'),
        ('book-detail-update', 'book-detail-export'),
      ]) {
        final leftButton = find.byKey(ValueKey(left));
        final rightButton = find.byKey(ValueKey(right));
        final leftRect = tester.getRect(leftButton);
        final rightRect = tester.getRect(rightButton);
        expect(leftRect.center.dy, closeTo(rightRect.center.dy, 0.1));
        expect(leftRect.right, lessThanOrEqualTo(rightRect.left));
        expect(leftRect.height, greaterThanOrEqualTo(48));
        expect(rightRect.height, greaterThanOrEqualTo(48));
        expect(leftButton.hitTestable(), findsOneWidget);
        expect(rightButton.hitTestable(), findsOneWidget);
      }
      for (final key in ['book-detail-delete']) {
        final button = find.byKey(ValueKey(key));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(button.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 80));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailSheet), findsNothing);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(BottomSheet));
      await tester.flingFrom(
        Offset(sheet.center.dx, sheet.top + 20),
        const Offset(0, 400),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailSheet), findsNothing);
    }
  });

  testWidgets('点删除返回 delete，由书架执行确认流程', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(popped, 'delete');
  });

  testWidgets('点详情返回 detail，由书架打开完整详情页', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(popped, 'detail');
  });

  testWidgets('点分组返回 create-group', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分组'));
    await tester.pumpAndSettle();
    expect(popped, 'create-group');
  });

  testWidgets('点加入书单返回 booklists，由书架打开书单选择', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('book-detail-booklists')),
    );
    await tester.pumpAndSettle();
    expect(popped, 'booklists');
  });

  testWidgets('长按菜单用导出替代多选，点击返回 export', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('多选'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-export')));
    await tester.pumpAndSettle();
    expect(popped, 'export');
  });
}
