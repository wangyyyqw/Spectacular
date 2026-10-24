import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';

const _width = 200.0;

ComputedStyle _style([Map<String, String> extra = const <String, String>{}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...extra,
    }, containingWidth: _width);

LayoutConstraints _constraints({
  double maxWidth = _width,
  double maxHeight = 600,
}) => LayoutConstraints(maxWidth: maxWidth, maxHeight: maxHeight);

TextFlowBlock _text(String text, [Map<String, String> extra = const {}]) =>
    TextFlowBlock(text: text, style: _style(extra));

/// Ahem 16px：单字宽 16、行高 24；平台取整差异用 0.01 容差。
void _expectSize(Size actual, double width, double height) {
  expect(actual.width, closeTo(width, 0.01));
  expect(actual.height, closeTo(height, 0.01));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content-box 声明宽决定块宽，padding/border 另计', () {
    final plain = _text('aa', {'width': '100px'});
    _expectSize(plain.measure(_constraints()), 100, 24);
    expect(plain.layout?.maxWidth, 100);
    expect(plain.boxModel?.contentWidth, 100);

    final decorated = _text('aa', {
      'width': '100px',
      'padding': '10px',
      'border': '4px solid',
    });
    // 内容宽 100，边框盒宽 100 + 28。
    _expectSize(decorated.measure(_constraints()), 128, 52);
    expect(decorated.layout?.maxWidth, 100);
  });

  test('border-box 声明宽含 padding/border，内容宽被压缩并折行', () {
    final block = _text('aaaaaaaaaa', {
      'box-sizing': 'border-box',
      'width': '100px',
      'padding': '10px',
      'border': '4px solid',
    });
    final size = block.measure(_constraints());

    // 内容宽 = 100 − 28 = 72；10 个字按 4 字/行折成 3 行。
    expect(block.boxModel?.contentWidth, 72);
    expect(block.layout?.maxWidth, 72);
    expect(block.layout?.lineCount, 3);
    _expectSize(size, 100, 100);
  });

  test('auto 宽按内容测量，inset 计入块尺寸', () {
    final block = _text('a' * 24, {'padding': '8px', 'border': '4px solid'});
    final size = block.measure(_constraints());

    // 内容可用宽 = 200 − 24 = 176，正好 11 字/行；块宽回到约束宽。
    expect(block.boxModel?.contentWidth, isNull);
    expect(block.layout?.maxWidth, 176);
    expect(block.layout?.lineCount, 3);
    _expectSize(size, 200, 96);
  });

  test('容器 padding 压缩子块可用宽，子块折行增加', () {
    final plainText = _text('a' * 12);
    final plain = ColumnFlowBlock.styled(
      children: [plainText],
      style: _style(),
    );
    plain.measure(_constraints());
    expect(plainText.layout?.lineCount, 1);

    final paddedText = _text('a' * 12);
    final padded = ColumnFlowBlock.styled(
      children: [paddedText],
      style: _style({'padding': '20px'}),
    );
    padded.measure(_constraints());

    // 子块可用宽 200 − 40 = 160，12 字折成 2 行。
    expect(paddedText.constraints?.maxWidth, 160);
    expect(paddedText.layout?.lineCount, 2);
    _expectSize(padded.size, 200, 88);
  });

  test('容器 padding/border 计入自身尺寸', () {
    final container = ColumnFlowBlock.styled(
      children: [_text('aa')],
      style: _style({'padding': '10px', 'border': '4px solid'}),
    );
    final size = container.measure(_constraints());

    // 内容 32×24，四边 inset 14 → 60×52。
    _expectSize(container.children.single.size, 32, 24);
    _expectSize(size, 60, 52);
    expect(container.childTops, <double>[0]);
  });

  test('margin 折叠与 padding 共存，childTop 相对内容区', () {
    final container = ColumnFlowBlock.styled(
      children: [
        _text('aa', {'margin': '10px'}),
        _text('bb', {'margin': '10px'}),
      ],
      style: _style({'padding': '10px'}),
    );
    final size = container.measure(_constraints());

    // 首块顶位 0；相邻 margin 折叠为 10 → 第二块顶位 24 + 10 = 34。
    expect(container.childTops, <double>[0, 34]);
    // 内容高 58 + 上下 padding 20 = 78。
    _expectSize(size, 52, 78);
    // 容器上下 margin 与首末子块折叠后逸出。
    expect(container.margin.top, 10);
    expect(container.margin.bottom, 10);
  });

  test('未声明尺寸且零 inset 时与旧行为一致', () {
    final legacy = ColumnFlowBlock([_text('aa'), _text('bbbb')]);
    final legacySize = legacy.measure(_constraints());

    final styled = ColumnFlowBlock.styled(
      children: [_text('aa'), _text('bbbb')],
      style: _style(),
    );
    final styledSize = styled.measure(_constraints());

    _expectSize(legacySize, 64, 48);
    _expectSize(styledSize, 64, 48);
    expect(styledSize, legacySize);
  });

  test('createFlowBox 容器分支走样式盒模型', () {
    final box = createFlowBox(
      style: _style({'padding': '10px', 'margin': '5px'}),
      children: [_text('aa')],
    );
    expect(box, isA<ColumnFlowBlock>());

    final size = box.measure(_constraints());
    // 子块 32×24，加 padding 10 → 52×44。
    _expectSize(size, 52, 44);
    expect(box.margin.top, 5);
  });
}
