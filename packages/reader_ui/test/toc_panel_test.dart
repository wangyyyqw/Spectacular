import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/reader_session.dart';

TocEntry _entry(
  String title,
  int spineIndex, {
  String? cfi,
  List<TocEntry> children = const [],
}) => TocEntry(
  title: title,
  spineIndex: spineIndex,
  cfi: cfi == null ? null : EpubCfi.parse(cfi),
  children: children,
);

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

    testWidgets('多级目录可折叠，当前分支默认展开', (tester) async {
      final selected = <TocEntry>[];
      final entries = <TocEntry>[
        _entry(
          '第一章',
          0,
          children: <TocEntry>[
            _entry(
              '1.1',
              1,
              children: <TocEntry>[_entry('1.1.1', 2)],
            ),
          ],
        ),
        _entry(
          '第二章',
          3,
          children: <TocEntry>[_entry('2.1', 4)],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocPanel(
              entries: entries,
              currentSpineIndex: 0,
              onSelect: selected.add,
            ),
          ),
        ),
      );

      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('1.1'), findsOneWidget);
      expect(find.text('1.1.1'), findsNothing);
      expect(find.text('第二章'), findsOneWidget);
      expect(find.text('2.1'), findsNothing);
      expect(find.text('共 5 章'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('toc-toggle-0-第一章')),
      );
      await tester.pump();
      expect(find.text('1.1'), findsNothing);
      expect(find.text('共 5 章'), findsOneWidget);
      expect(selected, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('toc-toggle-0-第一章')),
      );
      await tester.pump();
      expect(find.text('1.1'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('toc-toggle-1-1.1')),
      );
      await tester.pump();
      expect(find.text('1.1.1'), findsOneWidget);
    });

    testWidgets('打开时把当前章移到目录中间', (tester) async {
      final controller = ScrollController();
      final entries = <TocEntry>[
        for (var index = 0; index < 40; index += 1)
          _entry('第${index + 1}章', index),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: TocPanel(
                entries: entries,
                currentSpineIndex: 20,
                scrollController: controller,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(controller.offset, greaterThan(0));
      final row = tester.getRect(
        find.byKey(const ValueKey<String>('toc-row-20-第21章')),
      );
      final viewport = tester.getRect(find.byType(ListView));
      expect(row.center.dy, closeTo(viewport.center.dy, 0.5));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('同一 spine 按 CFI 定位当前顶层目录项', (tester) async {
      final entries = <TocEntry>[
        _entry(
          '第一节',
          0,
          cfi: 'epubcfi(/6/2!/4/2)',
          children: <TocEntry>[
            _entry('第一节子目', 0, cfi: 'epubcfi(/6/2!/4/4)'),
          ],
        ),
        _entry('第二节', 0, cfi: 'epubcfi(/6/2!/4/6)'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocPanel(
              entries: entries,
              currentSpineIndex: 0,
              currentCfi: 'epubcfi(/6/2!/4/5)',
              onSelect: (_) {},
            ),
          ),
        ),
      );

      ListTile tileOf(String title) => tester.widget<ListTile>(
        find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      );
      expect(tileOf('第一节').selected, isTrue);
      expect(tileOf('第一节子目').selected, isFalse);
      expect(tileOf('第二节').selected, isFalse);
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
