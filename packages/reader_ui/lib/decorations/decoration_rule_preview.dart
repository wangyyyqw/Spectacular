import 'decoration_rules.dart';

/// 自动装饰规则的临时预览命中，不进入数据库。
class ReaderDecorationRulePreview {
  /// 创建预览片段。
  const ReaderDecorationRulePreview({
    required this.startCfi,
    required this.endCfi,
    required this.text,
    required this.style,
  });

  /// 片段起点。
  final String startCfi;

  /// 片段终点。
  final String endCfi;

  /// 命中文本。
  final String text;

  /// 临时显示样式。
  final ReaderDecorationRuleStyle style;
}
