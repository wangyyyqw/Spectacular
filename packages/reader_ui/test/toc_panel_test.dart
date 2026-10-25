import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_session.dart';

TocEntry _entry(String title, int spineIndex, {List<TocEntry> children = const []}) =>
    TocEntry(title: title, spineIndex: spineIndex, children: children);

void main() {
  group('目录展开（P4-11）', () {
    test('深度优先展开并标注层级', () {
      final rows = flattenToc(<TocEntry>[
        _entry('第一章', 0),
        _entry(
          '第二章',
          1,
          children: <TocEntry>[
            _entry('2.1 小节', 1),
            _entry('2.2 小节', 2, children: <TocEntry>[_entry('2.2.1', 2)]),
          ],
        ),
      ]);
      expect(rows.map((row) => row.entry.title), <String>[
        '第一章',
        '第二章',
        '2.1 小节',
        '2.2 小节',
        '2.2.1',
      ]);
      expect(rows.map((row) => row.depth), <int>[1, 1, 2, 2, 3]);
    });
  });

  group('目录面板', () {
    testWidgets('层级缩进、当前章高亮、点击回调', (tester) async {
      final selected = <TocEntry>[];
      final entries = <TocEntry>[
        _entry('第一章', 0),
        _entry('第二章', 1, children: <TocEntry>[_entry('2.1', 2)]),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocPanel(
              entries: entries,
              currentSpineIndex: 1,
              onSelect: selected.add,
            ),
          ),
        ),
      );

      expect(find.text('目录'), findsOneWidget);
      expect(find.text('共 3 章'), findsOneWidget);
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('2.1'), findsOneWidget);

      // 当前章高亮：第二章 selected。
      final current = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('第二章'),
          matching: find.byType(ListTile),
        ),
      );
      expect(current.selected, isTrue);
      final other = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('第一章'),
          matching: find.byType(ListTile),
        ),
      );
      expect(other.selected, isFalse);

      // 子级缩进比父级多 16。
      final childPadding =
          tester.widget<ListTile>(
            find.ancestor(of: find.text('2.1'), matching: find.byType(ListTile)),
          ).contentPadding as EdgeInsets;
      final parentPadding =
          tester.widget<ListTile>(
            find.ancestor(
              of: find.text('第二章'),
              matching: find.byType(ListTile),
            ),
          ).contentPadding as EdgeInsets;
      expect(childPadding.left - parentPadding.left, 16);

      await tester.tap(find.text('2.1'));
      expect(selected.single.title, '2.1');
    });

    testWidgets('无目录显示空态', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocPanel(
              entries: const <TocEntry>[],
              currentSpineIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('本书没有目录'), findsOneWidget);
    });
  });
}
