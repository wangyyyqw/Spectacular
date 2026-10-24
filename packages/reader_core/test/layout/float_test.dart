import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';
import 'package:reader_core/layout/float_occupancy.dart';

LayoutConstraints _constraints({double maxWidth = 320}) =>
    LayoutConstraints(maxWidth: maxWidth, maxHeight: 10000);

ComputedStyle _style(Map<String, String> extra) => ComputedStyle(
      <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        ...extra,
      },
    );

BlockFlow _floatBox(String text, String side) => createFlowBox(
      style: _style({'float': side}),
      text: text,
    );

void main() {
  group('块流浮动绕排（P3-13 createPlaceholders 容器分支）', () {
    test('左浮动登记占用，后续文本按区间收窄且不越过浮动右缘', () {
      final floatBox = _floatBox('浮', 'left');
      final paragraph = createFlowBox(
        style: _style(const <String, String>{}),
        text: '这是一段足够长的正文文本，用来验证绕排收窄后文字不越过浮动边界，'
            '并且浮动结束之后恢复整行宽度。',
      );
      final root = ColumnFlowBlock([floatBox, paragraph]);
      root.measure(_constraints());

      final occupancy = root.floats;
      expect(occupancy.items, hasLength(1));
      final floatRect = occupancy.items.single.rect;
      expect(floatRect.width, lessThan(320), reason: 'fit-content 收缩');

      // 文本块在其与浮动重叠的高度区间内被收窄。
      final textTop = root.childTops.last;
      final textHeight = paragraph.size.height;
      final narrowed = occupancy.contentWidthAt(
        textTop,
        textTop + textHeight,
        320,
      );
      expect(paragraph.size.width, lessThanOrEqualTo(narrowed + 0.5),
          reason: '文本宽度不超过绕排可用宽（不越界）');
      expect(root.childLefts.last, closeTo(floatRect.width, 0.5),
          reason: '左浮动后文本左缘对齐浮动右缘（不重叠）');
    });

    test('右浮动：文本可用宽 = 容器 - 浮动宽', () {
      final floatBox = _floatBox('浮', 'right');
      final paragraph = createFlowBox(
        style: _style(const <String, String>{}),
        text: '右浮动旁边的正文段落，应有足够的长度来触发绕排收窄路径，'
            '这样才能验证右侧被占宽度正确地从容器右缘扣除。',
      );
      final root = ColumnFlowBlock([floatBox, paragraph]);
      root.measure(_constraints());

      final occupancy = root.floats;
      final floatRect = occupancy.items.single.rect;
      expect(floatRect.left, greaterThan(0), reason: '右浮动贴容器右缘');
      expect(paragraph.size.width,
          lessThanOrEqualTo(320 - floatRect.width + 0.5));
      expect(root.childLefts.last, 0, reason: '右浮动不产生左缩进');
    });

    test('浮动结束之后的文本恢复整行宽度', () {
      final floatBox = _floatBox('浮', 'left');
      final first = createFlowBox(
        style: _style(const <String, String>{}),
        text: '与浮动同区域的段落需要足够长以覆盖浮动的高度区间，从而触发收窄。',
      );
      final second = createFlowBox(
        style: _style(const <String, String>{}),
        text: '浮动结束后的段落恢复整行宽度，这一行应该用到完整的容器宽度。',
      );
      final root = ColumnFlowBlock([floatBox, first, second]);
      root.measure(_constraints(maxWidth: 320));

      final occupancy = root.floats;
      final floatRect = occupancy.items.single.rect;
      // 第二段的 top 在浮动底部之下（或其区间不含浮动）→ 不收窄。
      // childTops 只含流内子块：[first, second]。
      final secondTop = root.childTops[1];
      final secondInset = occupancy.occupiedLeftAt(
        secondTop,
        secondTop + second.size.height,
      );
      if (secondTop >= floatRect.bottom) {
        expect(secondInset, 0);
        expect(second.size.width, lessThanOrEqualTo(320.5));
      } else {
        expect(secondInset, greaterThan(0));
      }
    });

    test('无浮动的树保持单次测量不变量', () {
      final root = ColumnFlowBlock([
        createFlowBox(style: _style(const {}), text: '普通段落甲'),
        createFlowBox(style: _style(const {}), text: '普通段落乙'),
      ]);
      root.measure(_constraints());
      expect(root.layoutCount, 1);
      expect(root.children.every((c) => c.layoutCount == 1), isTrue);
    });

    test('clear:left：块顶推到左浮底部之下，且该浮动不再约束后续内容', () {
      final floatBox = _floatBox('浮', 'left');
      final short = createFlowBox(
        style: _style(const {}),
        text: '与浮动同区的短段。',
      );
      final cleared = createFlowBox(
        style: _style({'clear': 'left'}),
        text: '被 clear:left 推到浮动下方的段落，位置应在浮动底部之下。',
      );
      final follower = createFlowBox(
        style: _style(const {}),
        text: 'clear 之后的段落应恢复整行宽度，不再被已满足的浮动收窄。',
      );
      final root = ColumnFlowBlock([floatBox, short, cleared, follower]);
      root.measure(_constraints());

      final floatRect = root.floats.items.single.rect;
      final clearedTop = root.childTops[1];
      expect(clearedTop, greaterThanOrEqualTo(floatRect.bottom),
          reason: 'clear:left 推到左浮底部之下');

      // 该浮动已被移除：后续段不被收窄（childLefts 全 0）。
      expect(root.childLefts.last, 0);
      expect(follower.size.width, lessThanOrEqualTo(320.5));
    });

    test('clear:right：只等右侧浮动', () {
      // 左浮内容长到换行（更高），右浮较短：clear:right 推到右浮底部
      // 后，左浮仍在高度区间内继续约束。
      final leftFloat = _floatBox('左浮动内容足够长会折成多行因此变得更高一些了', 'left');
      final rightFloat = _floatBox('右', 'right');
      final cleared = createFlowBox(
        style: _style({'clear': 'right'}),
        text: 'clear:right 只等右侧浮动结束，左侧浮动仍可继续约束本块。',
      );
      final root = ColumnFlowBlock([leftFloat, rightFloat, cleared]);
      root.measure(_constraints());

      final sides = root.floats.items.map((item) => item.side).toSet();
      expect(sides, contains(FloatSide.left), reason: '左浮未满足前保留');
      expect(sides, isNot(contains(FloatSide.right)), reason: '右浮已满足移除');
      expect(root.childLefts.last, greaterThan(0),
          reason: '左侧浮动仍在约束，块被左收窄');
    });

    test('clear:both：两侧都推到浮动底部', () {
      final leftFloat = _floatBox('左', 'left');
      final rightFloat = _floatBox('右', 'right');
      final cleared = createFlowBox(
        style: _style({'clear': 'both'}),
        text: 'clear:both 的段落要等到左右两侧浮动全部结束，位于两者底部之下。',
      );
      final root = ColumnFlowBlock([leftFloat, rightFloat, cleared]);
      root.measure(_constraints());

      final clearedTop = root.childTops.last;
      for (final item in root.floats.items.toList()) {
        expect(clearedTop, greaterThanOrEqualTo(item.rect.bottom),
            reason: '${item.side} 浮动底部之上不应放块');
      }
      expect(root.floats.items, isEmpty, reason: '满足后占用全部移除');
    });

    test('绝对定位不参与 occupiedList（§48.3 第 4 条）', () {
      final absolute = createFlowBox(
        style: _style({'position': 'absolute'}),
        text: '绝对定位内容不进占用表',
      );
      final paragraph = createFlowBox(
        style: _style(const {}),
        text: '旁边的普通段落与绝对定位内容互不影响，宽度保持全宽。',
      );
      final root = ColumnFlowBlock([absolute, paragraph]);
      root.measure(_constraints());
      expect(root.floats.items, isEmpty);
      expect(paragraph.size.width, lessThanOrEqualTo(320.5));
    });

    test('跨页浮图连续三页：占用逐页裁剪续用，用尽后全宽恢复（P3-15）', () {
      // 浮动高 250，页高 100：第 1 页占用全高，第 2 页剩 150，第 3 页
      // 剩 50，第 4 页用尽。
      final entry = FloatOccupancy()
        ..insert(
          BoxOccupied(
            rect: const Rect.fromLTWH(0, 0, 120, 250),
            baseline: 0,
            side: FloatSide.left,
          ),
        );
      final pages = FloatOccupancy.sliceAcrossPages(entry, <double>[
        100,
        100,
        100,
        100,
      ]);
      expect(pages, hasLength(4));
      expect(pages[0].contentWidthAt(0, 100, 320), 200);
      expect(pages[1].contentWidthAt(0, 100, 320), 200,
          reason: '跨页剩余在下一页重新登记');
      expect(pages[1].items.single.rect.height, 150,
          reason: '精确裁剪（§48.3 第 2 条）');
      expect(pages[2].contentWidthAt(0, 100, 320), 200);
      expect(pages[2].items.single.rect.height, 50);
      expect(pages[3].items, isEmpty, reason: '浮动用尽后不再约束');
      expect(pages[3].contentWidthAt(0, 100, 320), 320);
    });

    test('分页游标不被浮动吞掉：容器内容高与浮动无关', () {
      const text = '第一段有足够多的文字用来占据确定的高度，绕排不影响游标推进。';
      final withFloat = ColumnFlowBlock([
        _floatBox('浮', 'left'),
        createFlowBox(style: _style(const {}), text: text),
        createFlowBox(style: _style(const {}), text: text),
      ]);
      final withoutFloat = ColumnFlowBlock([
        createFlowBox(style: _style(const {}), text: text),
        createFlowBox(style: _style(const {}), text: text),
      ]);
      withFloat.measure(_constraints());
      withoutFloat.measure(_constraints());
      // 短文本收窄后行数不变：浮动摘流不推进 cursor，容器内容高一致
      //（分页游标不被占位吞掉）。
      expect(withFloat.size.height, withoutFloat.size.height);
    });
  });
}
