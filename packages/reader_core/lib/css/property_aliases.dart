/// 属性名别名与私有属性映射（P9-13）。
///
/// 中文精排 EPUB（多看、掌阅、QQ 阅读）大量使用厂商私有属性：
/// `-duokan-text-indent`、`duokan-paragraph-align`、`-duokan-text-fill` 等。
/// 这些属性不是标准 CSS，但语义与标准属性一一对应；在解析入口统一改名，
/// 后续层叠、计算、绘制全部走标准路径，不必在每个消费点各写一次兼容。
abstract final class CssPropertyAliases {
  /// 私有属性 → 标准属性（键为去掉前导 `-` 后的小写名）。
  ///
  /// 键的写法规整：`-duokan-x` 与 `duokan-x` 剥掉前导 `-` 后同名，所以
  /// 真实书里连字符漏写（`webkit-writing-mode`）、或换成别的私有前缀
  /// （`-epub-x`、`-webkit-x`）都落到同一张表。
  static const Map<String, String> _aliases = <String, String>{
    'duokan-text-indent': 'text-indent',
    'duokan-paragraph-align': 'text-align',
    'duokan-text-align': 'text-align',
    'duokan-line-height': 'line-height',
    'duokan-letter-spacing': 'letter-spacing',
    'duokan-break-inside': 'break-inside',
    'duokan-page-break-inside': 'page-break-inside',
    'duokan-page-break-before': 'page-break-before',
    'duokan-page-break-after': 'page-break-after',
    'duokan-text-color': 'color',
    // 多看渐变文字：取第一个色标当纯色（渐变本身不支持）。
    'duokan-text-fill': 'color',
    'duokan-text-shadow': 'text-shadow',
    'duokan-text-decoration': 'text-decoration',
    'duokan-font-weight': 'font-weight',
    // 多看段前后距。
    'duokan-margin-before': 'margin-top',
    'duokan-margin-after': 'margin-bottom',
    'duokan-padding-before': 'padding-top',
    'duokan-padding-after': 'padding-bottom',
    // 着重号族：多看 4.x 与 WebKit 旧语法都写过（真实书与多看官方
    // 样式表里两套并存），统一落到标准 text-emphasis* 长属性。
    'duokan-text-emphasis': 'text-emphasis',
    'duokan-text-emphasis-style': 'text-emphasis-style',
    'duokan-text-emphasis-color': 'text-emphasis-color',
    'duokan-text-emphasis-position': 'text-emphasis-position',
    'webkit-text-emphasis': 'text-emphasis',
    'webkit-text-emphasis-style': 'text-emphasis-style',
    'webkit-text-emphasis-color': 'text-emphasis-color',
    'webkit-text-emphasis-position': 'text-emphasis-position',
    // 断行严格度：多看 duokan-line-break 与 WebKit 旧语法同义。
    // 目标属性 `line-break` 当前零消费（ComputedStyle 无字段、排版侧不读），
    // 这里只保证「改名 + 落进 values」，不要当作已支持。
    'duokan-line-break': 'line-break',
    'webkit-line-break': 'line-break',
    // 排版方向族（竖排 P5 未接入，先按标准属性保存）。
    // 目标属性 `writing-mode` / `text-orientation` 当前零消费（取值改写与
    // 归一已做，排版/绘制不读），待 P5 竖排接入后补消费点。
    // 注意：text-orientation 不能并进 writing-mode——真实书里
    // `duokan-text-orientation: upright` 紧跟在 `duokan-writing-mode:
    // vertical-rl` 之后，同特异性后者胜，并进去会把整章排版方向从竖排
    // 改回横排。
    'duokan-writing-mode': 'writing-mode',
    'duokan-writing-orientation': 'writing-mode',
    'duokan-block-progression': 'writing-mode',
    'duokan-text-orientation': 'text-orientation',
    'epub-writing-mode': 'writing-mode',
    'epub-text-orientation': 'text-orientation',
    'webkit-writing-mode': 'writing-mode',
    // 着重号/注音的 -epub- 旧前缀。
    'epub-text-emphasis': 'text-emphasis',
    'epub-text-emphasis-style': 'text-emphasis-style',
    'epub-text-emphasis-color': 'text-emphasis-color',
    'epub-text-emphasis-position': 'text-emphasis-position',
    // 断词与直排合成（真实书 `-epub-hyphens`、`-webkit-text-combine`）。
    // 目标属性 `hyphens` / `text-combine-upright` 当前零消费，同样是
    // 「先接住再等消费点」，不是已实现。
    'epub-hyphens': 'hyphens',
    'webkit-hyphens': 'hyphens',
    'epub-text-combine': 'text-combine-upright',
    'webkit-text-combine': 'text-combine-upright',
    'ms-text-combine-horizontal': 'text-combine-upright',
    // 逻辑方向边距/内边距：中文 EPUB 都是横排 LTR，按左/右近似
    // （真实书用 -webkit-margin-start 做首行缩进时的常见写法）。
    // -webkit-margin/padding-start/end 本质是逻辑属性（受书写模式/方向影响），
    // 统一映射成 margin-inline-start 等，由级联期的逻辑属性映射再落物理。
    'webkit-margin-start': 'margin-inline-start',
    'webkit-margin-end': 'margin-inline-end',
    'webkit-padding-start': 'padding-inline-start',
    'webkit-padding-end': 'padding-inline-end',
  };

