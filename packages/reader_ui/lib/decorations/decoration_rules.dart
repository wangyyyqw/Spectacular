import 'decoration_style.dart';
import 'style_values.dart';

/// 匹配类型沿用阅微规则的语义，旧规则按原正则开关解析。
enum ReaderDecorationRuleType {
  fixedText('固定文本'),
  regex('正则表达式'),
  range('分隔符范围'),
  doubleQuoteDialogue('双引号对话'),
  singleQuotePhrase('单引号词组');

  const ReaderDecorationRuleType(this.label);
  final String label;
  bool get needsPattern =>
      this != doubleQuoteDialogue && this != singleQuotePhrase;
  bool get supportsCrossParagraph => this == regex || this == range;
  int get priority => this == doubleQuoteDialogue
      ? 0
      : this == singleQuotePhrase
      ? 2
      : 1;
}

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

/// 可复用的文字、背景与盒样式。
class ReaderDecorationRuleStyle {
  /// 创建规则样式。
  const ReaderDecorationRuleStyle({
    this.color,
    this.highlight,
    this.backgroundColor,
    this.backgroundImagePath,
    this.backgroundImageFit = ReaderDecorationImageFit.cover,
    this.backgroundImageNineSlice,
    this.backgroundOpacity = 1,
    this.borderRadius = 0,
    this.borderStyle = ReaderDecorationBorderStyle.solid,
    this.borderWidth = 0,
    this.borderColor,
    this.typography = const ReaderDecorationStyle(),
    this.darkStyle,
  });

  /// 文字颜色。
  final int? color;

  final ReaderDecorationHighlight? highlight;

  /// 背景颜色。
  final int? backgroundColor;

  final String? backgroundImagePath;
  final ReaderDecorationImageFit backgroundImageFit;
  final ReaderDecorationNineSlice? backgroundImageNineSlice;

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

  /// 规则字体与留白参与正式排版，保留原文 CFI。
  final ReaderDecorationStyle typography;

  /// 未指定夜间样式时沿用日间。
  final ReaderDecorationRuleStyle? darkStyle;
  ReaderDecorationRuleStyle forTheme(bool dark) =>
      dark ? darkStyle ?? this : this;

  /// 转为正式排版与绘制样式。
  ReaderDecorationStyle get decorationStyle {
    final side = ReaderDecorationBorderSide(
      width: borderWidth,
      color: borderColor ?? 0xFF9CA3AF,
    );
    return ReaderDecorationStyle(
      color: color,
      highlight: highlight,
      backgroundColor: backgroundColor,
      backgroundImagePath: backgroundImagePath,
      backgroundImageFit: backgroundImageFit,
      backgroundImageNineSlice: backgroundImageNineSlice,
      backgroundOpacity: backgroundOpacity,
      borderRadius: borderRadius,
      borderStyle: borderStyle,
      borderTop: side,
      borderRight: side,
      borderBottom: side,
      borderLeft: side,
      fontFamily: typography.fontFamily,
      fontSizeScale: typography.fontSizeScale,
      fontWeight: typography.fontWeight,
      italic: typography.italic,
      letterSpacingEm: typography.letterSpacingEm,
      paddingTop: typography.paddingTop,
      paddingRight: typography.paddingRight,
      paddingBottom: typography.paddingBottom,
      paddingLeft: typography.paddingLeft,
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => {
    'v': 1,
    'color': color,
    if (highlight != null) 'highlight': highlight!.toJson(),
    'backgroundColor': backgroundColor,
    if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
    if (backgroundImagePath != null)
      'backgroundImageFit': backgroundImageFit.name,
    if (backgroundImagePath != null)
      'backgroundImageNineSlice': backgroundImageNineSlice?.toJson(),
    'backgroundOpacity': backgroundOpacity,
    'borderRadius': borderRadius,
    'borderStyle': borderStyle.name,
    'borderWidth': borderWidth,
    'borderColor': borderColor,
    'typography': typography.toJson(),
    if (darkStyle != null) 'darkStyle': darkStyle!.toJson(),
  };

  /// 更新规则样式。
  ReaderDecorationRuleStyle withValues(Map<String, Object?> values) =>
      ReaderDecorationRuleStyle.fromJson({...toJson(), ...values});

  /// 解析 JSON。
  factory ReaderDecorationRuleStyle.fromJson(Object? raw) {
    final json = styleObject(raw);
    return ReaderDecorationRuleStyle(
      color: styleColor(json['color']),
      highlight: ReaderDecorationHighlight.fromJson(json['highlight']),
      backgroundColor: styleColor(json['backgroundColor']),
      backgroundImagePath: styleString(json['backgroundImagePath']),
      backgroundImageFit: ReaderDecorationImageFit.fromJson(
        json['backgroundImageFit'],
      ),
      backgroundImageNineSlice: ReaderDecorationNineSlice.fromJson(
        json['backgroundImageNineSlice'],
      ),
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
      typography: ReaderDecorationStyle.fromJson(json['typography']),
      darkStyle: json['darkStyle'] == null
          ? null
          : ReaderDecorationRuleStyle.fromJson(json['darkStyle']),
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
    this.type,
    this.allowCrossParagraph = false,
    this.styleId,
    this.darkStyleId,
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

  /// 规则使用的排版与绘制样式。
  final ReaderDecorationRuleStyle style;

  /// 组内顺序。
  final int sortOrder;
  final ReaderDecorationRuleType? type;
  ReaderDecorationRuleType get effectiveType =>
      type ??
      (isRegex
          ? ReaderDecorationRuleType.regex
          : ReaderDecorationRuleType.fixedText);
  final bool allowCrossParagraph;

  /// 可复用样式引用；空值使用规则内嵌样式。
  final String? styleId;
  final String? darkStyleId;

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
    ReaderDecorationRuleType? type,
    bool? allowCrossParagraph,
    String? styleId,
    String? darkStyleId,
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
    type: type ?? this.type,
    allowCrossParagraph: allowCrossParagraph ?? this.allowCrossParagraph,
    styleId: styleId ?? this.styleId,
    darkStyleId: darkStyleId ?? this.darkStyleId,
  );
}

/// 保存可复用样式与本书全局规则选择，宿主可用现有设置表实现。
abstract interface class ReaderDecorationRulePreferences {
  Future<List<ReaderDecorationNamedStyle>> listStyles();
  Future<void> saveStyle(ReaderDecorationNamedStyle style);
  Future<void> removeStyle(String id);
  Future<Set<String>?> loadGlobalRuleSelection();
  Future<void> saveGlobalRuleSelection(Set<String>? ids);
}

class ReaderDecorationNamedStyle {
  const ReaderDecorationNamedStyle({
    required this.id,
    required this.name,
    required this.style,
    this.builtIn = false,
  });
  final String id;
  final String name;
  final ReaderDecorationRuleStyle style;
  final bool builtIn;
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
