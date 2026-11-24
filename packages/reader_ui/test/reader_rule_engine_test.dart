import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/decorations/decoration_rule_engine.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_style.dart';
import 'package:reader_ui/decorations/rule_match_worker.dart';

const _baseCfi = 'epubcfi(/6/2!/4/2/1:7)';
const _groups = [ReaderDecorationRuleGroup(id: 'group', name: '默认规则')];

class _CountingMatcher extends DecorationRuleMatcher {
  final calls = <String>[];

  @override
  Future<List<DecorationRuleHit>> match({
    required String pattern,
    required bool isRegex,
    required bool caseSensitive,
    required List<DecorationRuleTextBlock> blocks,
    int? limit,
    Duration timeout = const Duration(seconds: 1),
    ReaderDecorationRuleType? type,
    bool allowCrossParagraph = false,
    bool excludeSingleQuotes = false,
  }) {
    calls.add(pattern);
    return super.match(
      pattern: pattern,
      isRegex: isRegex,
      caseSensitive: caseSensitive,
      blocks: blocks,
      limit: limit,
      timeout: timeout,
      type: type,
      allowCrossParagraph: allowCrossParagraph,
      excludeSingleQuotes: excludeSingleQuotes,
    );
  }
}

ComputedStyle _style([String size = '16px']) => ComputedStyle({
  'font-family': 'Ahem',
  'font-size': size,
  'line-height': '1.5',
});

PageBlock _block(String text, String cfi, {bool eligible = true}) {
  final style = _style();
  return PageBlock(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 320),
    style: style,
    startCfi: cfi,
    textRuleEligible: eligible,
  );
}

PageContent _page(List<PageBlock> blocks, {int index = 0}) => PageContent(
  spineIndex: 0,
  pageIndex: index,
  slices: [
    for (final block in blocks)
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: block.layout.height,
      ),
  ],
  usedHeight: blocks.fold<double>(0, (height, block) => height + block.height),
  pageHeight: 600,
  topPadding: 0,
);

ReaderDecorationRule _rule(
  String id,
  String pattern, {
  bool isRegex = false,
  bool caseSensitive = false,
}) => ReaderDecorationRule(
  id: id,
  groupId: 'group',
  pattern: pattern,
  isRegex: isRegex,
  caseSensitive: caseSensitive,
  style: const ReaderDecorationRuleStyle(color: 0xFFFF0000),
);

Future<List<ReaderDecorationRuleMatch>> _match(
  ReaderDecorationRuleEngine engine,
  List<PageContent> pages,
  List<ReaderDecorationRule> rules,
) => engine.matchChapter(
  pages: pages,
  groups: _groups,
  rules: rules,
  bookId: 'book',
);

PageBlock _heading(String text, String cfi, String size) {
  final style = _style(size);
  return PageBlock(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 320),
    style: style,
    startCfi: cfi,
  );
}

