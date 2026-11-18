import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_settings.dart';

void main() {
  test('听书音色随设置序列化并参与相等判断', () {
    const settings = ReaderTtsSettings(
      rate: 0.7,
      voiceName: 'zh-CN-Standard-A',
      voiceLocale: 'zh-CN',
    );
    final restored = ReaderTtsSettings.fromJson(settings.toJson());
    expect(restored, settings);
    expect(restored.hasVoice, isTrue);
    expect(restored.copyWith(voiceName: '', voiceLocale: '').hasVoice, isFalse);
  });

  test('旧设置缺少音色字段时使用系统默认', () {
    final restored = ReaderTtsSettings.fromJson(<String, Object?>{'rate': 0.6});
    expect(restored.hasVoice, isFalse);
    expect(restored.rate, 0.6);
  });
}
