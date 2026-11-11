/// 书籍字号关键字的计算及相对基准分类。
abstract final class CssFontSizes {
  static const absoluteFactors = <String, double>{
    'xx-small': 9 / 16,
    'x-small': 10 / 16,
    'small': 13 / 16,
    'medium': 1,
    'large': 9 / 8,
    'x-large': 3 / 2,
    'xx-large': 2,
    'xxx-large': 3,
  };

  static bool isKeyword(String value) =>
      absoluteFactors.containsKey(value) ||
      value == 'smaller' ||
      value == 'larger';

  /// 绝对关键字与 rem 共用书籍基准；用户字号在排版覆盖阶段只应用一次。
  static bool usesRoot(String? value) =>
      value != null &&
      (absoluteFactors.containsKey(value) || value.endsWith('rem'));

  static double? resolve(
    String raw, {
    required double parent,
    required double root,
  }) {
    final value = raw.trim().toLowerCase();
    final factor = absoluteFactors[value];
    if (factor != null) return root * factor;
    return switch (value) {
      'smaller' => parent / 1.2,
      'larger' => parent * 1.2,
      _ => null,
    };
  }
}
