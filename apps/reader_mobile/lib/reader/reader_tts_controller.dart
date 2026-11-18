import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

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
  ReaderTtsController({required this.textProvider, required this.nextPage});

  final Future<String> Function() textProvider;
  final Future<bool> Function() nextPage;
  FlutterTts? _tts;
  bool _speaking = false;
  int _generation = 0;

  /// 是否正在朗读。
  bool get speaking => _speaking;

  /// 状态变化回调。
  void Function(bool speaking)? onStateChanged;

  /// 错误回调。
  void Function(Object error)? onError;

  /// 开始朗读；已在朗读时会先停止再重新开始。
  Future<void> start(ReaderTtsSettings settings) async {
    await stop();
    final generation = ++_generation;
    _speaking = true;
    onStateChanged?.call(true);
    try {
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
        final segments = _segments(text);
        if (segments.isEmpty) break;
        for (final segment in segments) {
          if (!_speaking || generation != _generation) return;
          await tts.speak(segment);
        }
        if (!settings.autoTurnPage || !_speaking) break;
        final advanced = await nextPage();
        if (!advanced) break;
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } catch (error) {
      onError?.call(error);
    } finally {
      if (generation == _generation) {
        _speaking = false;
        onStateChanged?.call(false);
      }
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
  }

  /// 释放语音引擎。
  Future<void> dispose() async {
    await stop();
    _tts = null;
    onStateChanged = null;
    onError = null;
  }

  /// 按句切分，过长的句子再按逗号与空格切短。
  static List<String> _segments(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const <String>[];
    final sentences = RegExp(r'[^。！？!?；;]+[。！？!?；;]?')
        .allMatches(normalized)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final result = <String>[];
    for (final sentence in sentences) {
      if (sentence.length <= 160) {
        result.add(sentence);
        continue;
      }
      final parts = sentence.split(RegExp(r'(?<=[，,、：:\s])'));
      var buffer = '';
      for (final part in parts) {
        if (buffer.isNotEmpty && buffer.length + part.length > 160) {
          result.add(buffer.trim());
          buffer = '';
        }
        buffer += part;
      }
      if (buffer.trim().isNotEmpty) result.add(buffer.trim());
    }
    return result;
  }
}
