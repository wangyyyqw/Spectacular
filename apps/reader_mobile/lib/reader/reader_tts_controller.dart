import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'reader_settings.dart';

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
