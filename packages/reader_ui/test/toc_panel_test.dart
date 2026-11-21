import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/panels/toc_panel.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';

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
  for (final (width, scale) in [(360.0, 1.0), (320.0, 1.5)]) {
    testWidgets('目录页头在宽度$width、字号倍率$scale下完整显示时间并统一颜色', (tester) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: TocPanel(
              entries: [
                for (var index = 0; index < 1515; index++)
                  _entry('第$index章', index),
              ],
              currentSpineIndex: 0,
              readingDuration: const AlwaysStoppedAnimation(
                Duration(hours: 2, minutes: 3),
              ),
              onSelect: (_) {},
            ),
          ),
        ),
      );
      final time = find.byKey(const ValueKey('toc-reading-duration'));
      final count = find.text('共 1515 章');
      expect(
        tester.renderObject<RenderParagraph>(time).didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<Text>(time).style, tester.widget<Text>(count).style);
      for (final key in [
        'toc-expand-all',
        'toc-collapse-all',
        'toc-locate-current',
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(key))), const Size(44, 44));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('累计阅读按整分钟更新并在一小时后显示小时', (tester) async {
    final duration = ValueNotifier(const Duration(seconds: 59));
    addTearDown(duration.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TocPanel(
            entries: [_entry('第一章', 0)],
            currentSpineIndex: 0,
            onSelect: (_) {},
            readingDuration: duration,
          ),
        ),
      ),
    );
    expect(find.text('累计阅读 0 分钟'), findsOneWidget);
    duration.value = const Duration(minutes: 1);
    await tester.pump();
    expect(find.text('累计阅读 1 分钟'), findsOneWidget);
    duration.value = const Duration(minutes: 61, seconds: 59);
    await tester.pump();
    expect(find.text('累计阅读 1 小时 1 分钟'), findsOneWidget);
    expect(find.text('共 1 章'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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

      expect(find.text('累计阅读 0 分钟'), findsOneWidget);
      expect(find.text('共 3 章'), findsOneWidget);
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('2.1'), findsOneWidget);

      // 当前章高亮：第二章 selected。
      final current = tester.widget<ListTile>(
        find.ancestor(of: find.text('第二章'), matching: find.byType(ListTile)),
      );
      expect(current.selected, isTrue);
      final theme = Theme.of(tester.element(find.byType(TocPanel)));
      expect(current.selectedTileColor, ReaderDrawerStyle.selectedRowOf(theme));
      expect(current.selectedTileColor, isNot(current.tileColor));
      expect(
        tester.widget<Text>(find.text('第二章')).style?.fontWeight,
        FontWeight.w600,
      );
      final other = tester.widget<ListTile>(
        find.ancestor(of: find.text('第一章'), matching: find.byType(ListTile)),
      );
      expect(other.selected, isFalse);

      // 子级缩进比带圆点的章节标题多 36。
      final childPadding =
          tester
                  .widget<ListTile>(
                    find.ancestor(
                      of: find.text('2.1'),
                      matching: find.byType(ListTile),
                    ),
                  )
                  .contentPadding
              as EdgeInsets;
      final parentPadding =
          tester
                  .widget<ListTile>(
                    find.ancestor(
                      of: find.text('第二章'),
                      matching: find.byType(ListTile),
                    ),
                  )
                  .contentPadding
              as EdgeInsets;
      expect(childPadding.left - parentPadding.left, 36);
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('toc-row-1-第二章')))
            .height,
        40,
      );
      final chapterTitle = tester.widget<Text>(find.text('第二章'));
      expect(chapterTitle.style?.fontSize, 14);
      expect(chapterTitle.style?.fontFamily, 'serif');
      final leafTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('第一章'), matching: find.byType(ListTile)),
      );
      expect(leafTile.trailing, isNull);

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
            _entry('1.1', 1, children: <TocEntry>[_entry('1.1.1', 2)]),
          ],
        ),
        _entry('第二章', 3, children: <TocEntry>[_entry('2.1', 4)]),
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
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppIcon && widget.glyph == AppGlyph.chevronDown,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('toc-toggle-0-第一章')));
      await tester.pump();
      expect(find.text('1.1'), findsNothing);
      expect(find.text('共 5 章'), findsOneWidget);
      expect(selected, isEmpty);

      await tester.tap(find.byKey(const ValueKey<String>('toc-toggle-0-第一章')));
      await tester.pump();
      expect(find.text('1.1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('toc-toggle-1-1.1')));
      await tester.pump();
      expect(find.text('1.1.1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('toc-collapse-all')));
      await tester.pump();
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('1.1'), findsNothing);
      expect(find.text('1.1.1'), findsNothing);
      expect(find.text('第二章'), findsOneWidget);
      expect(find.text('2.1'), findsNothing);
      expect(find.text('共 5 章'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('toc-expand-all')));
      await tester.pump();
      expect(find.text('1.1'), findsOneWidget);
      expect(find.text('1.1.1'), findsOneWidget);
      expect(find.text('2.1'), findsOneWidget);
      expect(find.text('共 5 章'), findsOneWidget);
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

      controller.jumpTo(0);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('toc-locate-current')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const ValueKey<String>('toc-row-20-第21章')))
            .center
            .dy,
        closeTo(viewport.center.dy, 0.5),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('收起全部会收起当前卷，回到当前章再展开父级路径并高亮子章', (tester) async {
      final entries = <TocEntry>[
        _entry(
          '第一章',
          0,
          children: <TocEntry>[
            _entry('1.1', 1, children: <TocEntry>[_entry('1.1.1', 2)]),
          ],
        ),
        _entry('第二章', 3, children: <TocEntry>[_entry('2.1', 4)]),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocPanel(
              entries: entries,
              currentSpineIndex: 2,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('toc-collapse-all')));
      await tester.pump();

      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('1.1'), findsNothing);
      expect(find.text('1.1.1'), findsNothing);
      expect(find.text('第二章'), findsOneWidget);
      expect(find.text('2.1'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('toc-locate-current')));
      await tester.pumpAndSettle();
      expect(find.text('1.1'), findsOneWidget);
      expect(find.text('1.1.1'), findsOneWidget);
      final current = tester.widget<ListTile>(
        find.ancestor(of: find.text('1.1.1'), matching: find.byType(ListTile)),
      );
      expect(current.selected, isTrue);
      expect(
        current.selectedTileColor,
        ReaderDrawerStyle.selectedRowOf(
          Theme.of(tester.element(find.byType(TocPanel))),
        ),
      );
    });

    testWidgets('同一 spine 按 CFI 定位当前顶层目录项', (tester) async {
      final entries = <TocEntry>[
        _entry(
          '第一节',
          0,
          cfi: 'epubcfi(/6/2!/4/2)',
          children: <TocEntry>[_entry('第一节子目', 0, cfi: 'epubcfi(/6/2!/4/4)')],
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
