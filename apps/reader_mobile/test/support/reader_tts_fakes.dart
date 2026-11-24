import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart'
    show ReaderTtsClip;
import 'package:reader_mobile/reader/reader_tts_segment.dart';
import 'package:reader_mobile/reader/reader_tts_background.dart';
import 'package:reader_mobile/reader/reader_tts_text.dart';

ReaderTtsClip pcmTtsClip(
  List<int> samples, {
  int sampleRate = 1000,
  int index = 0,
}) {
  final wav = ByteData(44 + samples.length * 2);
  for (final (offset, text) in [
    (0, 'RIFF'),
    (8, 'WAVE'),
    (12, 'fmt '),
    (36, 'data'),
  ]) {
    for (var i = 0; i < text.length; i++) {
      wav.setUint8(offset + i, text.codeUnitAt(i));
    }
  }
  wav.setUint32(4, 36 + samples.length * 2, Endian.little);
  wav.setUint32(16, 16, Endian.little);
  wav.setUint16(20, 1, Endian.little);
  wav.setUint16(22, 1, Endian.little);
  wav.setUint32(24, sampleRate, Endian.little);
  wav.setUint32(28, sampleRate * 2, Endian.little);
  wav.setUint16(32, 2, Endian.little);
  wav.setUint16(34, 16, Endian.little);
  wav.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    wav.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return ReaderTtsClip(
    wav: wav.buffer.asUint8List(),
    sampleRate: sampleRate,
    sampleCount: samples.length,
    index: index,
  );
}

class MemoryTtsTextSource implements ReaderTtsTextSource {
  MemoryTtsTextSource(List<String> texts)
    : chunks = [
        for (var i = 0; i < texts.length; i++)
          ReaderTtsTextChunk(
            spineIndex: i,
            title: '第 ${i + 1} 章',
            segments: ReaderTtsSegmentation.split(texts[i]),
            chapter: AnchorChapter(
              spineIndex: i,
              href: 'chapter$i.xhtml',
              blocks: [
                AnchorBlock(
                  cfi: 'epubcfi(/6/${(i + 1) * 2}!/4/2/1:0)',
                  text: texts[i],
                ),
              ],
            ),
          ),
      ];

  final List<ReaderTtsTextChunk> chunks;
  int advances = 0;

  @override
  Future<ReaderTtsTextChunk?> first({required bool autoTurnPage}) async =>
      chunks.firstOrNull;

  @override
  Future<ReaderTtsTextChunk?> next(int spineIndex) async {
    advances++;
    return spineIndex + 1 < chunks.length ? chunks[spineIndex + 1] : null;
  }
}

/// 模拟平台完成与字词回调，并保留 Android 插件的暂停后截取行为。
class FakeSystemTts {
  static const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final spoken = <String>[];
  final methods = <MethodCall>[];
  bool autoComplete = true;
  bool autoStart = true;
  bool languageAvailable = true;
  int speakResult = 1;
  Object? voicesError;
  Future<int> Function(String text)? onSpeak;
  List<Map<String, String>> voices = [
    {'name': '可用音色', 'locale': 'zh-CN'},
  ];
  String _original = '';
  String _active = '';
  String? _remaining;
  int _offset = 0;

  void install() => messenger.setMockMethodCallHandler(channel, _method);
  void close() => messenger.setMockMethodCallHandler(channel, null);

  Future<Object?> _method(MethodCall call) async {
    methods.add(call);
    switch (call.method) {
      case 'getVoices':
        if (voicesError != null) throw voicesError!;
        return voices;
      case 'isLanguageAvailable':
        return languageAvailable;
      case 'speak':
        final text = call.arguments is Map
            ? (call.arguments as Map)['text'] as String
            : call.arguments as String;
        _active = _original == text && _remaining != null ? _remaining! : text;
        _original = text;
        _remaining = null;
        _offset = 0;
        spoken.add(_active);
        if (autoStart) await emit('speak.onStart', true);
        if (onSpeak != null) return onSpeak!(text);
        if (autoComplete && speakResult == 1) scheduleMicrotask(complete);
        return speakResult;
      case 'pause':
        _remaining = _active.substring(_offset);
        return 1;
      case 'stop':
        _original = '';
        _remaining = null;
        return 1;
    }
    return 1;
  }

  Future<void> progress(int start, int end) async {
    _offset = start;
    await emit('speak.onProgress', {
      'text': _active,
      'start': '$start',
      'end': '$end',
      'word': _active.substring(start, end),
    });
  }

  Future<void> complete() => emit('speak.onComplete', true);

  Future<void> emit(String method, Object arguments) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      null,
    );
  }
}

/// 通过正式平台通道模拟前台服务的启动、状态发布和系统媒体命令。
class FakeTtsBackground {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final methods = <MethodCall>[];
  bool active = false;
  Object? startError;
  Object? activationError;
  Future<void>? starting;
  Map<String, String>? state;

  void install() => messenger.setMockMethodCallHandler(
    ReaderTtsBackgroundPlayback.channel,
    _method,
  );

  void close() => messenger.setMockMethodCallHandler(
    ReaderTtsBackgroundPlayback.channel,
    null,
  );

  Future<void> _method(MethodCall call) async {
    methods.add(call);
    switch (call.method) {
      case 'start':
        await starting;
        if (startError != null) throw startError!;
        active = true;
      case 'activate':
        if (activationError != null) throw activationError!;
      case 'update':
        state = Map<String, String>.from(call.arguments as Map);
      case 'stop':
        active = false;
        state = null;
    }
  }

  Future<void> emit(String method) => messenger.handlePlatformMessage(
    ReaderTtsBackgroundPlayback.channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
    null,
  );
}
