/// 一次算完的不可变样式值。
///
/// P1-20 先用字符串保存层叠后的指定值；P1-21 再补类型化字段与单位换算。
class ComputedStyle {
  /// 创建样式。
  const ComputedStyle(this.values, {this.hasExplicitTextColor = false});

  /// 属性 → 最终值。
  final Map<String, String> values;

  /// 是否存在作者/内联显式指定的文字色（暗色替换需要）。
  final bool hasExplicitTextColor;

  /// 取属性值。
  String? operator [](String property) => values[property.toLowerCase()];

  /// 文字颜色。
  String? get color => this['color'];

  /// 字号。
  String? get fontSize => this['font-size'];

  /// 字体族。
  String? get fontFamily => this['font-family'];

  /// 行高。
  String? get lineHeight => this['line-height'];

  /// 文本对齐。
  String? get textAlign => this['text-align'];

  /// 是否包含属性。
  bool contains(String property) => values.containsKey(property.toLowerCase());

  @override
  String toString() => 'ComputedStyle($values)';
}