  /// 解析一条声明：返回标准属性名与（可能被规整的）值。
  static (String, String) resolve(String property, String value) {
    final raw = property.trim().toLowerCase();
    final normalized = raw.startsWith('-') ? raw.substring(1) : raw;
    final target = _aliases[normalized];
    if (target == null) {
      return (raw, value);
    }
    if (normalized.endsWith('text-fill')) {
      final color = _firstColor(value);
      if (color != null) {
        return (target, color);
      }
    }
    return (target, _normalizeValue(target, value));
  }

  static final RegExp _colorPattern = RegExp(
    r'(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)|hsla?\([^)]*\))',
  );

  static String? _firstColor(String value) =>
      _colorPattern.firstMatch(value)?.group(1);

  /// 私有属性取值规整：多看排版方向族用 `vertical` / `horizontal` 与
  /// 单字母块级推进方向（`rl` / `lr` / `tb`），都不是标准 writing-mode
  /// 取值。这里统一折成标准写法：
  /// - `rl` 是块级推进「从右往左」= 竖排右起 → `vertical-rl`；
  /// - `lr` 是「从左往右」= 竖排左起（蒙古文）→ `vertical-lr`；
  /// - `tb` 是「从上往下」= 横排 → `horizontal-tb`。
  ///
  /// 不折的话引擎侧只能拿到 `rl` 这类旧值，竖排接入时还要再判一次。
  static String _normalizeValue(String target, String value) {
    if (target == 'writing-mode') {
      switch (value.trim().toLowerCase()) {
        case 'vertical' || 'rl' || 'rl-tb' || 'tb-rl':
          return 'vertical-rl';
        case 'lr' || 'lr-tb':
          return 'vertical-lr';
        case 'horizontal' || 'tb':
          return 'horizontal-tb';
      }
    }
    return value;
  }

  /// 逻辑属性（`margin-inline-start` 等）→ 物理属性名。
  ///
  /// [writingMode] 传 `CssWritingMode.name`（`horizontalTb` / `verticalRl` /
  /// `verticalLr`），[direction] 传 `CssDirection.name`（`ltr` / `rtl`）；用
  /// 字符串而不是枚举是为了让别名层保持单向依赖（computed_style 依赖本文件）。
  ///
  /// 覆盖 `margin-*` / `padding-*` / `inset-*` 与 `border-*` 的
  /// inline|block × start|end（border 含 `-width`/`-style`/`-color`）。
  /// 映射规则：horizontal-tb + ltr → inline-start = left；vertical-rl 的块级
  /// 推进从右往左 → block-start = right；竖排下 `direction: rtl` 的行内方向
  /// 自下而上 → inline-start = bottom。
  static Map<String, String> logicalPhysicalMap({
    required String writingMode,
    required String direction,
  }) {
    // 入参既可以是 CSS 取值（`horizontal-tb`/`vertical-rl`），也可以是
    // `CssWritingMode.name`（`horizontalTb`/`verticalRl`），统一去连字符小写。
    final mode = writingMode.replaceAll('-', '').toLowerCase();
    final vertical = mode.startsWith('vertical');
    final ltr = direction.trim().toLowerCase() != 'rtl';
    final String inlineStart;
    final String inlineEnd;
    final String blockStart;
    final String blockEnd;
    if (!vertical) {
      inlineStart = ltr ? 'left' : 'right';
      inlineEnd = ltr ? 'right' : 'left';
      blockStart = 'top';
      blockEnd = 'bottom';
    } else if (mode.endsWith('rl')) {
      inlineStart = ltr ? 'top' : 'bottom';
      inlineEnd = ltr ? 'bottom' : 'top';
      blockStart = 'right';
      blockEnd = 'left';
    } else {
      inlineStart = ltr ? 'top' : 'bottom';
      inlineEnd = ltr ? 'bottom' : 'top';
      blockStart = 'left';
      blockEnd = 'right';
    }
    final map = <String, String>{};
    for (final family in const <String>['margin', 'padding']) {
      map['$family-inline-start'] = '$family-$inlineStart';
      map['$family-inline-end'] = '$family-$inlineEnd';
      map['$family-block-start'] = '$family-$blockStart';
      map['$family-block-end'] = '$family-$blockEnd';
    }
    // inset-* 落到定位属性本身（引擎读 top/right/bottom/left）。
    map['inset-inline-start'] = inlineStart;
    map['inset-inline-end'] = inlineEnd;
    map['inset-block-start'] = blockStart;
    map['inset-block-end'] = blockEnd;
    // border 简写与 -width/-style/-color 长属性。
    final borderSides = <String, String>{
      'border-inline-start': inlineStart,
      'border-inline-end': inlineEnd,
      'border-block-start': blockStart,
      'border-block-end': blockEnd,
    };
    borderSides.forEach((logical, side) {
      map[logical] = 'border-$side';
      map['$logical-width'] = 'border-$side-width';
      map['$logical-style'] = 'border-$side-style';
      map['$logical-color'] = 'border-$side-color';
    });
    return map;
  }

  /// 值级别的私有关键字（`vertical-align: duokan-middle-line` 等）。
  static String normalizeValue(String value) {
    final trimmed = value.trim();
    if (trimmed == 'duokan-middle-line') {
      return 'middle';
    }
    return trimmed;
  }
}
