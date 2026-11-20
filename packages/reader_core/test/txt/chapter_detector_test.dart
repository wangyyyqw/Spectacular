import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/txt.dart';

void main() {
  test('明确启用的个人规则优先于内置规则，支持卷章重置', () {
    final body = '普通正文' * 30;
    const options = ChapterDetectionOptions(
      autoRules: [
        ChapterRule(
          id: 'mine',
          name: '章作为卷',
          pattern: '不使用',
          volumePattern: r'第[一二]章',
          autoEnabled: true,
        ),
      ],
    );
    final result = ChapterDetector.detect([
      '第一章',
      '1、开始',
      body,
      '2、继续',
      body,
      '第二章',
      '1、新章',
      body,
      '2、结束',
      body,
    ], options: options);
    expect(result.boundaries.where((boundary) => boundary.isVolume).length, 2);
    expect(result.boundaries.length, 6);
  });
  test('首行标题、简繁数字、英文罗马数和卷章混排', () async {
    final result = await ChapterDetector.preview([
      '第一章 开始',
      '正文。',
      '第貳回 重逢',
      '正文。',
      '第三卷 新卷',
      '第１章 起点',
      '正文。',
      'CHAPTER IV End',
      '正文。',
      '第一卷 第十二章 同行标题',
      '正文。',
      '尾声',
    ]);
    expect(result.boundaries.map((item) => item.blockIndex), [
      0,
      2,
      4,
      5,
      7,
      9,
      11,
    ]);
    expect(
      result.boundaries
          .where((item) => item.isVolume)
          .map((item) => item.title),
      ['第三卷 新卷'],
    );
  });

  test('单章和短章不因字数或标题数量少而丢失', () {
    final result = ChapterDetector.detect(['第一章 开始', '完。']);
    expect(result.boundaries.single.title, '第一章 开始');
    expect(result.boundaries.single.synthetic, isFalse);
    expect(result.warnings, isNotEmpty);
  });

  test('前言和末尾文本完整归属，正文编号列表不成章', () {
    final result = ChapterDetector.detect([
      '简介内容',
      '第一章 起点',
      '请带上：',
      '1、杯子',
      '2、纸笔',
      '3、书本',
      '第一节课开始了。',
      '第一个部分。',
      '12楼',
      '3.14',
      '2026-11-20',
      '第二章 终点',
      '剩余正文',
    ]);
    expect(result.boundaries.map((item) => item.title), [
      '前言',
      '第一章 起点',
      '第二章 终点',
    ]);
  });

  test('EPUB序列化留下的开头空白不生成空前言', () {
    final result = ChapterDetector.detect(['\n  ', '\t　', '第一章 开始', '正文内容']);
    expect(result.boundaries, hasLength(1));
    expect(result.boundaries.single.blockIndex, 2);
    expect(result.boundaries.single.title, '第一章 开始');
    expect(result.boundaries.single.synthetic, isFalse);
  });

  test('相同格式且连续编号的弱标题能够识别', () {
    final body = '一段普通正文' * 30;
    final result = ChapterDetector.detect([
      '1、开始',
      body,
      '2、继续',
      body,
      '3、结束',
      body,
    ]);
    expect(result.boundaries.map((item) => item.title), [
      '1、开始',
      '2、继续',
      '3、结束',
    ]);
  });

  test('书首清单在后文重复才排除切点，前言文本仍保留', () {
    final result = ChapterDetector.detect([
      '目录',
      '第一章 开始',
      '第二章 继续',
      '第三章 结束',
      '以下正文',
      '第一章 开始',
      '正文第一章',
      '第二章 继续',
      '正文第二章',
      '第三章 结束',
      '正文第三章',
    ]);
    expect(result.boundaries.map((item) => item.blockIndex), [0, 5, 7, 9]);
    expect(result.boundaries.first.title, '前言');
  });

  test('自定义按完整行匹配，不混入内置规则且不要求捕获组', () async {
    const options = ChapterDetectionOptions(
      mode: ChapterDetectionMode.custom,
      rule: ChapterRule(id: 'mine', name: '自定义', pattern: r'段落[一二三]'),
    );
    final result = await ChapterDetector.preview([
      '前文',
      '段落一',
      '第一章',
      '文字段落二文字',
      '段落三',
    ], options: options);
    expect(result.boundaries.map((item) => item.blockIndex), [0, 1, 4]);
  });

  test('自定义无匹配不偷偷变为按长度分节', () {
    final result = ChapterDetector.detect(
      ['普通文字'],
      options: const ChapterDetectionOptions(
        mode: ChapterDetectionMode.custom,
        rule: ChapterRule(id: 'none', name: '无结果', pattern: r'章节\d+'),
      ),
    );
    expect(result.boundaries, isEmpty);
  });

  test('自定义规则可以匹配原始缩进，标题显示去掉首尾空白', () {
    final result = ChapterDetector.detect(
      ['　　章一', '普通文字', '章二'],
      options: const ChapterDetectionOptions(
        mode: ChapterDetectionMode.custom,
        rule: ChapterRule(id: 'indent', name: '缩进章', pattern: r'　{2}章.'),
      ),
    );
    expect(result.boundaries.single.title, '章一');
    expect(result.boundaries.single.blockIndex, 0);
  });

  test('连续年份日期不被宽松数字规则识别为章节', () {
    final body = '普通正文' * 30;
    final result = ChapterDetector.detect([
      '2024-11-20',
      body,
      '2025-11-20',
      body,
      '2026-11-20',
      body,
    ]);
    expect(result.boundaries.every((boundary) => boundary.synthetic), isTrue);
  });

  test('无标题按完整块分节，重分章不拆复杂块', () async {
    final result = await ChapterDetector.preview([
      '甲' * 6000,
      '乙' * 6000,
      '丙' * 6000,
    ]);
    expect(result.boundaries.map((item) => item.blockIndex), [0, 2]);
    final filtered = await ChapterDetector.preview(
      ['第一章', '第二章', '第三章'],
      candidateBlockIndexes: {0, 2},
    );
    expect(filtered.boundaries.map((item) => item.blockIndex), [0, 2]);
  });

  test('强标题超长正文按完整块续节', () {
    final result = ChapterDetector.detect([
      '第一章',
      '甲' * 25000,
      '乙' * 25000,
      '丙',
    ]);
    expect(result.boundaries.map((item) => item.blockIndex), [0, 3]);
    expect(result.boundaries.last.synthetic, isTrue);
  });

  test('非法或可匹配空行的正则给明确错误', () async {
    for (final pattern in ['(', '.*', '']) {
      await expectLater(
        ChapterDetector.preview(
          ['正文'],
          options: ChapterDetectionOptions(
            mode: ChapterDetectionMode.custom,
            rule: ChapterRule(id: 'bad', name: '错误', pattern: pattern),
          ),
        ),
        throwsA(
          isA<TxtConversionException>().having(
            (error) => error.code,
            '错误码',
            'E_TXT_RULE',
          ),
        ),
      );
    }
  });

  test('保存规则校验与执行共用规则，不接受空行或不支持的内联标记', () {
    for (final pattern in ['.*', '', '(?im)^第一章']) {
      expect(
        () => ChapterDetector.validateRule(
          ChapterRule(id: 'invalid', name: '无效规则', pattern: pattern),
        ),
        throwsA(isA<TxtConversionException>()),
      );
    }
    expect(
      () => ChapterDetector.validateRule(
        const ChapterRule(
          id: 'volume',
          name: '空卷规则',
          pattern: '章.+',
          volumePattern: '.*',
        ),
      ),
      throwsA(isA<TxtConversionException>()),
    );
    expect(
      () => ChapterDetector.validateRule(
        const ChapterRule(
          id: 'valid',
          name: '有效规则',
          pattern: '章.+',
          volumePattern: '卷.+',
        ),
      ),
      returnsNormally,
    );
  });

  test('灾难回溯在后台被超时中断', () async {
    await expectLater(
      ChapterDetector.preview(
        ['${'a' * 100}b'],
        options: const ChapterDetectionOptions(
          mode: ChapterDetectionMode.custom,
          rule: ChapterRule(id: 'slow', name: '慢正则', pattern: r'(a+)+'),
        ),
      ),
      throwsA(
        isA<TxtConversionException>().having(
          (error) => error.code,
          '错误码',
          'E_TXT_REGEX_TIMEOUT',
        ),
      ),
    );
  });

  test('规则与选项JSON可重建', () {
    const options = ChapterDetectionOptions(
      mode: ChapterDetectionMode.custom,
      rule: ChapterRule(
        id: 'mine',
        name: '章节',
        pattern: r'章\d+',
        volumePattern: r'卷\d+',
        autoEnabled: true,
      ),
    );
    expect(
      ChapterDetectionOptions.fromJson(options.toJson()).toJson(),
      options.toJson(),
    );
  });
}
