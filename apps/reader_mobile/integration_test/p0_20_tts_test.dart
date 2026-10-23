import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P0-20 平台 TTS 可用性与中文朗读回调', (tester) async {
    final tts = FlutterTts();
    addTearDown(tts.stop);

    final languages = await tts.getLanguages;
    final languageList = languages is List ? languages : const <dynamic>[];
    final chinese = languageList
        .where((item) => '$item'.toLowerCase().contains('zh'))
        .map((item) => '$item')
        .toList();

    final available = await tts.isLanguageAvailable('zh-CN');
    await tts.setLanguage('zh-CN');
    final rateResults = <String>[];
    for (final rate in <double>[0.1, 0.5, 0.9]) {
      final applied = await tts.setSpeechRate(rate);
      rateResults.add('$rate:$applied');
    }
    await tts.setVolume(0.6);
    await tts.awaitSpeakCompletion(true);

    final stopwatch = Stopwatch()..start();
    var speakTimedOut = false;
    Object? speakResult;
    try {
      speakResult = await tts
          .speak('这是中文字体朗读测试。')
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      speakTimedOut = true;
      speakResult = 0;
      await tts.stop();
    }
    stopwatch.stop();

    final voices = await tts.getVoices;
    final voiceCount = voices is List ? voices.length : 0;

    // ignore: avoid_print
    print(
      'P0-20 platform=${defaultTargetPlatform.name} '
      'languages=${languageList.length} chinese=$chinese '
      'zh_cn_available=$available voices=$voiceCount rates=$rateResults '
      'speak_result=$speakResult speak_timeout=$speakTimedOut '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );

    expect(languageList, isNotEmpty);
    expect(chinese, isNotEmpty);
    expect(available, isTrue);
    expect(
      speakResult,
      isNot(0),
      reason: speakTimedOut ? 'TTS speak 8 秒未回调（设备引擎可能崩溃/无语音）' : null,
    );
  });
}
