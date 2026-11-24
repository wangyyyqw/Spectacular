import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/position/location_anchor.dart' show utf16Boundary;

import 'reader_settings.dart';

/// 系统语音引擎中的音色。
class ReaderTtsVoice {
  const ReaderTtsVoice({
    required this.name,
    required this.locale,
    this.quality = '',
  });
  final String name;
  final String locale;
  final String quality;

  String get key => '$name|$locale';
  String get label => quality.trim().isEmpty
      ? '$name · $locale'
      : '$name · $locale · ${quality.trim()}';
}

/// 一个系统实例统一处理音色查询与朗读，避免插件的全局通道覆盖回调。
class ReaderSystemTts {
  FlutterTts? _tts;
  Future<void>? _initialization;
  Completer<bool>? _completion;
  String _text = '';
  bool _paused = false;
  bool _nativePaused = false;
  bool _started = false;
  int _offset = 0;
  void Function()? _onStarted;
  void Function(int start, int end)? _onProgress;

  Future<void> _initialize() => _initialization ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    final tts = _tts ??= FlutterTts();
    tts.setStartHandler(_startedSpeaking);
    tts.setContinueHandler(_startedSpeaking);
    tts.setCompletionHandler(() => _finish(true));
    tts.setErrorHandler((message) => _fail(StateError('系统语音引擎错误：$message')));
    tts.setCancelHandler(() {
      if (_started && !_paused) _fail(StateError('系统语音已中断'));
    });
    tts.setProgressHandler(_progress);
    // 暂停/取消在各平台的完成 Future 行为不同，用独立等待者管理结束。
    await tts.awaitSpeakCompletion(false);
  }

  void _startedSpeaking() {
    if (_completion == null || _completion!.isCompleted || _paused) return;
    _started = true;
    _nativePaused = false;
    _onStarted?.call();
  }

  void _progress(String text, int start, int end, String word) {
    if (_completion == null ||
        _completion!.isCompleted ||
        _paused ||
        !_text.endsWith(text)) {
      return;
    }
    final base = _text.length - text.length;
    _offset = utf16Boundary(_text, (base + start).clamp(0, _text.length));
    final until = utf16Boundary(
      _text,
      (base + end).clamp(_offset, _text.length),
      forward: true,
    );
    if (!_started && until > _offset) _startedSpeaking();
    if (until > _offset) _onProgress?.call(_offset, until);
  }

  void _finish(bool completed) {
    final wait = _completion;
    if (wait == null || wait.isCompleted) return;
    if (completed) {
      _text = '';
      _offset = 0;
      _nativePaused = false;
    }
    wait.complete(completed);
  }

  void _fail(Object error) {
    final wait = _completion;
    if (wait != null && !wait.isCompleted) wait.completeError(error);
  }

  Future<List<ReaderTtsVoice>> voices() async {
    await _initialize();
    final raw = await _tts!.getVoices;
    if (raw is! List) return const [];
    final voices = <String, ReaderTtsVoice>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final name = '${item['name'] ?? ''}'.trim();
      final locale = '${item['locale'] ?? ''}'.trim();
      if (name.isEmpty || locale.isEmpty) continue;
      final voice = ReaderTtsVoice(
        name: name,
        locale: locale,
        quality: '${item['quality'] ?? ''}',
      );
      voices[voice.key] = voice;
    }
    final chinese = voices.values
        .where((voice) => voice.locale.toLowerCase().startsWith('zh'))
        .toList();
    final result = chinese.isEmpty ? voices.values.toList() : chinese;
    return result..sort((left, right) => left.label.compareTo(right.label));
  }

  Future<void> configure(ReaderTtsSettings settings) async {
    await _initialize();
    final tts = _tts!;
    final locale = settings.hasVoice ? settings.voiceLocale : 'zh-CN';
    if (await tts.isLanguageAvailable(locale) == false) {
      throw StateError('系统缺少 $locale 语音，请安装对应语音包或选择离线音色');
    }
    await tts.setLanguage(locale);
    if (settings.hasVoice) {
      final result = await tts.setVoice({
        'name': settings.voiceName,
        'locale': locale,
      });
      if (result == 0 || result == false) await tts.setLanguage('zh-CN');
    }
    await tts.setSpeechRate(settings.rate.clamp(0.1, 1));
    await tts.setPitch(settings.pitch.clamp(0.5, 2));
    await tts.setVolume(settings.volume.clamp(0, 1));
  }

  Future<bool> speak(
    String text, {
    bool focus = true,
    required void Function() onStarted,
    required void Function(int start, int end) onProgress,
  }) async {
    await _initialize();
    if (_text != text) {
      _text = text;
      _offset = 0;
      _nativePaused = false;
    }
    _paused = false;
    _started = false;
    _onStarted = onStarted;
    _onProgress = onProgress;
    final wait = _completion = Completer<bool>();
    final startup = Timer(const Duration(seconds: 15), () {
      if (identical(_completion, wait) && !wait.isCompleted && !_started) {
        wait.completeError(StateError('系统语音未响应，请检查语音引擎或选择离线音色'));
      }
    });
    final utterance = _nativePaused ? text : text.substring(_offset);
    _submitUtterance(utterance, wait, focus: focus);
    try {
      return await wait.future;
    } finally {
      startup.cancel();
      if (identical(_completion, wait)) _completion = null;
    }
  }

  void _submitUtterance(
    String utterance,
    Completer<bool> wait, {
    required bool focus,
  }) {
    unawaited(
      _tts!
          .speak(utterance, focus: focus)
          .then<void>(
            (result) {
              if (!identical(_completion, wait) || wait.isCompleted) return;
              if (result == 0 || result == -1 || result == false) {
                wait.completeError(StateError('系统语音未能朗读，请检查语音引擎或选择离线音色'));
              }
            },
            onError: (Object error, StackTrace stack) {
              if (identical(_completion, wait) && !wait.isCompleted) {
                wait.completeError(error, stack);
              }
            },
          ),
    );
  }

  Future<void> pause() async {
    _paused = true;
    _finish(false);
    try {
      final result = await _tts?.pause();
      _nativePaused = result == 1 || result == true;
    } catch (_) {
      _nativePaused = false;
    }
    if (!_nativePaused) await _tts?.stop();
  }

  Future<void> stop() async {
    _paused = false;
    _started = false;
    _nativePaused = false;
    _text = '';
    _offset = 0;
    _finish(false);
    _completion = null;
    try {
      await _tts?.stop();
    } on MissingPluginException {
      // 平台未提供系统语音时，停止不能阻止离线引擎或阅读页释放。
    } on PlatformException {
      // 已失效的系统服务没有可继续停止的朗读。
    }
  }
}
