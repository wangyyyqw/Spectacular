import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/selection/selection_menu.dart';
import 'package:reader_ui/theme/reader_theme.dart';

const _menuLabels = <String, String>{
  'copy': '复制',
  'mark': '划线',
  'thought': '想法',
  'decoration': '装饰',
  'dictionary': '词典',
  'select-all': '全选',
};

List<SelectionAction> _menuActions(ValueChanged<String> onTap) => [
  for (final entry in _menuLabels.entries)
    SelectionAction(
      id: entry.key,
      label: entry.value,
      onTap: () => onTap(entry.key),
    ),
];

Future<void> _pumpMenu(
  WidgetTester tester,
  SelectionMenu menu, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(menu.bounds);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Scaffold(body: Stack(children: [menu])),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _page(String text, {double maxWidth = 160}) {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: _style(),
    maxWidth: maxWidth,
  );
  final block = PageBlock(layout: layout, style: _style());
  final slice = PageBlockSlice(
    block: block,
    startLine: 0,
    endLine: layout.lineCount,
    height: layout.height,
  );
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: <PageBlockSlice>[slice],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 8,
  );
}

PageContent _verticalPage(String text, {double contentWidth = 300}) {
  final style = ComputedStyle(const <String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': 'Ahem',
    'writing-mode': 'vertical-rl',
  });
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: contentWidth,
  );
  final block = PageBlock.styled(
    layout: layout,
    style: style,
    containingWidth: contentWidth,
  );
  final slice = PageBlockSlice(
    block: block,
    startLine: 0,
    endLine: layout.lineCount,
    height: layout.height,
  );
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: <PageBlockSlice>[slice],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 8,
  );
}

