import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';

void main() {
  test('连续单字强调连成完整词组，保留末尾语气与每个字的原文坐标', () {
    const text = '一百多个新配方全！部！学！习！接着制作。';
    final segments = ReaderTtsSegmentation.split(text);
    expect(segments.map((segment) => segment.text), ['一百多个新配方全部学习！', '接着制作。']);
    for (final segment in segments) {
      for (var i = 0; i < segment.text.length; i++) {
        expect(text[segment.rawStart(i)], segment.text[i]);
        expect(segment.rawEnd(i + 1), segment.rawStart(i) + 1);
      }
    }
    expect(
      segments.first.rawEnd(segments.first.text.length),
      text.indexOf('接'),
    );
  });

  test('强调支持中英文叹问号、连续标点和间隔空格，不切开扩展汉字', () {
    const text = '“全!! 部！ 学!? 习！！”他说。“怎？么?可？！能？”“𠀀！乙！丙！”';
    final segments = ReaderTtsSegmentation.split(text);
    expect(segments.map((segment) => segment.text), [
      '全部学习！！',
      '他说。',
      '怎么可能？',
      '𠀀乙丙！',
    ]);
    expect(segments.map((segment) => segment.isDialogue), [
      true,
      false,
      true,
      true,
    ]);
    expect(segments.last.sourceOffsets.take(2), [
      text.indexOf('𠀀'),
      text.indexOf('𠀀') + 1,
    ]);
  });

  test('普通短句、列举、引号和段落之间不作为单字强调合并', () {
    const text = '来！走！甲、乙、丙。好！“是！的！”全！部！学！习！';
    final segments = ReaderTtsSegmentation.split(
      text,
      paragraphStarts: [text.indexOf('学')],
    );
    expect(segments.map((segment) => segment.text), [
      '来！',
      '走！',
      '甲、乙、丙。',
      '好！',
      '是！',
      '的！',
      '全！',
      '部！',
      '学！',
      '习！',
    ]);
  });

  test('强调词组跨页仍按原文页末拆分并保留连续播放关系', () {
    const text = '全！部！学！习！';
    final segments = ReaderTtsSegmentation.split(
      text,
      pageEnds: [text.indexOf('部'), text.indexOf('习')],
    );
    expect(segments.map((segment) => segment.text), ['全', '部学', '习！']);
    expect(segments.map((segment) => segment.sourceOffsets), [
      [0],
      [2, 4],
      [6, 7],
    ]);
    expect(segments.map((segment) => segment.continuesOnNextPage), [
      true,
      true,
      false,
    ]);
  });

  test('短首句保持原分段，长首句在自然停顿拆开且保留对白原文坐标', () {
    final text = '“这是适合首先朗读的自然短语，${'后面的内容' * 16}。”下一句。';
    final original = ReaderTtsSegmentation.split(text);
    final split = ReaderTtsSegmentation.shortenLead(original, 0);
    expect(split.first.text, '这是适合首先朗读的自然短语，');
    expect(split.take(2).every((segment) => segment.isDialogue), isTrue);
    expect(
      split.map((segment) => segment.text).join(),
      original.map((segment) => segment.text).join(),
    );
    for (final segment in split) {
      expect(
        text.substring(
          segment.rawStart(0),
          segment.rawEnd(segment.text.length),
        ),
        segment.text,
      );
    }
    expect(
      identical(ReaderTtsSegmentation.shortenLead(split, 0), split),
      isTrue,
    );
  });

  test('跨页启动句的短分段保留前后页关系且不切开代理对', () {
    final text = '${'甲' * 39}😀${'乙' * 50}。';
    final original = ReaderTtsSegmentation.split(text, pageEnds: [20, 70]);
    final split = ReaderTtsSegmentation.shortenLead(original, 0);
    expect(split.map((segment) => segment.text).join(), text);
    expect(split.map((segment) => segment.continuesOnNextPage), [
      true,
      false,
      true,
      false,
    ]);
    expect(split.take(2).map((segment) => segment.text).join(), '甲' * 39);
    for (final segment in split) {
      expect(
        text.substring(
          segment.rawStart(0),
          segment.rawEnd(segment.text.length),
        ),
        segment.text,
      );
    }
  });

  test('中文弯引号拆出旁白与对白', () {
    final segments = ReaderTtsSegmentation.split('“你好。”他说。“走吧！”');
    expect(segments.map((segment) => segment.text).toList(), <String>[
      '你好。',
      '他说。',
      '走吧！',
    ]);
    expect(segments[0].isDialogue, isTrue);
    expect(segments[1].isDialogue, isFalse);
    expect(segments[2].isDialogue, isTrue);
  });

  test('直角引号和英文直引号可识别', () {
    final corner = ReaderTtsSegmentation.split('「坐吧。」她点头。');
    expect(corner.first.text, '坐吧。');
    expect(corner.first.isDialogue, isTrue);
    final straight = ReaderTtsSegmentation.split('他说："走吧。"');
    expect(straight.map((segment) => segment.text), <String>['他说：', '走吧。']);
    expect(straight.last.isDialogue, isTrue);
  });

  test('未闭合引号按对白朗读，不丢正文', () {
    final segments = ReaderTtsSegmentation.split('他说：“别停');
    expect(segments.map((segment) => segment.text).join(), '他说：别停');
    expect(segments.last.isDialogue, isTrue);
  });

  test('装饰分隔符被清理且长句被切短', () {
    final text = '${'很长的一段旁白，' * 40}※※※＊';
    final segments = ReaderTtsSegmentation.split(text);
    expect(segments, isNotEmpty);
    expect(segments.every((segment) => segment.text.length <= 160), isTrue);
    expect(segments.any((segment) => segment.text.contains('※')), isFalse);
  });

  test('无标点长串也限制长度并保留代理对', () {
    final text = '${'甲' * 159}😀${'乙' * 320}';
    final segments = ReaderTtsSegmentation.split(text);
    expect(segments.every((segment) => segment.text.length <= 160), isTrue);
    expect(segments.map((segment) => segment.text).join(), text);
    expect(segments.any((segment) => segment.text.contains('�')), isFalse);
    for (final segment in segments) {
      expect(
        text.substring(
          segment.rawStart(0),
          segment.rawEnd(segment.text.length),
        ),
        segment.text,
      );
    }
  });

  test('重复正文、引号与清理空白后仍对应各自原文偏移', () {
    const text = '  “相同。相同。”\n\n  旁白。';
    final segments = ReaderTtsSegmentation.split(text);
    expect(segments.map((segment) => segment.text), ['相同。', '相同。', '旁白。']);
    expect(segments.map((segment) => segment.rawStart(0)), [3, 6, 14]);
    expect(segments.map((segment) => segment.rawEnd(segment.text.length)), [
      6,
      9,
      17,
    ]);
  });

  test('页末拆分不吞下一页标点，保留对白、清理映射与代理对', () {
    const text = '  “甲😀乙！？丙丁。”\n\n旁白。';
    final segments = ReaderTtsSegmentation.split(
      text,
      paragraphStarts: [text.indexOf('旁白')],
      pageEnds: [text.indexOf('丙'), text.indexOf('？'), text.indexOf('😀') + 1],
    );
    expect(segments.map((segment) => segment.text), [
      '甲',
      '😀乙！',
      '？',
      '丙丁。',
      '旁白。',
    ]);
    expect(segments.take(4).every((segment) => segment.isDialogue), isTrue);
    expect(segments.last.isDialogue, isFalse);
    expect(segments.map((segment) => segment.continuesOnNextPage), [
      true,
      true,
      false,
      false,
      false,
    ]);
    for (final segment in segments) {
      expect(
        text.substring(
          segment.rawStart(0),
          segment.rawEnd(segment.text.length),
        ),
        segment.text,
      );
    }
  });
}
