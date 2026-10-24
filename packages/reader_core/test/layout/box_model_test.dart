import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';

const _containingWidth = 200.0;

ComputedStyle _style(
  Map<String, String> declarations, {
  double containingWidth = _containingWidth,
}) => ComputedStyle(declarations, containingWidth: containingWidth);

BoxModel _model(
  Map<String, String> declarations, {
  double containingWidth = _containingWidth,
}) => BoxModel.fromStyle(
  _style(declarations, containingWidth: containingWidth),
  containingWidth: containingWidth,
);

void main() {
  test('content-box 声明宽即内容宽，padding/border 另计', () {
    final model = _model({
      'width': '100px',
      'padding': '10px',
      'border': '4px solid',
    });

    expect(model.boxSizing, CssBoxSizing.contentBox);
    expect(model.contentWidth, 100);
    expect(model.horizontalInset, 28);
    expect(model.resolveContentWidth(200), 100);
    expect(model.borderBoxWidth(model.resolveContentWidth(200)), 128);
  });

  test('border-box 声明宽含 padding 与 border', () {
    final model = _model({
      'box-sizing': 'border-box',
      'width': '100px',
      'padding': '10px',
      'border': '4px solid',
    });

    // 内容宽 = 100 − (10+10) − (4+4) = 72。
    expect(model.contentWidth, 72);
    expect(model.resolveContentWidth(200), 72);
    expect(model.borderBoxWidth(72), 100);
  });

  test('border-box 声明值小于 inset 时内容尺寸钳 0', () {
    final model = _model({
      'box-sizing': 'border-box',
      'width': '20px',
      'padding': '10px',
      'border': '4px solid',
    });

    // 20 − 28 < 0，钳到 0。
    expect(model.contentWidth, 0);
    expect(model.resolveContentWidth(200), 0);
  });

  test('百分比 width 按 containingWidth 解算', () {
    final normal = _model({'width': '50%'});
    expect(normal.contentWidth, 100);

    final wide = _model({'width': '50%'}, containingWidth: 320);
    expect(wide.contentWidth, 160);
  });

  test('auto 宽填满可用宽，扣掉 inset', () {
    final model = _model({'width': 'auto', 'padding': '10px'});

    expect(model.contentWidth, isNull);
    expect(model.resolveContentWidth(200), 180);

    final noInset = _model({});
    expect(noInset.contentWidth, isNull);
    expect(noInset.resolveContentWidth(200), 200);
  });

  test('auto 宽同时扣掉 margin', () {
    final model = _model({
      'padding': '10px',
      'border': '4px solid',
      'margin': '0 20px',
    });

    // 200 − 28 − 40 = 132，边框盒 160。
    expect(model.resolveContentWidth(200), 132);
    expect(model.borderBoxWidth(132), 160);
  });

  test('min/max 宽钳制，min 优先于 max', () {
    expect(_model({'max-width': '120px'}).resolveContentWidth(200), 120);
    expect(
      _model({'width': '50px', 'min-width': '80px'}).resolveContentWidth(200),
      80,
    );
    // 百分比 min-width 也按 containingWidth 解算：10 被抬到 200 × 50% = 100。
    expect(
      _model({'width': '10px', 'min-width': '50%'}).resolveContentWidth(200),
      100,
    );
    // min 与 max 冲突时 min 生效（CSS 2.1 §10.4）。
    expect(
      _model({'min-width': '180px', 'max-width': '150px'})
          .resolveContentWidth(200),
      180,
    );
  });

  test('height 声明按 box-sizing 解算，未声明用测量值', () {
    final contentBox = _model({'height': '40px'});
    expect(contentBox.contentHeight, 40);
    expect(contentBox.resolveContentHeight(999, containingHeight: 500), 40);

    final borderBox = _model({
      'box-sizing': 'border-box',
      'height': '40px',
      'padding': '10px',
      'border': '4px solid',
    });
    expect(borderBox.verticalInset, 28);
    expect(borderBox.contentHeight, 12);
    expect(borderBox.resolveContentHeight(999, containingHeight: 500), 12);

    final auto = _model({});
    expect(auto.contentHeight, isNull);
    expect(auto.resolveContentHeight(30, containingHeight: 500), 30);
  });

  test('百分比 height 暂按 containingWidth 近似解算', () {
    final model = _model({'height': '50%'});

    // 骨架期近似：200 × 50% = 100。
    expect(model.contentHeight, 100);
  });

  test('min/max 高钳制，min 优先于 max', () {
    expect(
      _model({'min-height': '60px'})
          .resolveContentHeight(30, containingHeight: 500),
      60,
    );
    expect(
      _model({'max-height': '20px'})
          .resolveContentHeight(100, containingHeight: 500),
      20,
    );
    expect(
      _model({'min-height': '50px', 'max-height': '30px'})
          .resolveContentHeight(40, containingHeight: 500),
      50,
    );
  });

  test('百分比 padding 已由样式层按 containingWidth 解析', () {
    final model = _model({'padding': '10%'});

    expect(model.padding.left, 20);
    expect(model.padding.top, 20);
    expect(model.horizontalInset, 40);
    expect(model.verticalInset, 40);
  });

  test('零 inset 直通，borderBox 尺寸等于内容尺寸', () {
    final model = _model({});

    expect(model.horizontalInset, 0);
    expect(model.verticalInset, 0);
    expect(model.resolveContentWidth(300), 300);
    expect(model.borderBoxWidth(300), 300);
    expect(model.resolveContentHeight(25, containingHeight: 100), 25);
    expect(model.borderBoxHeight(25), 25);
  });
}
