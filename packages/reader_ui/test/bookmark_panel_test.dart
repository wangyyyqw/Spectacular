import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/panels/bookmark_panel.dart';
import 'package:reader_ui/reader_session.dart';

ReaderBookmark _bookmark(String id, String label, {int spine = 0}) =>
    ReaderBookmark(
      id: id,
      cfi: 'epubcfi(/6/4/1:0)',
      spineIndex: spine,
      label: label,
      createdAt: DateTime(2026, 1, 1, 9, 30),
    );

void main() {
  testWidgets('书签面板：列表、点击跳转、删除', (tester) async {
    final selected = <ReaderBookmark>[];
    final deleted = <ReaderBookmark>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkPanel(
            bookmarks: <ReaderBookmark>[
              _bookmark('a', '第 2 章 · 第 1 页', spine: 1),
              _bookmark('b', '第 5 章 · 第 3 页', spine: 4),
            ],
            onSelect: selected.add,
            onDelete: deleted.add,
          ),
        ),
      ),
    );

    expect(find.text('书签'), findsOneWidget);
    expect(find.text('共 2 条'), findsOneWidget);
    expect(find.text('第 2 章 · 第 1 页'), findsOneWidget);

    await tester.tap(find.text('第 5 章 · 第 3 页'));
    expect(selected.single.id, 'b');

    final deleteIcon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.glyph == AppGlyph.delete,
    );
    await tester.tap(deleteIcon.first);
    expect(deleted.single.id, 'a');
  });

  testWidgets('书签面板空态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkPanel(
            bookmarks: const <ReaderBookmark>[],
            onSelect: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('还没有书签'), findsOneWidget);
  });
}
