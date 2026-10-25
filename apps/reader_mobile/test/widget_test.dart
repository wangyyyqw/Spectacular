import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';

import 'support/test_epub.dart';

/// 内存存储（零 IO）：加载圈转一帧即出内容，固定 pump 即可。
Future<void> _settle(WidgetTester tester, {int frames = 4}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('宿主可导入核心契约', () {
    expect(CancelToken().isCancelled, isFalse);
  });

  testWidgets('应用壳：四底栏切换，书架空态与导入入口', (tester) async {
    final library = LibraryStore.memory();
    final progress = FileReaderProgressStore.memory();
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: progress),
    );
    await _settle(tester);

    for (final label in <String>['书架', '统计', '书评', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.text('导入 EPUB'), findsOneWidget);

    await tester.tap(find.text('统计'));
    await _settle(tester);
    expect(find.text('总书数'), findsOneWidget);

    await tester.tap(find.text('书评'));
    await _settle(tester);
    expect(find.text('导入书籍后可以在这里写书评'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await _settle(tester);
    expect(find.text('排版引擎'), findsOneWidget);
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
          progressStore: FileReaderProgressStore.memory(),
          pickEpubFiles: () async => <String>[entry.filePath],
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('山海小记'), findsWidgets);
    expect(find.text('测试作者'), findsOneWidget);

    await tester.tap(find.text('山海小记').first);
    // 打开是同步计算（微任务）+ 骨架屏无限动画：固定步进推进到内容出现。
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 正文由 Canvas 绘制（无 Text 组件）：断言 ReaderPage 已挂载。
    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);

    // 阅读页无 AppBar 返回键：直接 pop 根导航（等价系统返回）。
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _settle(tester);
    expect(find.text('导入 EPUB'), findsOneWidget);
  });
}