void main() {
  group('选区归一与几何（P4-15）', () {
    test('normalized 保证起点在前', () {
      final page = _page('abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      final hitA = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 2, boxes.first.rect.center.dy),
      )!;
      final hitB = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 60, boxes.first.rect.center.dy),
      )!;
      final forward = ReaderSelection.normalized(hitA, hitB);
      final backward = ReaderSelection.normalized(hitB, hitA);
      expect(
        forward.start.charOffset,
        lessThanOrEqualTo(forward.end.charOffset),
      );
      expect(backward.start.charOffset, forward.start.charOffset);
      expect(backward.end.charOffset, forward.end.charOffset);
    });

    test('长按选词：结果非空且包含命中字符', () {
      final page = _page('一二三四五六七八九十');
      final boxes = TextHitTester.lineBoxes(page);
      final hit = TextHitTester.hitTest(
        page,
        Offset(
          boxes.first.rect.left + boxes.first.rect.width * 0.45,
          boxes.first.rect.center.dy,
        ),
      )!;
      final selection = SelectionOps.wordAt(page, hit);
      expect(selection.start.charOffset, lessThan(selection.end.charOffset));
      expect(selection.start.charOffset, lessThanOrEqualTo(hit.charOffset));
      expect(selection.end.charOffset, greaterThanOrEqualTo(hit.charOffset));
    });

    test('选区矩形覆盖命中行且高度约 1.1 倍行高', () {
      final page = _page('abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      final start = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 1, boxes.first.rect.center.dy),
      )!;
      final end = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 80, boxes.first.rect.center.dy),
      )!;
      final selection = ReaderSelection.normalized(start, end);
      final geometry = SelectionOps.geometryOf(page, selection);
      expect(geometry.lineRects, isNotEmpty);
      final rect = geometry.lineRects.first;
      expect(rect.height, closeTo(boxes.first.rect.height * 1.1, 0.5));
      expect(rect.top, lessThan(boxes.first.rect.center.dy));
      expect(rect.bottom, greaterThan(boxes.first.rect.center.dy));
    });

    test('跨行选区：矩形数等于覆盖行数，起止手柄落在行边界', () {
      final page = _page('0123456789abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes.length, greaterThanOrEqualTo(2));
      final start = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 4, boxes.first.rect.center.dy),
      )!;
      final end = TextHitTester.hitTest(
        page,
        Offset(boxes[1].rect.left + 40, boxes[1].rect.center.dy),
      )!;
      final selection = ReaderSelection.normalized(start, end);
      final geometry = SelectionOps.geometryOf(page, selection);
      expect(geometry.lineRects.length, greaterThanOrEqualTo(2));
      expect(geometry.startHandle.dy, boxes.first.rect.top);
      expect(geometry.endHandle.dy, boxes[1].rect.bottom);
      expect(
        geometry.startHandle.dx,
        lessThanOrEqualTo(geometry.endHandle.dx + 200),
      );
    });

    test('charAt 越界坐标钳制到页内', () {
      final page = _page('abcdefghij');
      final hit = SelectionOps.charAt(page, const Offset(-500, -500));
      expect(hit.charOffset, 0);
      expect(hit.lineIndex, 0);
    });

    test('竖排选区沿列纵向展开，手柄落在列首尾', () {
      final page = _verticalPage('天地玄黄');
      final box = TextHitTester.lineBoxes(page).single;
      final start = TextHitTester.hitTest(
        page,
        Offset(box.rect.center.dx, box.rect.top + 1),
      )!;
      final end = TextHitTester.hitTest(
        page,
        Offset(box.rect.center.dx, box.rect.bottom - 1),
      )!;
      final selection = ReaderSelection.normalized(start, end);
      final geometry = SelectionOps.geometryOf(page, selection);

      expect(geometry.lineRects, hasLength(1));
      final rect = geometry.lineRects.single;
      expect(rect.width, closeTo(box.rect.width, 0.01));
      expect(rect.top, box.rect.top);
      expect(rect.bottom, greaterThan(box.rect.top + box.rect.height * 0.5));
      expect(geometry.startHandle.dy, box.rect.top);
      expect(geometry.endHandle.dy, box.rect.bottom);
    });
  });

  group('选句与菜单（P4-16）', () {
    test('三击选句：中文长句边界正确（含跨软换行的句子）', () {
      final page = _page('他说：“你来了。”我回答：“是的。”');
      final boxes = TextHitTester.lineBoxes(page);
      final hit = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 8, boxes.first.rect.center.dy),
      )!;
      final selection = SelectionOps.sentenceAt(page, hit);
      final text = SelectionOps.textOf(page, selection);
      expect(text, '他说：“你来了。”');
    });

    test('选区文本拼接：跨行中文不加空格', () {
      final page = _page('一二三四五六七八九十一二三四五六七八九十');
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes.length, greaterThanOrEqualTo(2));
      final selection = ReaderSelection.normalized(
        TextHitTester.hitTest(
          page,
          Offset(boxes.first.rect.left + 1, boxes.first.rect.center.dy),
        )!,
        TextHitTester.hitTest(
          page,
          Offset(boxes[1].rect.left + 40, boxes[1].rect.center.dy),
        )!,
      );
      final text = SelectionOps.textOf(page, selection);
      expect(text.length, greaterThan(boxes.first.text.length));
      expect(text.contains(' '), isFalse);
    });

    testWidgets('菜单渲染且动作可点击', (tester) async {
      final page = _page('abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      final selection = ReaderSelection.normalized(
        TextHitTester.hitTest(
          page,
          Offset(boxes.first.rect.left + 10, boxes.first.rect.center.dy),
        )!,
        TextHitTester.hitTest(
          page,
          Offset(boxes.first.rect.left + 60, boxes.first.rect.center.dy),
        )!,
      );
      final anchor = SelectionOps.boundsOf(page, selection);
      var copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SelectionMenu(
                  actions: <SelectionAction>[
                    SelectionAction(
                      id: 'copy',
                      label: '复制',
                      onTap: () => copied = true,
                    ),
                    SelectionAction(id: 'dismiss', label: '取消', onTap: () {}),
                  ],
                  anchor: anchor,
                  bounds: const Size(300, 400),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('selection-menu')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('selection-action-copy')),
      );
      expect(copied, isTrue);

      // 菜单不遮挡选区（上方空间不足时翻到下方）。
      final menuRect = tester.getRect(
        find.byKey(const ValueKey<String>('selection-menu')),
      );
      expect(menuRect.overlaps(anchor), isFalse, reason: '菜单不得覆盖选区');
    });

    testWidgets('选区完全离开视口时不显示浮动菜单', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SelectionMenu(
                  actions: <SelectionAction>[
                    SelectionAction(id: 'copy', label: '复制', onTap: () {}),
                  ],
                  anchor: const Rect.fromLTWH(20, -40, 100, 20),
                  bounds: const Size(300, 400),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('selection-menu')),
        findsNothing,
      );
    });

    testWidgets('日夜正文下均显示紧凑深色单行菜单，图标在文字上方', (tester) async {
      for (final theme in [ReaderTheme.white, ReaderTheme.black]) {
        final selected = <String>[];
        await _pumpMenu(
          tester,
          SelectionMenu(
            actions: _menuActions(selected.add),
            readerTheme: theme,
            anchor: const Rect.fromLTWH(20, 180, 120, 24),
            bounds: const Size(360, 600),
          ),
        );
        final menu = find.byKey(const ValueKey<String>('selection-menu'));
        final material = tester.widget<Material>(menu);
        expect(material.borderRadius, BorderRadius.circular(12));
        expect(material.clipBehavior, Clip.antiAlias);
        expect(tester.getSize(menu).width, lessThanOrEqualTo(300));
        expect(tester.getSize(menu).height, lessThanOrEqualTo(60));
        final scheme = Theme.of(tester.element(menu)).colorScheme;
        expect(scheme.surface, const Color(0xFF282B31));
        expect(scheme.onSurface, const Color(0xFFF5F5F5));
        final positions = <double>[];
        for (final entry in _menuLabels.entries) {
          final button = find.byKey(ValueKey('selection-action-${entry.key}'));
          final icon = find.descendant(
            of: button,
            matching: find.byType(AppIcon),
          );
          final label = find.descendant(
            of: button,
            matching: find.text(entry.value),
          );
          expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
          expect(
            tester.getBottomLeft(icon).dy,
            lessThan(tester.getTopLeft(label).dy),
          );
          expect(tester.widget<AppIcon>(icon).color, scheme.onSurface);
          expect(tester.widget<AppIcon>(icon).size, 22);
          expect(tester.widget<Text>(label).style?.fontSize, 12);
          positions.add(tester.getCenter(button).dy);
          await tester.tap(button);
        }
        expect(positions.toSet(), hasLength(1));
        expect(selected, _menuLabels.keys.toList());
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('窄屏大字号不换行或溢出，横向滑动可点击末项', (tester) async {
      final selected = <String>[];
      await _pumpMenu(
        tester,
        SelectionMenu(
          actions: _menuActions(selected.add),
          anchor: const Rect.fromLTWH(20, 180, 120, 24),
          bounds: const Size(280, 500),
        ),
        textScaler: const TextScaler.linear(2),
      );
      final menu = find.byKey(const ValueKey<String>('selection-menu'));
      final scroll = find.byKey(
        const ValueKey<String>('selection-menu-scroll'),
      );
      expect(tester.getSize(menu).width, lessThanOrEqualTo(256));
      expect(tester.getSize(menu).height, greaterThan(70));
      expect(
        find.byKey(const ValueKey('selection-action-copy')).hitTestable(),
        findsOneWidget,
      );
      final positions = [
        for (final id in _menuLabels.keys)
          tester.getCenter(find.byKey(ValueKey('selection-action-$id'))).dy,
      ];
      expect(positions.toSet(), hasLength(1));
      await tester.drag(scroll, const Offset(-400, 0));
      await tester.pumpAndSettle();
      final selectAll = find.byKey(
        const ValueKey<String>('selection-action-select-all'),
      );
      expect(
        tester.getRect(menu).contains(tester.getCenter(selectAll)),
        isTrue,
      );
      await tester.tap(selectAll);
      expect(selected, ['select-all']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('靠近页首或页尾时菜单留在视口内且不遮挡选区', (tester) async {
      for (final anchor in [
        const Rect.fromLTWH(20, 4, 120, 24),
        const Rect.fromLTWH(20, 560, 120, 24),
      ]) {
        await _pumpMenu(
          tester,
          SelectionMenu(
            actions: _menuActions((_) {}),
            anchor: anchor,
            bounds: const Size(360, 600),
          ),
        );
        final rect = tester.getRect(
          find.byKey(const ValueKey<String>('selection-menu')),
        );
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(348));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(600));
        expect(rect.overlaps(anchor), isFalse);
      }
    });

    testWidgets('墨水屏菜单保留黑白阅读配色', (tester) async {
      await _pumpMenu(
        tester,
        SelectionMenu(
          actions: _menuActions((_) {}),
          inkMode: true,
          readerTheme: const ReaderTheme(
            id: 'ink',
            name: '墨水屏',
            background: Colors.white,
            text: Colors.black,
          ),
          anchor: const Rect.fromLTWH(20, 180, 120, 24),
          bounds: const Size(360, 600),
        ),
      );
      final menu = find.byKey(const ValueKey<String>('selection-menu'));
      final scheme = Theme.of(tester.element(menu)).colorScheme;
      expect(scheme.surface, Colors.white);
      expect(scheme.onSurface, Colors.black);
      expect(tester.takeException(), isNull);
    });
  });

  group('选区层手柄（P4-15）', () {
    testWidgets('选区入场淡入、手柄落位，拖拽期间不重播动画', (tester) async {
      final page = _page('abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      final start = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 20, boxes.first.rect.center.dy),
      )!;
      final end = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 80, boxes.first.rect.center.dy),
      )!;
      var selection = ReaderSelection.normalized(start, end);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                height: 400,
                child: SelectionLayer(
                  page: page,
                  pageIndex: 0,
                  selection: selection,
                  onChanged: (next) => setState(() => selection = next),
                ),
              ),
            ),
          ),
        ),
      );

      final fadeFinder = find.byKey(
        const ValueKey<String>('selection-entrance'),
      );
      final scaleFinder = find.byKey(
        const ValueKey<String>('selection-handle-end-scale'),
      );
      expect(tester.widget<FadeTransition>(fadeFinder).opacity.value, 0);
      expect(
        tester.widget<ScaleTransition>(scaleFinder).scale.value,
        closeTo(0.72, 0.001),
      );

      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<FadeTransition>(fadeFinder).opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FadeTransition>(fadeFinder).opacity.value, 1);
      expect(tester.widget<ScaleTransition>(scaleFinder).scale.value, 1);

      final before = selection.end.charOffset;
      await tester.drag(
        find.byKey(const ValueKey<String>('selection-handle-end')),
        const Offset(30, 0),
      );
      await tester.pump();
      expect(selection.end.charOffset, greaterThan(before));
      expect(tester.widget<FadeTransition>(fadeFinder).opacity.value, 1);
      expect(tester.widget<ScaleTransition>(scaleFinder).scale.value, 1);
    });

    testWidgets('渲染两个手柄并能拖拽改变选区', (tester) async {
      final page = _page('abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      final start = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 20, boxes.first.rect.center.dy),
      )!;
      final end = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + 100, boxes.first.rect.center.dy),
      )!;
      var selection = ReaderSelection.normalized(start, end);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                height: 400,
                child: SelectionLayer(
                  page: page,
                  pageIndex: 0,
                  selection: selection,
                  onChanged: (next) => setState(() => selection = next),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('selection-handle-start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('selection-handle-end')),
        findsOneWidget,
      );

      final before = selection.end.charOffset;
      final handle = find.byKey(const ValueKey<String>('selection-handle-end'));
      await tester.drag(handle, const Offset(40, 0));
      await tester.pump();
      expect(selection.end.charOffset, greaterThan(before));
      expect(
        selection.end.charOffset,
        lessThanOrEqualTo(selection.end.lineBox.text.length),
        reason: '不越出行尾',
      );
    });

    testWidgets('连续拖拽 20 次（含越界坐标）选区始终在页内', (tester) async {
      final page = _page('0123456789abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      var selection = ReaderSelection.normalized(
        TextHitTester.hitTest(
          page,
          Offset(boxes.first.rect.left + 2, boxes.first.rect.center.dy),
        )!,
        TextHitTester.hitTest(
          page,
          Offset(boxes.first.rect.left + 40, boxes.first.rect.center.dy),
        )!,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 300,
                height: 400,
                child: SelectionLayer(
                  page: page,
                  pageIndex: 0,
                  selection: selection,
                  onChanged: (next) => setState(() => selection = next),
                ),
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 20; i++) {
        final handle = find.byKey(
          ValueKey<String>(
            i.isEven ? 'selection-handle-end' : 'selection-handle-start',
          ),
        );
        final dx = i.isEven ? 30.0 : -30.0;
        await tester.drag(handle, Offset(dx, i.isEven ? 60 : -60));
        await tester.pump();
        final geometry = SelectionOps.geometryOf(page, selection);
        for (final rect in geometry.lineRects) {
          expect(rect.top, greaterThanOrEqualTo(-0.5), reason: '不越页顶');
          expect(rect.bottom, lessThanOrEqualTo(400 + 0.5), reason: '不越页底');
        }
        expect(selection.start.sliceIndex, 0);
        expect(selection.end.sliceIndex, 0);
      }
    });
  });
}
