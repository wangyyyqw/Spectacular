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
}
