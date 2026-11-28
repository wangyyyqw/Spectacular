import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';

import '../support/test_epub.dart';

void main() {
  for (final mode in ['普通', '减少动态', '墨水屏']) {
    testWidgets('堆叠展开收起随内容过渡，连续操作只保留当前与上一层：$mode', (tester) async {
      final library = LibraryStore.memory();
      late BookTag tag;
      await tester.runAsync(() async {
        tag = await library.createTag('历史');
        for (final title in ['甲书', '乙书']) {
          final book = await library.importBytes(buildTestEpub(title: title));
          await library.addBookTag(book.id, tag.id);
        }
        await library.setSetting(bookshelfTagStacksKey, 'true');
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => ReaderFrostedScope(
            inkMode: mode == '墨水屏',
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: mode == '减少动态'),
              child: child!,
            ),
          ),
          home: BookshelfPage(
            library: library,
            progressStore: MemoryReaderProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stack = find.byKey(ValueKey('book-stack-${tag.id}'));
      final back = find.byKey(const ValueKey('bookshelf-stack-back'));
      final grid = find.byKey(const ValueKey('bookshelf-grid'));
      final original = tester.getRect(grid);
      await tester.tap(stack);
      await tester.pump();
      expect(back, findsOneWidget);
      if (mode == '普通') {
        expect(grid, findsNWidgets(2));
        expect(tester.getRect(grid.first), original, reason: '标题不改变旧视图的边界');
        expect(stack.hitTestable(), findsNothing);
        expect(tester.getRect(grid.last).left, greaterThan(original.left));
      } else {
        expect(grid, findsOneWidget);
        expect(stack, findsNothing);
      }
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(back);
      await tester.pump();
      expect(back.hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(stack.hitTestable());
      await tester.pump();
      expect(grid.evaluate().length, lessThanOrEqualTo(2));
      await tester.tap(find.byTooltip('列表视图'));
      await tester.pump();
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('目标页'))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bookshelf-list')), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget);
      expect(back, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
