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
  testWidgets('书签面板：标题与页面文字分行，不显示页码和时间', (tester) async {
    final selected = <ReaderBookmark>[];
    final deleted = <ReaderBookmark>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkPanel(
            bookmarks: <ReaderBookmark>[
              _bookmark('a', '第 2 章 · 第 1 页', spine: 1),
              _bookmark('b', '第 5 章 · 第 3 页 · 页面正文里的一句话', spine: 4),
            ],
            onSelect: selected.add,
            onDelete: deleted.add,
          ),
        ),
      ),
    );

    expect(find.text('第 2 章'), findsOneWidget);
    expect(find.text('页面正文里的一句话'), findsOneWidget);
    expect(find.textContaining('第 1 页'), findsNothing);
    expect(find.textContaining('2026-01-01'), findsNothing);
    // 相邻书签之间有分隔线。
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Divider),
      ),
      findsOneWidget,
    );

    // 书签图标相对整行垂直居中。
    final row = tester.getRect(
      find.byKey(const ValueKey<String>('bookmark-row-a')),
    );
    final icon = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('bookmark-row-a')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.glyph == AppGlyph.bookmark,
        ),
      ),
    );
    expect(icon.center.dy, closeTo(row.center.dy, .01));

    await tester.tap(find.text('第 5 章'));
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