List<PageBlock> _filteredBlocks() {
  final inline = _block('前匹配①后\uFFFC匹配', 'epubcfi(/6/2!/4/2/15)');
  final ruby = _block('汉字匹配', 'epubcfi(/6/2!/4/2/17)');
  final table = _block('表格匹配', 'epubcfi(/6/2!/4/2/13)');
  return [
    _block('正文匹配', _baseCfi),
    _heading('一级标题匹配', 'epubcfi(/6/2!/4/2/3)', '32px'),
    _heading('六级标题匹配', 'epubcfi(/6/2!/4/2/5)', '14px'),
    _block('脚注匹配', 'epubcfi(/6/2!/4/2/7)', eligible: false),
    _block('页眉匹配', 'epubcfi(/6/2!/4/2/9)', eligible: false),
    _block('页脚匹配', 'epubcfi(/6/2!/4/2/11)', eligible: false),
    PageBlock(
      layout: table.layout,
      style: table.style,
      startCfi: table.startCfi,
      table: const TableRenderSpec(
        cells: [],
        columnXs: [0, 320],
        rowYs: [0, 24],
        tableWidth: 320,
      ),
    ),
    PageBlock(
      layout: inline.layout,
      style: inline.style,
      startCfi: inline.startCfi,
      footnotes: const [
        PageFootnote(start: 3, end: 4, label: '①', kind: NoteKind.footnote),
      ],
      inlineImages: const [InlineImageSpec(offset: 5, url: 'image.png')],
    ),
    PageBlock(
      layout: ruby.layout,
      style: ruby.style,
      startCfi: ruby.startCfi,
      rubies: const [RubyAnnotation(start: 0, end: 2, text: '注音匹配')],
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('样式和顺序变化复用真实匹配，只重算条件变化的规则', () async {
    final matcher = _CountingMatcher();
    final engine = ReaderDecorationRuleEngine(matcher: matcher);
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('甲乙甲', _baseCfi)]),
    ];
    final firstRule = _rule('first', '甲');
    final secondRule = _rule('second', '乙').copyWith(sortOrder: 1);
    final first = await _match(engine, pages, [firstRule, secondRule]);
    expect(matcher.calls, ['甲', '乙']);
    final styled = firstRule.copyWith(
      sortOrder: 2,
      style: const ReaderDecorationRuleStyle(
        color: 0xff0000ff,
        typography: ReaderDecorationStyle(fontSizeScale: 1.5),
        darkStyle: ReaderDecorationRuleStyle(color: 0xff00ff00),
      ),
    );
    final restyled = await _match(engine, pages, [styled, secondRule]);
    expect(matcher.calls, ['甲', '乙']);
    expect(restyled.map((hit) => hit.ruleId), ['second', 'first', 'first']);
    expect(restyled.last.startCfi, first[1].startCfi);
    expect(restyled.last.endCfi, first[1].endCfi);
    expect(restyled.last.style, same(styled.style));
    expect(restyled.last.style.forTheme(true).color, 0xff00ff00);
    expect(first.last.style, same(secondRule.style));
    final changed = await _match(engine, pages, [
      styled.copyWith(pattern: '甲乙'),
      secondRule,
    ]);
    expect(matcher.calls, ['甲', '乙', '甲乙']);
    expect(changed.map((hit) => hit.text), ['乙', '甲乙']);
  });

  test('进行中的规则被样式修改复用，两个请求分别保留各自样式', () async {
    final matcher = _CountingMatcher();
    final engine = ReaderDecorationRuleEngine(matcher: matcher);
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('正文', _baseCfi)]),
    ];
    final rule = _rule('text', '正文');
    final updated = rule.copyWith(
      style: const ReaderDecorationRuleStyle(color: 0xff00ff00),
    );
    final original = _match(engine, pages, [rule]);
    final restyled = _match(engine, pages, [updated]);
    expect((await original).single.style, same(rule.style));
    expect((await restyled).single.style, same(updated.style));
    expect(matcher.calls, ['正文']);
  });

  test('切换单引号规则只让对话重新扣除词组，其他规则继续复用', () async {
    final matcher = _CountingMatcher();
    final engine = ReaderDecorationRuleEngine(matcher: matcher);
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('“甲‘乙’丙”', _baseCfi)]),
    ];
    final dialogue = _rule(
      'dialogue',
      '',
    ).copyWith(type: ReaderDecorationRuleType.doubleQuoteDialogue);
    final word = _rule('word', '甲');
    final single = _rule(
      'single',
      '',
    ).copyWith(type: ReaderDecorationRuleType.singleQuotePhrase);
    expect(
      (await _match(engine, pages, [dialogue, word])).first.text,
      '“甲‘乙’丙”',
    );
    final withSingle = await _match(engine, pages, [dialogue, word, single]);
    expect(withSingle.map((hit) => hit.text), ['“甲', '丙”', '甲', '‘乙’']);
    expect(matcher.calls, ['', '甲', '', '']);
    final restored = await _match(engine, pages, [
      dialogue,
      word,
      single.copyWith(enabled: false),
    ]);
    expect(restored.first.text, '“甲‘乙’丙”');
    expect(matcher.calls, ['', '甲', '', '', '']);
  });

  test('原文、排除区间和来源位置变化不会复用旧命中', () async {
    final matcher = _CountingMatcher();
    final engine = ReaderDecorationRuleEngine(matcher: matcher);
    addTearDown(engine.dispose);
    Future<List<ReaderDecorationRuleMatch>> match(
      DecorationRuleTextBlock block,
    ) => engine.matchChapter(
      pages: const [],
      sourceBlocks: [block],
      groups: _groups,
      rules: [_rule('text', '正文')],
      bookId: 'book',
    );
    final first = await match(
      const DecorationRuleTextBlock(cfi: _baseCfi, text: '正文'),
    );
    final moved = await match(
      DecorationRuleTextBlock(cfi: cfiWithCharOffset(_baseCfi, 20), text: '正文'),
    );
    expect(cfiCharOffset(first.single.startCfi), 7);
    expect(cfiCharOffset(moved.single.startCfi), 20);
    expect(
      await match(const DecorationRuleTextBlock(cfi: _baseCfi, text: '原文')),
      isEmpty,
    );
    expect(
      await match(
        const DecorationRuleTextBlock(
          cfi: _baseCfi,
          text: '正文',
          excluded: [(0, 1)],
        ),
      ),
      isEmpty,
    );
    expect(matcher.calls, hasLength(4));
  });

  test('跨段边界和作者保护范围变化使对话缓存失效', () async {
    final matcher = _CountingMatcher();
    final engine = ReaderDecorationRuleEngine(matcher: matcher);
    addTearDown(engine.dispose);
    Future<List<ReaderDecorationRuleMatch>> match({
      int boundary = 0,
      List<(int, int)> protected = const [],
    }) => engine.matchChapter(
      pages: const [],
      sourceBlocks: [
        DecorationRuleTextBlock(
          cfi: _baseCfi,
          text: '“开头',
          protected: protected,
        ),
        DecorationRuleTextBlock(
          cfi: 'epubcfi(/6/2!/4/4/1:0)',
          text: '结尾”',
          boundary: boundary,
        ),
      ],
      groups: _groups,
      rules: [
        _rule(
          'dialogue',
          '',
        ).copyWith(type: ReaderDecorationRuleType.doubleQuoteDialogue),
      ],
      bookId: 'book',
    );
    expect((await match()).map((hit) => hit.text), ['“开头', '结尾”']);
    expect((await match(boundary: 1)).map((hit) => hit.text), ['“开头']);
    expect((await match(protected: [(1, 3)])).map((hit) => hit.text), [
      '“',
      '结尾”',
    ]);
    expect(matcher.calls, hasLength(3));
  });

  test('失败规则改样式不重试，修改匹配条件后恢复且复用其他规则', () async {
    final matcher = _CountingMatcher();
    final engine = ReaderDecorationRuleEngine(matcher: matcher);
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('正文', _baseCfi)]),
    ];
    final invalid = _rule('invalid', '(', isRegex: true);
    final valid = _rule('valid', '正文');
    await _match(engine, pages, [invalid, valid]);
    await _match(engine, pages, [
      invalid.copyWith(style: const ReaderDecorationRuleStyle(color: 1)),
      valid,
    ]);
    expect(matcher.calls, ['(', '正文']);
    final fixed = await _match(engine, pages, [
      invalid.copyWith(pattern: '正文'),
      valid,
    ]);
    expect(fixed, hasLength(2));
    expect(matcher.calls, ['(', '正文', '正文']);
    expect(engine.errors, isEmpty);
  });

  for (final (isRegex, caseSensitive, offsets) in [
    (false, false, [(0, 3), (4, 7)]),
    (false, true, [(0, 3)]),
    (true, false, [(0, 3), (4, 7), (8, 11)]),
  ]) {
    test('文本与正则模式保留字面量语义，区分大小写=$caseSensitive，正则=$isRegex', () async {
      final matcher = DecorationRuleMatcher();
      addTearDown(matcher.dispose);
      final matches = await matcher.match(
        pattern: 'a.c',
        isRegex: isRegex,
        caseSensitive: caseSensitive,
        blocks: const [
          DecorationRuleTextBlock(cfi: _baseCfi, text: 'a.c A.C axc'),
        ],
      );
      expect(matches.map((match) => (match.start, match.end)), offsets);
    });
  }

  test('Unicode 正则匹配单个补充平面字符，偏移保持 UTF-16', () async {
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    final matches = await matcher.match(
      pattern: r'^.$',
      isRegex: true,
      caseSensitive: true,
      blocks: const [DecorationRuleTextBlock(cfi: _baseCfi, text: '😀')],
    );
    expect(matches.map((match) => (match.start, match.end)), [(0, 2)]);
  });

  test('正则命中保留图片背景和铺放样式，预览与正文区间一致', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('前甲中乙23后', _baseCfi)]),
    ];
    final rule = _rule('image', r'甲|乙\d+', isRegex: true).copyWith(
      style: const ReaderDecorationRuleStyle(
        backgroundImagePath: '/local/texture.png',
        backgroundImageFit: ReaderDecorationImageFit.tile,
        backgroundOpacity: 0.4,
        borderRadius: 3,
      ),
    );
    final matches = await _match(engine, pages, [rule]);
    expect(matches.map((match) => match.text), ['甲', '乙23']);
    expect(
      matches.every(
        (match) =>
            match.style.decorationStyle.backgroundImagePath ==
            '/local/texture.png',
      ),
      isTrue,
    );
    expect(
      matches.first.style.decorationStyle.backgroundImageFit,
      ReaderDecorationImageFit.tile,
    );
    expect(matches.first.style.decorationStyle.backgroundOpacity, 0.4);
    final previews = await engine.preview(rule, pages);
    expect(
      previews.map((preview) => preview.startCfi),
      matches.map((match) => match.startCfi),
    );
    expect(
      previews.map((preview) => preview.endCfi),
      matches.map((match) => match.endCfi),
    );
    expect(previews.first.style.toJson(), matches.first.style.toJson());
    expect(
      await _match(engine, pages, [rule.copyWith(isRegex: false)]),
      isEmpty,
    );
  });

  test('无效正则不会阻止同一匹配器继续执行有效规则', () async {
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    const blocks = [DecorationRuleTextBlock(cfi: _baseCfi, text: '正文')];
    await expectLater(
      matcher.match(
        pattern: '(',
        isRegex: true,
        caseSensitive: false,
        blocks: blocks,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          '提示',
          contains('正则格式无效'),
        ),
      ),
    );
    final matches = await matcher.match(
      pattern: '正文',
      isRegex: false,
      caseSensitive: false,
      blocks: blocks,
    );
    expect(matches.map((match) => (match.start, match.end)), [(0, 2)]);
  });

  test('真实回溯工作 isolate 在默认一秒期限被终止，父 isolate 仍可响应', () async {
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    var heartbeats = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => heartbeats++,
    );
    addTearDown(heartbeat.cancel);
    final stopwatch = Stopwatch()..start();
    await expectLater(
      matcher.match(
        pattern: r'(a+)+$',
        isRegex: true,
        caseSensitive: true,
        blocks: [DecorationRuleTextBlock(cfi: _baseCfi, text: '${'a' * 64}!')],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          '提示',
          contains('超过 1 秒'),
        ),
      ),
    );
    stopwatch.stop();
    heartbeat.cancel();
    expect(stopwatch.elapsedMilliseconds, inInclusiveRange(900, 5000));
    expect(heartbeats, greaterThan(3));
  });

  test('可配置短期限杀掉回溯 isolate，随后规则立即正常返回', () async {
    final matcher = DecorationRuleMatcher();
    addTearDown(matcher.dispose);
    await expectLater(
      matcher.match(
        pattern: r'(a+)+$',
        isRegex: true,
        caseSensitive: true,
        blocks: [DecorationRuleTextBlock(cfi: _baseCfi, text: '${'a' * 64}!')],
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          '提示',
          contains('会话已跳过'),
        ),
      ),
    );
    final matches = await matcher.match(
      pattern: '正文',
      isRegex: false,
      caseSensitive: false,
      blocks: const [DecorationRuleTextBlock(cfi: _baseCfi, text: '正文')],
    );
    expect(matches, hasLength(1));
  });

  test('超时只跳过该规则，同会话清缓存不重试，修改条件后恢复', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final bad = _rule('slow', r'(a+)+$', isRegex: true).copyWith(sortOrder: -1);
    final good = _rule('good', '正文');
    final pages = [
      _page([_block('${'a' * 64}!正文', _baseCfi)]),
    ];
    final rules = [bad, good];
    final first = _match(engine, pages, rules);
    expect(_match(engine, pages, rules), same(first));
    expect((await first).map((match) => match.ruleId), ['good']);
    expect(engine.errors['slow'], contains('会话已跳过'));
    engine.clearCache();
    final stopwatch = Stopwatch()..start();
    expect((await _match(engine, pages, rules)).map((match) => match.ruleId), [
      'good',
    ]);
    expect(stopwatch.elapsedMilliseconds, lessThan(900));
    final restored = bad.copyWith(pattern: '正文', isRegex: false);
    expect(
      (await _match(engine, pages, [
        restored,
        good,
      ])).map((match) => match.ruleId),
      ['slow', 'good'],
    );
    expect(engine.errors, isEmpty);
  });

  test('无效正则在规则卡片标错，其余规则和修改后的规则继续生效', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('正文', _baseCfi)]),
    ];
    final invalid = _rule('invalid', '(', isRegex: true);
    final matches = await _match(engine, pages, [invalid, _rule('good', '正文')]);
    expect(matches.map((match) => match.ruleId), ['good']);
    expect(engine.errors['invalid'], contains('正则格式无效'));
    await _match(engine, pages, [invalid.copyWith(pattern: '正文')]);
    expect(engine.errors, isEmpty);
  });

  test('正文与各字号标题可匹配，脚注表格页家具及引用图片注音均排除', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final pages = [_page(_filteredBlocks())];
    final blocks = ReaderDecorationRuleEngine.textBlocks(pages);
    expect(blocks, hasLength(5));
    expect(
      blocks.map((block) => block.text),
      containsAll(['正文匹配', '一级标题匹配', '六级标题匹配', '汉字匹配']),
    );
    final matches = await _match(engine, pages, [_rule('reading', '匹配')]);
    expect(matches, hasLength(6));
    final excluded = await _match(engine, pages, [
      _rule('excluded', '①|\uFFFC|脚注|表格|页眉|页脚|注音|匹配①后', isRegex: true),
    ]);
    expect(excluded, isEmpty);
  });

  test('零长正则不生成装饰，文本匹配不跨原文块', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final pages = [
      _page([_block('第一', _baseCfi), _block('第二', 'epubcfi(/6/2!/4/2/3)')]),
    ];
    expect(await _match(engine, pages, [_rule('cross', '一第')]), isEmpty);
    expect(
      await _match(engine, pages, [_rule('zero', '^', isRegex: true)]),
      isEmpty,
    );
  });

  test('同原文块跨页列片段按 CFI 复原，命中不丢偏移或重复', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final first = _block('AB', _baseCfi);
    final second = _block('CD', cfiWithCharOffset(_baseCfi, 9));
    final pages = [
      _page([second], index: 1),
      _page([first]),
      _page([first]),
    ];
    final blocks = ReaderDecorationRuleEngine.textBlocks(pages);
    expect(blocks.single.text, 'ABCD');
    final matches = await _match(engine, pages, [_rule('joined', 'BCD')]);
    expect(matches.single.text, 'BCD');
    expect(cfiCharOffset(matches.single.startCfi), 8);
    expect(cfiCharOffset(matches.single.endCfi), 11);
  });

  test('全局和本书先普通组后默认组，组内排序且禁用及他书规则不生效', () {
    const groups = [
      ReaderDecorationRuleGroup(
        id: 'bd',
        name: '本书默认',
        bookId: 'book',
        isDefault: true,
        sortOrder: -10,
      ),
      ReaderDecorationRuleGroup(
        id: 'b',
        name: '本书',
        bookId: 'book',
        sortOrder: 10,
      ),
      ReaderDecorationRuleGroup(
        id: 'gd',
        name: '全局默认',
        isDefault: true,
        sortOrder: -100,
      ),
      ReaderDecorationRuleGroup(id: 'g2', name: '全局二', sortOrder: 2),
      ReaderDecorationRuleGroup(id: 'g1', name: '全局一', sortOrder: 1),
      ReaderDecorationRuleGroup(id: 'off', name: '禁用', enabled: false),
      ReaderDecorationRuleGroup(id: 'other', name: '别书', bookId: 'other'),
    ];
    final rules = [
      for (final group in groups)
        _rule(group.id, '正文').copyWith(groupId: group.id),
      _rule('g2-first', '正文').copyWith(groupId: 'g2', sortOrder: -1),
      _rule('disabled', '正文').copyWith(groupId: 'g1', enabled: false),
    ];
    final ordered = ReaderDecorationRuleEngine.orderedRules(
      groups: groups,
      rules: rules,
      bookId: 'book',
    );
    expect(ordered.map((rule) => rule.id), [
      'g1',
      'g2-first',
      'g2',
      'gd',
      'b',
      'bd',
    ]);
    expect(groups.first.id, 'bd');
    expect(rules.first.id, 'bd');
  });

  test('预览只返回前50条，不改规则或章缓存完整命中，也不产生存储对象', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final rule = _rule('preview', '文');
    final pages = [
      _page([_block('文' * 60, _baseCfi)]),
    ];
    final preview = await engine.preview(rule, pages);
    expect(preview, hasLength(50));
    expect(cfiCharOffset(preview.first.startCfi), 7);
    expect(cfiCharOffset(preview.last.endCfi), 57);
    expect(preview.every((hit) => identical(hit.style, rule.style)), isTrue);
    expect(rule.pattern, '文');
    expect(rule.enabled, isTrue);
    expect(
      await _match(engine, pages, List.unmodifiable([rule])),
      hasLength(60),
    );
    expect(engine.errors, isEmpty);
  });

  test('规则预览拒绝无效正则并保留会话错误提示', () async {
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    await expectLater(
      engine.preview(_rule('invalid', '(', isRegex: true), [
        _page([_block('正文', _baseCfi)]),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          '提示',
          contains('正则格式无效'),
        ),
      ),
    );
    expect(engine.errors['invalid'], contains('正则格式无效'));
  });
}
