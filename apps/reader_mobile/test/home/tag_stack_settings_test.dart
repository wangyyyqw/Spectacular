import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/tag_stack_settings_sheet.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

final _tags = [
  for (final name in ['穿越', '明朝', '寒门'])
    BookTag(id: name, name: name, createdAt: DateTime(2026)),
];

Future<void> _show(
  WidgetTester tester, {
  List<BookTag>? tags,
  List<String> selected = const ['穿越', '明朝', '寒门'],
  double textScale = 1,
  required Future<void> Function(List<String>) onSave,
  required Future<void> Function(BookTag) onDelete,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: TagStackSettingsSheet(
        groupName: '历史',
        tags: tags ?? _tags,
        counts: const {'穿越': 3, '明朝': 5, '寒门': 2},
        selected: selected,
        onSave: onSave,
        onDelete: onDelete,
      ),
    ),
  ),
);

void main() {
  testWidgets('已选标签按保存顺序显示，可通过手柄拖动并保存新顺序', (tester) async {
    List<String>? saved;
    await _show(
      tester,
      selected: ['寒门', '穿越', '明朝'],
      onSave: (ids) async => saved = ids,
      onDelete: (_) async {},
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('stack-tag-drag-寒门'));
    final last = find.byKey(const ValueKey('stack-tag-drag-明朝'));
    expect(tester.getCenter(first).dy, lessThan(tester.getCenter(last).dy));
    final start = tester.getTopLeft(first) + const Offset(4, 4);
    final end = tester.getBottomLeft(last) + const Offset(22, 25);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / 10)!);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(first).dy, greaterThan(tester.getCenter(last).dy));
    expect(find.text('2 本在本分组 · 第 3 位'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-stacks-save')));
    await tester.pumpAndSettle();
    expect(saved, ['穿越', '明朝', '寒门']);
  });

  testWidgets('长标签列表拖到视口边缘时自动滚动并可移到末尾', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tags = [
      for (var index = 0; index < 15; index++)
        BookTag(id: '$index', name: '标签 $index', createdAt: DateTime(2026)),
    ];
    List<String>? saved;
    await _show(
      tester,
      tags: tags,
      selected: tags.map((tag) => tag.id).toList(),
      onSave: (ids) async => saved = ids,
      onDelete: (_) async {},
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('tag-stacks-order'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    final start =
        tester.getTopLeft(find.byKey(const ValueKey('stack-tag-drag-0'))) +
        const Offset(4, 4);
    final end = Offset(start.dx, tester.getBottomLeft(list).dy - 8);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / 10)!);
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var step = 0; step < 100; step++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (scrollable.position.pixels >= scrollable.position.maxScrollExtent) {
        break;
      }
    }
    expect(scrollable.position.pixels, greaterThan(0));
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 1),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-stacks-save')));
    await tester.pumpAndSettle();
    expect(saved, [for (var index = 1; index < 15; index++) '$index', '0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除需确认，成功后从列表和待保存顺序移除', (tester) async {
    final deleted = <String>[];
    List<String>? saved;
    await _show(
      tester,
      onSave: (ids) async => saved = ids,
      onDelete: (tag) async => deleted.add(tag.id),
    );
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey('stack-tag-delete-明朝'));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.textContaining('所有书籍和标签堆叠'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-tag-confirm')));
    await tester.pumpAndSettle();
    expect(deleted, ['明朝']);
    expect(find.byKey(const ValueKey('stack-tag-option-明朝')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-stacks-save')));
    await tester.pumpAndSettle();
    expect(saved, ['穿越', '寒门']);
  });

  testWidgets('删除中禁用保存和排序，失败后保留标签并可重试', (tester) async {
    final pending = Completer<void>();
    await _show(tester, onSave: (_) async {}, onDelete: (_) => pending.future);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stack-tag-delete-穿越')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-tag-confirm')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('tag-stacks-save')))
          .onPressed,
      isNull,
    );
    expect(find.text('正在删除标签…'), findsOneWidget);
    pending.completeError(const LibraryImportException('本书有未完成的编辑草稿'));
    await tester.pumpAndSettle();
    expect(find.text('本书有未完成的编辑草稿'), findsOneWidget);
    expect(find.byKey(const ValueKey('stack-tag-option-穿越')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('stack-tag-delete-穿越')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('窄屏大字时标签排序和删除操作不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _show(
      tester,
      textScale: 2,
      onSave: (_) async {},
      onDelete: (_) async {},
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('stack-tag-drag-穿越')), findsOneWidget);
    expect(find.byKey(const ValueKey('stack-tag-delete-穿越')), findsOneWidget);
  });
}
