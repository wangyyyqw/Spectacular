import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 列表视图里的书名顺序。
List<String> _listTitles(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('bookshelf-list')),
      matching: find.byType(Text),
    ),
  ))
    if (text.key is ValueKey<String> &&
        (text.key! as ValueKey<String>).value.startsWith('book-row-title-'))
      text.data ?? '',
];

class _UpdateController extends OnlineBookController {
  _UpdateController(LibraryStore library) : super(library: library);

  Future<void> publishUpdates(Map<String, Object?> updates) async {
    await library.setSetting(bookshelfOnlineUpdatesKey, jsonEncode(updates));
    notifyListeners();
  }
}

void main() {
  late Directory temp;
  late List<File> files;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bookshelf-view');
    files = <File>[
      for (final title in <String>['B书', 'A书', 'C书'])
        File('${temp.path}/文件名与元数据不同-$title.epub')
          ..writeAsBytesSync(buildTestEpub(title: title)),
    ];
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  testWidgets('更新事件立即刷新书架，按最新章节时间上浮且保留最近阅读优先级', (tester) async {
    final library = LibraryStore.memory();
    final books = (await tester.runAsync(
      () async => [
        for (final file in files) await library.importFile(file.path),
      ],
    ))!;
    final online = _UpdateController(library);
    await library.setSetting('bookshelf.grid', 'false');
    await library.setSetting(bookshelfAutoUpdateFirstKey, 'true');
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          onlineBooks: online,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    final original = _listTitles(tester);
    final now = DateTime.now().millisecondsSinceEpoch;
    await online.publishUpdates({
      books[0].id: {
        'updated': true,
        'updatedAt': now - 3600000,
        'checkedAt': now + 1,
      },
      books[1].id: {
        'updated': true,
        'updatedAt': now - 60000,
        'checkedAt': now,
      },
    });
    await _settle(tester);
    expect(_listTitles(tester).take(2), [books[1].title, books[0].title]);
    expect(_listTitles(tester), isNot(original));
    await library.touchLastRead(books[2].id);
    await _settle(tester);
    expect(_listTitles(tester).first, books[2].title);
    await tester.pumpWidget(const SizedBox());
    online.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('已选分组及切换动画中启用全部书架分组，书籍保持可见', (tester) async {
    final library = LibraryStore.memory();
    final book = (await tester.runAsync(
      () => library.importBytes(buildTestEpub(title: '分组切换保留书架')),
    ))!;
    final group = await library.createGroup('测试分组');
    await library.setBooksGroup([book.id], groupId: group.id);
    final ungrouped = (await tester.runAsync(
      () => library.importBytes(buildTestEpub(title: '默认未分组图书')),
    ))!;
    Widget page(int token) => MaterialApp(
      home: BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
        refreshToken: token,
      ),
    );
    await tester.pumpWidget(page(0));
    await _settle(tester);
    await tester.tap(find.text('测试分组'));
    await tester.pump(const Duration(milliseconds: 30));
    await library.setSetting(bookshelfAllAsGroupKey, 'true');
    await tester.pumpWidget(page(1));
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('bookshelf-grid')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('book-card-title-${book.id}')), findsOneWidget);
    expect(find.text('测试分组'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-all')));
    await _settle(tester);
    expect(find.byKey(ValueKey('book-card-title-${book.id}')), findsNothing);
    expect(
      find.byKey(ValueKey('book-card-title-${ungrouped.id}')),
      findsOneWidget,
    );
    expect((await library.groupAssignments())[book.id], group.id);
    expect(tester.takeException(), isNull);
    await library.setSetting(bookshelfAllAsGroupKey, 'false');
    await tester.pumpWidget(page(2));
    await _settle(tester);
    expect(find.text('测试分组'), findsOneWidget);
    expect(find.byKey(ValueKey('book-card-title-${book.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final reducedMotion in [false, true]) {
    testWidgets('视图动画支持连续切换、过渡中导航及减少动态效果：$reducedMotion', (tester) async {
      final library = LibraryStore.memory();
      await tester.runAsync(() async {
        await library.importBytes(buildTestEpub(title: '切换动画'));
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: child!,
          ),
          home: BookshelfPage(
            library: library,
            progressStore: MemoryReaderProgressStore(),
          ),
        ),
      );
      await _settle(tester);
      final searchSurface = tester.widget<Material>(
        find.byKey(const ValueKey('bookshelf-search-surface')),
      );
      final importSurface = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('bookshelf-import')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(searchSurface.borderRadius, BorderRadius.circular(20));
      expect(searchSurface.elevation, 3);
      expect(importSurface.borderRadius, searchSurface.borderRadius);
      expect(importSurface.elevation, 2);
      expect(importSurface.color, searchSurface.color);
      expect(
        importSurface.color,
        ReaderDrawerStyle.searchSurfaceOf(
          Theme.of(
            tester.element(find.byKey(const ValueKey('bookshelf-import'))),
          ),
        ),
      );
      final grid = find.byKey(const ValueKey('bookshelf-grid'));
      final list = find.byKey(const ValueKey('bookshelf-list'));
      final toolbarFinder = find.byKey(
        const ValueKey('bookshelf-group-toolbar'),
      );
      final toolbar = tester.getRect(toolbarFinder);
      final groupCenter = tester.getCenter(find.text('全部')).dy;
      expect(find.textContaining('全部 '), findsNothing);
      final toolbarIcons = tester.widgetList<AppIcon>(
        find.descendant(of: toolbarFinder, matching: find.byType(AppIcon)),
      );
      expect(toolbarIcons.map((icon) => icon.strokeWidth), <double>[1.3, 1.3]);
      final toolbarButtons = tester.widgetList<IconButton>(
        find.descendant(of: toolbarFinder, matching: find.byType(IconButton)),
      );
      final theme = Theme.of(tester.element(find.byType(BookshelfPage)));
      expect(toolbarButtons, hasLength(2));
      for (final button in toolbarButtons) {
        expect(button.color, theme.colorScheme.onSurfaceVariant);
        expect(button.disabledColor, theme.disabledColor);
      }
      for (final button in [
        find.byTooltip('列表视图'),
        find.byKey(const ValueKey('bookshelf-multi-select')),
      ]) {
        final icon = find.descendant(
          of: button,
          matching: find.byType(AppIcon),
        );
        expect(tester.getCenter(icon).dy, closeTo(groupCenter, .01));
      }
      final cover = tester.getRect(
        find.byKey(const ValueKey('book-card-cover')),
      );
      final gap = toolbar.top - tester.getBottomLeft(
        find.byKey(const ValueKey('bookshelf-search-surface')),
      ).dy;
      expect(cover.top - toolbar.bottom, closeTo(gap, .01));
      final restingBounds = tester.getRect(grid);
      await tester.tap(find.byTooltip('列表视图'));
      await tester.pump();
      final enteringBounds = tester.getRect(list);
      expect(enteringBounds.size, restingBounds.size, reason: '切换时不缩放封面与文字');
      expect(enteringBounds.left, restingBounds.left);
      expect(
        enteringBounds.top - restingBounds.top,
        reducedMotion ? 0 : inExclusiveRange(0, 13),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .getCenter(
              find.descendant(
                of: find.byTooltip('网格视图'),
                matching: find.byType(AppIcon),
              ),
            )
            .dy,
        closeTo(groupCenter, .01),
      );
      expect(list, findsOneWidget);
      expect(grid, reducedMotion ? findsNothing : findsOneWidget);
      if (!reducedMotion) {
        expect(grid.hitTestable(), findsNothing);
        expect(tester.getRect(grid).top, lessThan(restingBounds.top));
        expect(
          tester.getRect(list).top,
          inExclusiveRange(restingBounds.top, enteringBounds.top),
        );
      }

      await tester.tap(find.byTooltip('网格视图'));
      await tester.pump();
      final returningGrid = grid.last;
      expect(tester.getRect(returningGrid).size, restingBounds.size);
      expect(
        tester.getRect(returningGrid).top - restingBounds.top,
        reducedMotion ? 0 : inExclusiveRange(-13, 0),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.byTooltip('列表视图'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(await library.getSetting('bookshelf.grid'), 'false');

      // 动画中打开页面也只能收集当前视图的封面 Hero。
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('目标页面'))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('目标页面'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      expect(grid, findsNothing);
      expect(tester.getRect(list), restingBounds);
      expect(find.text('切换动画'), findsWidgets);
    });
  }

  testWidgets('视图切换生效并持久化，排序入口不再显示在书架顶部', (tester) async {
    final library = LibraryStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async => <String>[
            for (final file in files) file.path,
          ],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从本机导入'));
    await _settle(tester, frames: 12);
    expect(
      find.byKey(const ValueKey<String>('bookshelf-grid')),
      findsOneWidget,
    );
    final entries = await library.list();
    for (final entry in entries) {
      final card = find.byKey(ValueKey('book-card-${entry.id}'));
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('book-card-title-${entry.id}')))
            .textAlign,
        TextAlign.center,
      );
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .every((text) => text.data == entry.title),
        isTrue,
      );
      expect(find.byKey(ValueKey('book-card-meta-${entry.id}')), findsNothing);
      expect(find.text(entry.title), findsWidgets);
    }
    expect(find.textContaining('文件名与元数据不同'), findsNothing);
    expect(find.byKey(const ValueKey('bookshelf-count')), findsNothing);
    expect(find.text('书架'), findsNothing);
    final search = tester.getRect(
      find.byKey(const ValueKey('bookshelf-search-field')),
    );
    final toolbar = tester.getRect(
      find.byKey(const ValueKey('bookshelf-group-toolbar')),
    );
    final toggle = tester.getRect(find.byTooltip('列表视图'));
    expect(
      search.width,
      greaterThan(
        tester.view.physicalSize.width / tester.view.devicePixelRatio * .7,
      ),
    );
    expect(search.bottom, lessThanOrEqualTo(toolbar.top));
    expect(toggle.center.dy, closeTo(toolbar.center.dy, 1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Hero &&
            entries.any((entry) => widget.tag == bookCoverHeroTag(entry.id)),
      ),
      findsNWidgets(entries.length),
    );

    // 切到列表视图。
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(
      find.byKey(const ValueKey<String>('bookshelf-list')),
      findsOneWidget,
    );
    expect(find.text('测试作者'), findsNWidgets(entries.length));
    expect(find.text('已读 0 分钟'), findsNWidgets(entries.length));
    expect(find.text('已读 0 / 1 章'), findsNWidgets(entries.length));
    expect(find.textContaining('文件名与元数据不同'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Hero &&
            entries.any((entry) => widget.tag == bookCoverHeroTag(entry.id)),
      ),
      findsNWidgets(entries.length),
    );
    final rowCover = tester.getSize(
      find.byKey(const ValueKey<String>('book-row-cover')).first,
    );
    expect(rowCover.width / rowCover.height, closeTo(3 / 4, 0.001));
    expect(await library.getSetting('bookshelf.grid'), 'false');
    expect(find.byTooltip('排序'), findsNothing);

    // 默认最近阅读优先：都没读过 → 导入时间倒序（C, A, B 的导入顺序是 B,A,C）。
    expect(_listTitles(tester), <String>['C书', 'A书', 'B书']);

    // 重新构建页面（≈ 重启）应恢复列表视图。
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    expect(
      find.byKey(const ValueKey<String>('bookshelf-list')),
      findsOneWidget,
    );
    expect(_listTitles(tester), <String>['C书', 'A书', 'B书']);
  });

  for (final publisherId in [null, 0, 88]) {
    final public = publisherId != null && publisherId > 0;
    testWidgets(
      '长按书籍${publisherId == null
          ? '未关联'
          : public
          ? '已公开关联'
          : '仅同步身份'}保持正确关联入口',
      (tester) async {
        final library = LibraryStore.memory();
        final progress = MemoryReaderProgressStore();
        final reaMicro = ReaMicroController(
          library: library,
          progressStore: progress,
          enableLanLoginServer: false,
        );
        addTearDown(reaMicro.dispose);
        await tester.runAsync(reaMicro.initialize);
        await tester.pumpWidget(
          MaterialApp(
            home: BookshelfPage(
              library: library,
              progressStore: progress,
              reaMicro: reaMicro,
              pickEpubFiles: () async => <String>[files.first.path],
              readFile: (path) async => File(path).readAsBytesSync(),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byTooltip('导入 EPUB / TXT'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('从本机导入'));
        await _settle(tester, frames: 12);
        final entry = (await library.list()).single;
        if (publisherId != null) {
          await reaMicro.linkBook(
            entry.id,
            const ReaMicroCloudBook(
              cloudBookId: 11,
              name: '云端书',
              publishers: [
                ReaMicroCloudPublisher(publisherId: 88, publisher: '起点中文网'),
              ],
            ),
            publisherId: publisherId,
          );
        }

        await tester.longPress(
          find.byKey(ValueKey<String>('book-card-${entry.id}')),
        );
        await _settle(tester);
        expect(find.text(public ? '起点中文网' : '未关联'), findsOneWidget);

        final publicReading = find.byKey(
          const ValueKey<String>('book-detail-public-reading'),
        );
        expect(publicReading.hitTestable(), findsOneWidget);
        await tester.ensureVisible(publicReading);
        await _settle(tester);
        await tester.tap(publicReading);
        // 关联入口保留阅微登录提示。
        await _settle(tester, frames: 6);
        expect(find.text('请先登录阅微账号'), findsOneWidget);
      },
    );
  }
  testWidgets('网格与列表按压图书时不覆盖封面', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '无按压叠层'));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    void expectPressOverlayIsTransparent(String key) {
      final inkWell = tester.widget<InkWell>(find.byKey(ValueKey(key)));
      expect(
        inkWell.overlayColor?.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
    }

    expectPressOverlayIsTransparent('book-card-${entry.id}');
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expectPressOverlayIsTransparent('book-row-${entry.id}');
  });
}
