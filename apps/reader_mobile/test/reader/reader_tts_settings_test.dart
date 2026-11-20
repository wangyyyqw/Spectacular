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
    expect(restored.mode, ReaderTtsMode.system);
    expect(restored.hasOfflineVoice, isFalse);
  });

  test('离线伴听设置可持久化并保持旧字段', () {
    const settings = ReaderTtsSettings(
      mode: ReaderTtsMode.offline,
      rate: 0.65,
      voiceName: '系统音色',
      voiceLocale: 'zh-CN',
      narratorVoiceId: 'vits-piper-zh_CN-chaowen-medium',
      dialogueVoiceId: 'vits-piper-zh_CN-xiao_ya-medium',
      narratorSpeed: 1.2,
      dialogueSpeed: 0.9,
      narratorSpeakerId: 2,
    );
    final restored = ReaderTtsSettings.fromJson(settings.toJson());
    expect(restored, settings);
    expect(restored.mode, ReaderTtsMode.offline);
    expect(restored.hasOfflineVoice, isTrue);
    expect(restored.hasVoice, isTrue);
  });

  test('切换日夜配色保留听书偏好', () {
    const tts = ReaderTtsSettings(
      mode: ReaderTtsMode.offline,
      narratorVoiceId: 'vits-piper-zh_CN-chaowen-medium',
      dialogueSpeed: 0.9,
    );
    final settings = ReaderSettings.defaults
        .copyWithTts(tts)
        .copyWithTheme('sepia')
        .copyWithTheme('moss');
    expect(settings.tts, tts);
    expect(settings.dayThemeId, 'sepia');
    expect(settings.nightThemeId, 'moss');
  });

  test('离线语速与说话人越界值会收敛', () {
    final restored = ReaderTtsSettings.fromJson(<String, Object?>{
      'narratorSpeed': 9,
      'dialogueSpeed': 0,
      'narratorSpeakerId': 1200,
    });
    expect(restored.narratorSpeed, 2);
    expect(restored.dialogueSpeed, 0.5);
    expect(restored.narratorSpeakerId, 999);
  });
}
