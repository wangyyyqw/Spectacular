import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';

import 'decoration_rules.dart';

/// 将高亮 CSS 声明转换为可编辑的装饰属性。
ReaderDecorationRuleStyle importDecorationRuleCss(
  ReaderDecorationRuleStyle current,
  String source,
) {
  final declarations = CssParser.parseInlineDeclarations(source);
  if (declarations.isEmpty) throw const FormatException('请输入 CSS 样式声明');
  const supported = {
    'color',
    'background',
    'background-color',
    'font-size',
    'font-family',
    'font-weight',
    'font-style',
    'letter-spacing',
    'padding',
    'margin',
    'padding-top',
    'padding-right',
    'padding-bottom',
    'padding-left',
    'margin-top',
    'margin-right',
    'margin-bottom',
    'margin-left',
    'border',
    'border-color',
    'border-width',
    'border-style',
    'border-radius',
    'background-size',
  };
  final values = <String, String>{};
  for (final declaration in declarations) {
    if (!supported.contains(declaration.property) ||
        declaration.value.toLowerCase().contains('url(')) {
      throw FormatException('暂不支持 ${declaration.property}，请使用样式面板设置');
    }
    values[declaration.property] = declaration.value;
  }
  final computed = ComputedStyle(values, containingWidth: 272);
  bool has(String prefix) =>
      values.keys.any((key) => key == prefix || key.startsWith('$prefix-'));
  final typography = current.typography.withValues({
    if (has('font-size')) 'fontSizeScale': computed.fontSize / 16,
    if (has('font-family')) 'fontFamily': computed.fontFamilies.firstOrNull,
    if (has('font-weight')) 'fontWeight': computed.fontWeight,
    if (has('font-style')) 'italic': computed.italic,
    if (has('letter-spacing'))
      'letterSpacingEm': computed.letterSpacing / computed.fontSize,
    // 内外留白统一转换为装饰绘制范围，不改变正文行盒。
    if (has('padding') || has('margin')) ...{
      'paddingTop': computed.padding.top + computed.margin.top,
      'paddingRight': computed.padding.right + computed.margin.right,
      'paddingBottom': computed.padding.bottom + computed.margin.bottom,
      'paddingLeft': computed.padding.left + computed.margin.left,
    },
  });
  return current.withValues({
    'typography': typography.toJson(),
    if (has('color')) 'color': computed.color.toARGB32(),
    if (values.containsKey('background') ||
        values.containsKey('background-color'))
      'backgroundColor': computed.backgroundColor.toARGB32(),
    if (values['background-size'] case final size?) ...{
      if (size != '100% 100%' && size != 'stretch')
        'backgroundImageFit': current.backgroundImageFit.name
      else
        'backgroundImageFit': 'fill',
    },
    if (has('border')) ...{
      if (has('border-width') || values.containsKey('border'))
        'borderWidth': computed.borders.top.width,
      if (has('border-color') || values.containsKey('border'))
        'borderColor': computed.borders.top.color.toARGB32(),
      if (has('border-style') || values.containsKey('border'))
        'borderStyle': computed.borders.top.style.name,
    },
    if (values['border-radius'] case final radius?)
      'borderRadius':
          double.tryParse(radius.replaceAll(RegExp(r'[a-z%]+'), '')) ?? 0,
  });
}
