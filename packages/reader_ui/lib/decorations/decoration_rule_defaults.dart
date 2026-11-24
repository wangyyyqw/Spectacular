import 'decoration_rules.dart';
import 'decoration_style.dart';

/// 默认高亮样式，位图由应用宿主提供。
const readerDecorationBuiltInStyles = [
  ReaderDecorationNamedStyle(
    id: 'builtin_rainbow_glass',
    name: '彩色玻璃·紫',
    builtIn: true,
    style: ReaderDecorationRuleStyle(
      color: 0xFF5A2E7F,
      backgroundImagePath: 'asset://reader_highlight/rainbow_glass.png',
      backgroundImageFit: ReaderDecorationImageFit.fill,
      typography: ReaderDecorationStyle(
        fontSizeScale: 0.9,
        paddingLeft: 16,
        paddingRight: 16,
        paddingTop: 9,
        paddingBottom: 9,
      ),
    ),
  ),
  ReaderDecorationNamedStyle(
    id: 'default',
    name: '橙色默认',
    builtIn: true,
    style: ReaderDecorationRuleStyle(
      color: 0xFFFF9800,
      typography: ReaderDecorationStyle(fontSizeScale: 0.9),
    ),
  ),
];

List<ReaderDecorationRule> readerDecorationDefaultRules(String groupId) => [
  for (final (id, name, type) in const [
    (
      'double_quote_dialogue',
      '双引号对话',
      ReaderDecorationRuleType.doubleQuoteDialogue,
    ),
    (
      'single_quote_phrase',
      '单引号词组',
      ReaderDecorationRuleType.singleQuotePhrase,
    ),
  ])
    ReaderDecorationRule(
      id: id,
      groupId: groupId,
      name: name,
      pattern: '',
      type: type,
      enabled: false,
      styleId: 'builtin_rainbow_glass',
      darkStyleId: 'default',
      style: readerDecorationBuiltInStyles.first.style.withValues({
        'darkStyle': readerDecorationBuiltInStyles.last.style.toJson(),
      }),
      sortOrder: type == ReaderDecorationRuleType.doubleQuoteDialogue ? 0 : 1,
    ),
];
