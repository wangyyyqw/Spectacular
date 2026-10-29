import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// `font-variant-caps` → OpenType 特性（测量与绘制共用 textStyleFor）。
ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

List<String> _tags(ComputedStyle style) =>
    (TextLayoutEngine.textStyleFor(style).fontFeatures ?? const <FontFeature>[])
        .map((feature) => feature.feature)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('small-caps → smcp；all-small-caps → smcp + c2sc', () {
    expect(_tags(_style()), isEmpty, reason: 'normal 不带特性');
    expect(
      _tags(_style(const {'font-variant-caps': 'small-caps'})),
      contains('smcp'),
    );
    expect(
      _tags(_style(const {'font-variant-caps': 'all-small-caps'})),
      containsAll(<String>['smcp', 'c2sc']),
    );
  });

  test('font-variant 简写里的 caps 族同样生效', () {
    expect(
      _tags(_style(const {'font-variant': 'small-caps'})),
      contains('smcp'),
    );
  });

  test('font-variant-ligatures: none 关闭 liga 与 clig', () {
    final style = _style(const {'font-variant-ligatures': 'none'});
    expect(_tags(style), containsAll(<String>['liga', 'clig']));
    expect(
      (TextLayoutEngine.textStyleFor(style).fontFeatures ??
              const <FontFeature>[])
          .where((feature) => feature.value == 0)
          .length,
      2,
    );
  });

  test('其它 caps 族映射到对应 OpenType 标签', () {
    expect(_tags(_style(const {'font-variant-caps': 'petite-caps'})), contains('pcap'));
    expect(
      _tags(_style(const {'font-variant-caps': 'all-petite-caps'})),
      containsAll(<String>['pcap', 'c2pc']),
    );
    expect(_tags(_style(const {'font-variant-caps': 'unicase'})), contains('unic'));
    expect(_tags(_style(const {'font-variant-caps': 'titling-caps'})), contains('titl'));
  });

  test('无 smcp 的字体：测量宽度不受影响、不报错', () {
    final normal = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(),
      maxWidth: 400,
    );
    final caps = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'font-variant-caps': 'small-caps'}),
      maxWidth: 400,
    );
    // Ahem 没有 smcp 特性 → 引擎按原样渲染，宽度一致（测量/绘制同口径）。
    expect(caps.lines.single.width, closeTo(normal.lines.single.width, 0.01));
    expect(caps.lineCount, normal.lineCount);
  });
}
