import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/selection/selection_menu.dart';

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
      expect(forward.start.charOffset, lessThanOrEqualTo(forward.end.charOffset));
      expect(backward.start.charOffset, forward.start.charOffset);
      expect(backward.end.charOffset, forward.end.charOffset);
    });

    test('长按选词：结果非空且包含命中字符', () {
      final page = _page('一二三四五六七八九十');
      final boxes = TextHitTester.lineBoxes(page);
      final hit = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.left + boxes.first.rect.width * 0.45,
            boxes.first.rect.center.dy),
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
      expect(geometry.startHandle.dx, lessThanOrEqualTo(geometry.endHandle.dx + 200));
    });

    test('charAt 越界坐标钳制到页内', () {
      final page = _page('abcdefghij');
      final hit = SelectionOps.charAt(page, const Offset(-500, -500));
      expect(hit.charOffset, 0);
      expect(hit.lineIndex, 0);
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
        TextHitTester.hitTest(page, Offset(boxes.first.rect.left + 1,
            boxes.first.rect.center.dy))!,
        TextHitTester.hitTest(page, Offset(boxes[1].rect.left + 40,
            boxes[1].rect.center.dy))!,
      );
      final text = SelectionOps.textOf(page, selection);
      expect(text.length, greaterThan(boxes.first.text.length));
      expect(text.contains(' '), isFalse);
    });

    testWidgets('菜单渲染且动作可点击', (tester) async {
      final page = _page('abcdefghij');
      final boxes = TextHitTester.lineBoxes(page);
      final selection = ReaderSelection.normalized(
        TextHitTester.hitTest(page, Offset(boxes.first.rect.left + 10,
            boxes.first.rect.center.dy))!,
        TextHitTester.hitTest(page, Offset(boxes.first.rect.left + 60,
            boxes.first.rect.center.dy))!,
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
      expect(find.byKey(const ValueKey<String>('selection-menu')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('selection-action-copy')));
      expect(copied, isTrue);

      // 菜单不遮挡选区（上方空间不足时翻到下方）。
      final menuRect = tester.getRect(
        find.byKey(const ValueKey<String>('selection-menu')),
      );
      expect(
        menuRect.overlaps(anchor),
        isFalse,
        reason: '菜单不得覆盖选区',
      );
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
        TextHitTester.hitTest(page, Offset(boxes.first.rect.left + 2,
            boxes.first.rect.center.dy))!,
        TextHitTester.hitTest(page, Offset(boxes.first.rect.left + 40,
            boxes.first.rect.center.dy))!,
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
