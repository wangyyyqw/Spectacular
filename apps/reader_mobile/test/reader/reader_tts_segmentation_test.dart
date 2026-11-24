import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';

void main() {
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
