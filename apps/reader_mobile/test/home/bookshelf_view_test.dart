import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';

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

void main() {
  late Directory temp;
  late List<File> files;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bookshelf-view');
    files = <File>[
      for (final title in <String>['B书', 'A书', 'C书'])
        File('${temp.path}/$title.epub')
          ..writeAsBytesSync(buildTestEpub(title: title)),
    ];
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

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
    await _settle(tester, frames: 12);
    expect(
      find.byKey(const ValueKey<String>('bookshelf-grid')),
      findsOneWidget,
    );
    final entries = await library.list();
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
    expect(find.text('未开始 · 测试作者'), findsNWidgets(entries.length));
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

  testWidgets('长按书籍可进入阅微公开阅读入口', (tester) async {
    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    final reaMicro = ReaMicroController(
      library: library,
      progressStore: progress,
      enableLanLoginServer: false,
    );
    addTearDown(reaMicro.dispose);
    await reaMicro.initialize();
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
    await _settle(tester, frames: 12);
    final entry = (await library.list()).single;

    await tester.longPress(
      find.byKey(ValueKey<String>('book-card-${entry.id}')),
    );
    await _settle(tester);
    expect(find.text('关联'), findsOneWidget);

    final publicReading = find.byKey(
      const ValueKey<String>('book-detail-public-reading'),
    );
    await tester.ensureVisible(publicReading);
    await _settle(tester);
    await tester.tap(publicReading);
    // 导入完成的提示还在展示，登录提示会排在它的 4 秒展示时间之后。
    await _settle(tester, frames: 60);
    expect(find.text('请先登录阅微账号'), findsOneWidget);
  });
}
