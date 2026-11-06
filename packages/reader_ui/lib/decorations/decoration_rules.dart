import 'decoration_style.dart';
import 'style_values.dart';

/// 本书或全局规则的分组。
class ReaderDecorationRuleGroup {
  /// 创建分组。
  const ReaderDecorationRuleGroup({
    required this.id,
    required this.name,
    this.bookId,
    this.enabled = true,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  /// 唯一标识。
  final String id;

  /// 所属书籍 UUID；空值为全局。
  final String? bookId;

  /// 名称。
  final String name;

  /// 分组开关。
  final bool enabled;

  /// 默认组固定在末尾。
  final bool isDefault;

  /// 组间顺序。
  final int sortOrder;

  /// 更新名称、开关或顺序。
  ReaderDecorationRuleGroup copyWith({
    String? name,
    bool? enabled,
    int? sortOrder,
  }) => ReaderDecorationRuleGroup(
    id: id,
    bookId: bookId,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    isDefault: isDefault,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

/// 仅包含绘制属性的规则样式。
class ReaderDecorationRuleStyle {
  /// 创建规则样式。
  const ReaderDecorationRuleStyle({
    this.color,
    this.backgroundColor,
    this.backgroundOpacity = 1,
    this.borderRadius = 0,
    this.borderStyle = ReaderDecorationBorderStyle.solid,
    this.borderWidth = 0,
    this.borderColor,
  });

  /// 文字颜色。
  final int? color;

  /// 背景颜色。
  final int? backgroundColor;

  /// 背景透明度。
  final double backgroundOpacity;

  /// 统一圆角。
  final double borderRadius;

  /// 统一线型。
  final ReaderDecorationBorderStyle borderStyle;

  /// 四边统一线宽。
  final double borderWidth;

  /// 边框颜色。
  final int? borderColor;

  /// 转为绘制样式，不含任何字体度量字段。
  ReaderDecorationStyle get decorationStyle {
    final side = ReaderDecorationBorderSide(
      width: borderWidth,
      color: borderColor ?? 0xFF9CA3AF,
    );
    return ReaderDecorationStyle(
      color: color,
      backgroundColor: backgroundColor,
      backgroundOpacity: backgroundOpacity,
      borderRadius: borderRadius,
      borderStyle: borderStyle,
      borderTop: side,
      borderRight: side,
      borderBottom: side,
      borderLeft: side,
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => {
    'v': 1,
    'color': color,
    'backgroundColor': backgroundColor,
    'backgroundOpacity': backgroundOpacity,
    'borderRadius': borderRadius,
    'borderStyle': borderStyle.name,
    'borderWidth': borderWidth,
    'borderColor': borderColor,
  };

  /// 更新规则样式。
  ReaderDecorationRuleStyle withValues(Map<String, Object?> values) =>
      ReaderDecorationRuleStyle.fromJson({...toJson(), ...values});

  /// 解析 JSON。
  factory ReaderDecorationRuleStyle.fromJson(Object? raw) {
    final json = styleObject(raw);
    return ReaderDecorationRuleStyle(
      color: styleColor(json['color']),
      backgroundColor: styleColor(json['backgroundColor']),
      backgroundOpacity: styleNumber(
        json['backgroundOpacity'],
        fallback: 1,
        min: 0,
        max: 1,
      ),
      borderRadius: styleNumber(
        json['borderRadius'],
        fallback: 0,
        min: 0,
        max: 20,
      ),
      borderStyle: ReaderDecorationBorderStyle.fromJson(json['borderStyle']),
      borderWidth: styleNumber(
        json['borderWidth'],
        fallback: 0,
        min: 0,
        max: 6,
      ),
      borderColor: styleColor(json['borderColor']),
    );
  }
}

/// 渲染期文本匹配规则。
class ReaderDecorationRule {
  /// 创建规则。
  const ReaderDecorationRule({
    required this.id,
    required this.groupId,
    required this.pattern,
    required this.style,
    this.name,
    this.isRegex = false,
    this.caseSensitive = false,
    this.enabled = true,
    this.sortOrder = 0,
  });

  /// 唯一标识。
  final String id;

  /// 所属组。
  final String groupId;

  /// 可选名称。
  final String? name;

  /// 字面文本或正则。
  final String pattern;

  /// 正则开关。
  final bool isRegex;

  /// 区分大小写。
  final bool caseSensitive;

  /// 单条开关。
  final bool enabled;

  /// 不影响排版的样式。
  final ReaderDecorationRuleStyle style;

  /// 组内顺序。
  final int sortOrder;

  /// 创建更新后的规则。
  ReaderDecorationRule copyWith({
    String? groupId,
    String? name,
    String? pattern,
    bool? isRegex,
    bool? caseSensitive,
    bool? enabled,
    ReaderDecorationRuleStyle? style,
    int? sortOrder,
  }) => ReaderDecorationRule(
    id: id,
    groupId: groupId ?? this.groupId,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    isRegex: isRegex ?? this.isRegex,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    enabled: enabled ?? this.enabled,
    style: style ?? this.style,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

/// 只存分组和规则；命中结果只存在于阅读会话中。
abstract interface class ReaderDecorationRuleStore {
  /// 当前书与全局的分组，自动确保各作用域有默认组。
  Future<List<ReaderDecorationRuleGroup>> listGroups();

  /// 可见分组下的全部规则。
  Future<List<ReaderDecorationRule>> listRules();

  /// 保存分组，默认组保留其固定性质。
  Future<void> saveGroup(ReaderDecorationRuleGroup group);

  /// 删除组并把规则移到同作用域默认组末尾。
  Future<void> removeGroup(String id);

  /// 保存规则，保存前校验正则。
  Future<void> saveRule(ReaderDecorationRule rule);

  /// 删除规则。
  Future<void> removeRule(String id);

  /// 同作用域组间排序，默认组固定最后。
  Future<void> reorderGroups(List<String> ids);

  /// 组内排序。
  Future<void> reorderRules(String groupId, List<String> ids);
}
