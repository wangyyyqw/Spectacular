import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'reader_offline_tts.dart';
import 'reader_settings.dart';

/// 系统语音引擎提供的一种朗读音色。
class ReaderTtsVoice {
  /// 创建音色项。
  const ReaderTtsVoice({
    required this.name,
    required this.locale,
    this.quality = '',
  });

  /// 语音引擎中的音色名称。
  final String name;

  /// 语言区域，例如 `zh-CN`。
  final String locale;

  /// 音质描述；部分引擎为空。
  final String quality;

  /// 设置中保存用的稳定标识。
  String get key => '$name|$locale';

  /// 界面显示文字。
  String get label {
    final suffix = quality.trim();
    return suffix.isEmpty ? '$name · $locale' : '$name · $locale · $suffix';
  }
}

/// 读取系统可用的朗读音色；存在中文音色时只返回中文音色。
Future<List<ReaderTtsVoice>> loadReaderTtsVoices() async {
  try {
    final raw = await FlutterTts().getVoices;
    if (raw is! List<Object?>) return const <ReaderTtsVoice>[];
    final voices = <ReaderTtsVoice>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map<Object?, Object?>) continue;
      final name = item['name']?.toString().trim() ?? '';
      final locale = item['locale']?.toString().trim() ?? '';
      if (name.isEmpty || locale.isEmpty) continue;
      if (!seen.add('$name|$locale')) continue;
      voices.add(
        ReaderTtsVoice(
          name: name,
          locale: locale,
          quality: item['quality']?.toString() ?? '',
        ),
      );
    }
    if (voices.isEmpty) return const <ReaderTtsVoice>[];
    final chinese = voices
        .where((voice) => voice.locale.toLowerCase().startsWith('zh'))
        .toList(growable: false);
    final result = chinese.isEmpty ? voices : chinese;
    result.sort((left, right) => left.label.compareTo(right.label));
    return result;
  } catch (_) {
    return const <ReaderTtsVoice>[];
  }
}

/// 分页听书控制：逐段朗读当前页，读完后按需自动翻页。
class ReaderTtsController {
  /// 创建控制器。
  ReaderTtsController({
    required this.textProvider,
    required this.nextPage,
    this.offlineSynthesizer,
    this.player,
    this.resolveOfflineVoice,
  });

  final Future<String> Function() textProvider;
  final Future<bool> Function() nextPage;

  /// 离线合成器；为空时离线模式会回退到系统语音。
  final ReaderOfflineTtsSynthesizer? offlineSynthesizer;

  /// 离线音频播放器。
  final ReaderTtsPlayer? player;

  /// 按音色标识读取本地模型。
  final Future<ReaderOfflineVoiceInstance?> Function(String id)?
  resolveOfflineVoice;

  FlutterTts? _tts;
  bool _speaking = false;
  int _generation = 0;

  /// 是否正在朗读。
  bool get speaking => _speaking;

  /// 状态变化回调。
  void Function(bool speaking)? onStateChanged;

  /// 错误回调。
  void Function(Object error)? onError;

  /// 离线语音不可用并回退到系统语音时的提示。
  void Function(String message)? onFallback;

  /// 开始朗读；已在朗读时会先停止再重新开始。
  Future<void> start(ReaderTtsSettings settings) async {
    await stop();
    final generation = ++_generation;
    _speaking = true;
    onStateChanged?.call(true);
    try {
      if (settings.mode == ReaderTtsMode.offline) {
        try {
          await _startOffline(settings, generation);
          return;
        } catch (error) {
          if (!_speaking || generation != _generation) return;
          onFallback?.call('离线伴听不可用，已切换系统语音：$error');
        }
      }
      await _startSystem(settings, generation);
    } catch (error) {
      onError?.call(error);
    } finally {
      if (generation == _generation) {
        _speaking = false;
        onStateChanged?.call(false);
      }
    }
  }

  Future<void> _startSystem(ReaderTtsSettings settings, int generation) async {
    final tts = _tts ??= FlutterTts();
    await tts.awaitSpeakCompletion(true);
    await tts.setLanguage('zh-CN');
    if (settings.hasVoice) {
      try {
        await tts.setVoice(<String, String>{
          'name': settings.voiceName,
          'locale': settings.voiceLocale,
        });
      } catch (_) {
        // 系统移除了已选音色时退回默认中文音色。
      }
    }
    await tts.setSpeechRate(settings.rate.clamp(0.1, 1));
    await tts.setPitch(settings.pitch.clamp(0.5, 2));
    await tts.setVolume(settings.volume.clamp(0, 1));
    while (_speaking && generation == _generation) {
      final text = (await textProvider()).trim();
      final segments = ReaderTtsSegmentation.split(text);
      if (segments.isEmpty) break;
      for (final segment in segments) {
        if (!_speaking || generation != _generation) return;
        await tts.speak(segment.text);
      }
      if (!settings.autoTurnPage || !_speaking) break;
      final advanced = await nextPage();
      if (!advanced) break;
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  Future<void> _startOffline(ReaderTtsSettings settings, int generation) async {
    final synthesizer = offlineSynthesizer;
    final audioPlayer = player;
    final resolver = resolveOfflineVoice;
    if (synthesizer == null || audioPlayer == null || resolver == null) {
      throw StateError('离线伴听未配置');
    }
    if (!settings.hasOfflineVoice) throw StateError('尚未选择离线旁白音色');
    final narrator = await resolver(settings.narratorVoiceId);
    if (narrator == null) throw StateError('所选旁白音色尚未下载');
    ReaderOfflineVoiceInstance? dialogue;
    if (settings.dialogueVoiceId.trim().isNotEmpty &&
        settings.dialogueVoiceId != settings.narratorVoiceId) {
      dialogue = await resolver(settings.dialogueVoiceId);
    }
    await audioPlayer.stop();
    while (_speaking && generation == _generation) {
      final text = (await textProvider()).trim();
      final segments = ReaderTtsSegmentation.split(text);
      if (segments.isEmpty) break;
      final clips = await synthesizer.synthesize(
        segments: segments,
        narrator: narrator,
        dialogue: dialogue,
        settings: settings,
      );
      for (final clip in clips) {
        if (!_speaking || generation != _generation) return;
        await audioPlayer.play(clip);
      }
      if (!settings.autoTurnPage || !_speaking) break;
      final advanced = await nextPage();
      if (!advanced) break;
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  /// 停止朗读。
  Future<void> stop() async {
    _generation += 1;
    if (!_speaking) return;
    _speaking = false;
    onStateChanged?.call(false);
    try {
      await _tts?.stop();
    } catch (_) {
      // 平台语音引擎已释放时忽略停止错误。
    }
    try {
      await player?.stop();
    } catch (_) {
      // 播放器已释放时忽略停止错误。
    }
  }

  /// 释放语音引擎。
  Future<void> dispose() async {
    await stop();
    _tts = null;
    await player?.dispose();
    onStateChanged = null;
    onError = null;
    onFallback = null;
  }
}
