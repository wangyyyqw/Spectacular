import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

void main() {
  testWidgets('我的页可查看诊断日志且不显示浮动提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(library: LibraryStore.memory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看诊断日志'), findsOneWidget);

    await tester.tap(find.text('查看诊断日志'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志'), findsNothing);
    expect(find.text('查看诊断日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '主题抽屉关闭保留原设置，选择后等待真实保存回调',
    (tester) async {
      final saved = <ThemeMode>[];
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ProfilePage(
            library: LibraryStore.memory(),
            themeMode: ThemeMode.light,
            onThemeModeChanged: (mode) async {
              saved.add(mode);
              await pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('界面主题'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);

      await tester.tap(find.text('界面主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('夜间模式'));
      await tester.pumpAndSettle();
      expect(saved, [ThemeMode.dark]);
      final themeTile = find.widgetWithText(ListTile, '界面主题');
      expect(tester.widget<ListTile>(themeTile).onTap, isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(themeTile).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    '书架排序抽屉标记当前项，取消保留设置，选择保存原存储',
    (tester) async {
      final library = LibraryStore.memory();
      await library.setSetting(bookshelfSortKey, BookSortOrder.recent.value);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ProfilePage(library: library),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('bookshelf-sort-setting'));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('bookshelf-sort-recent')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(await library.getSetting(bookshelfSortKey), 'recent');
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookshelf-sort-title')));
      await tester.pumpAndSettle();
      expect(await library.getSetting(bookshelfSortKey), 'title');
      expect((tester.widget<ListTile>(entry).subtitle! as Text).data, '书名');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets('清理日志保留后果确认，可取消返回设置', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProfilePage(library: LibraryStore.memory()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('logs-clear')));
    await tester.tap(find.byKey(const ValueKey('logs-clear')));
    await tester.pumpAndSettle();
    final confirmation = find.byWidgetPredicate(
      (widget) => widget is AlertDialog,
    );
    expect(confirmation, findsOneWidget);
    expect(find.byKey(const ValueKey('logs-clear-confirm')), findsOneWidget);
    expect(find.text('将删除本机保存的全部诊断日志（含历史会话），确定吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmation, findsNothing);
    expect(find.byKey(const ValueKey('logs-clear')), findsOneWidget);
  });
}
