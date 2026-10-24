import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';

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
  });
}
