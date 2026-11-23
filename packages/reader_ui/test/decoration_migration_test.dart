import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/decorations/decoration_rule_engine.dart';
import 'package:reader_ui/decorations/decoration_rule_defaults.dart';
import 'package:reader_ui/decorations/decoration_rule_matching.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/rule_match_worker.dart';
import 'package:reader_ui/decorations/decoration_rule_css.dart';

void main() {
  test('CSS 导入保留默认字号颜色与像素留白，正则末尾严格匹配', () async {
    final style = importDecorationRuleCss(
      const ReaderDecorationRuleStyle(),
      'color: rgba(90,46,127,1); padding:9px 16px; font-size:0.9em; background-size:100% 100%',
    );
    expect(style.color, 0xFF5A2E7F);
    expect(style.typography.fontSizeScale, 0.9);
    expect(style.typography.paddingRight, 16);
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    expect(
      await matcher.match(
        pattern: r'a$',
        isRegex: true,
        caseSensitive: true,
        blocks: [const DecorationRuleTextBlock(cfi: '', text: 'a\n')],
      ),
      isEmpty,
    );
  });
  test('对话跨段保留位置，单引号与作者样式从对话中扣除', () async {
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    final blocks = [
      const DecorationRuleTextBlock(
        cfi: '',
        text: '“开头‘词组’和重点',
        protected: [(8, 10)],
      ),
      const DecorationRuleTextBlock(cfi: '', text: '下一段结尾”'),
    ];
    final hits = await matcher.match(
      pattern: '',
      isRegex: false,
      caseSensitive: false,
      blocks: blocks,
      type: ReaderDecorationRuleType.doubleQuoteDialogue,
      excludeSingleQuotes: true,
    );
    expect(hits.where((hit) => hit.block == 1).single.start, 0);
    expect(
      hits.where((hit) => hit.block == 1).single.end,
      blocks[1].text.length,
    );
    expect(
      hits.where((hit) => hit.block == 0).map((hit) => (hit.start, hit.end)),
      [(0, 3), (7, 8)],
    );
  });

  test('分隔符范围沿用最近开符，跨段开关与七段上限', () async {
    expect(decorationDelimiterRanges('【旧【新】', '【】', 1), [(2, 5)]);
    expect(decorationDelimiterRanges('|a|', '|', 1), [(0, 3)]);
    expect(decorationDelimiterRanges('【a\nb】', '【】', 1), isEmpty);
    expect(decorationDelimiterRanges('【a\nb】', '【】', 7), [(0, 5)]);
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    final blocks = [
      for (var i = 0; i < 8; i++)
        DecorationRuleTextBlock(
          cfi: '',
          text: i == 0
              ? '【a'
              : i == 7
              ? 'b】'
              : 'x',
        ),
    ];
    expect(
      await matcher.match(
        pattern: '【】',
        isRegex: false,
        caseSensitive: false,
        blocks: blocks,
        type: ReaderDecorationRuleType.range,
        allowCrossParagraph: true,
      ),
      isEmpty,
    );
  });

  test('超限正则不截断，非支持表达式与复杂展开拒绝', () async {
    expect(
      validateDecorationRule(ReaderDecorationRuleType.regex, r'(?<=a)b'),
      isNotNull,
    );
    expect(
      validateDecorationRule(ReaderDecorationRuleType.regex, r'(a{100}){100}'),
      isNotNull,
    );
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    await expectLater(
      matcher.match(
        pattern: r'a+',
        isRegex: true,
        caseSensitive: true,
        blocks: [DecorationRuleTextBlock(cfi: '', text: 'a' * 32769)],
      ),
      throwsFormatException,
    );
    await expectLater(
      matcher.match(
        pattern: 'a',
        isRegex: true,
        caseSensitive: true,
        blocks: [DecorationRuleTextBlock(cfi: '', text: 'a' * 1025)],
      ),
      throwsFormatException,
    );
  });

  test('表格等不可匹配原文断开跨段，默认明暗样式完整往返', () async {
    final chapter = AnchorChapter(
      spineIndex: 0,
      href: 'a.xhtml',
      blocks: [
        const AnchorBlock(cfi: 'epubcfi(/6/2!/4/2/1:0)', text: '【正文'),
        const AnchorBlock(
          cfi: 'epubcfi(/6/2!/4/4/1:0)',
          text: '表格',
          ruleEligible: false,
        ),
        const AnchorBlock(cfi: 'epubcfi(/6/2!/4/6/1:0)', text: '结尾】'),
      ],
    );
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    expect(
      await matcher.match(
        pattern: '【】',
        isRegex: false,
        caseSensitive: false,
        blocks: ReaderDecorationRuleEngine.anchorBlocks(chapter),
        type: ReaderDecorationRuleType.range,
        allowCrossParagraph: true,
      ),
      isEmpty,
    );
    final rule = readerDecorationDefaultRules('global').first;
    final copy = ReaderDecorationRuleStyle.fromJson(rule.style.toJson());
    expect(copy.forTheme(false).color, 0xFF5A2E7F);
    expect(copy.forTheme(true).color, 0xFFFF9800);
    expect(copy.typography.fontSizeScale, 0.9);
    expect(copy.typography.paddingLeft, 16);
  });
}
