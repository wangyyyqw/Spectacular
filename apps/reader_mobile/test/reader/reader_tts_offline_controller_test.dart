import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/reader_offline_tts.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/reader/reader_tts_controller.dart';
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';

void main() {
  test('离线听书按旁白与对白音色合成并顺序播放', () async {
    final synthesizer = _FakeSynthesizer();
    final player = _FakePlayer();
    final controller = ReaderTtsController(
      textProvider: () async => '“你好。”他说。',
      nextPage: () async => false,
      offlineSynthesizer: synthesizer,
      player: player,
      resolveOfflineVoice: _resolveVoice,
    );
    addTearDown(controller.dispose);

    await controller.start(
      const ReaderTtsSettings(
        mode: ReaderTtsMode.offline,
        narratorVoiceId: 'narrator',
        dialogueVoiceId: 'dialogue',
        autoTurnPage: false,
        narratorSpeed: 1.2,
        dialogueSpeed: 0.9,
      ),
    );

    expect(synthesizer.calls, 1);
    expect(synthesizer.segments.map((segment) => segment.text), <String>[
      '你好。',
      '他说。',
    ]);
    expect(synthesizer.narrator?.id, 'narrator');
    expect(synthesizer.dialogue?.id, 'dialogue');
    expect(synthesizer.settings?.narratorSpeed, 1.2);
    expect(player.clips, hasLength(2));
    expect(controller.speaking, isFalse);
  });

  test('对白音色跟随旁白时不重复加载第二个模型', () async {
    final synthesizer = _FakeSynthesizer();
    final controller = ReaderTtsController(
      textProvider: () async => '旁白。“对白。”',
      nextPage: () async => false,
      offlineSynthesizer: synthesizer,
      player: _FakePlayer(),
      resolveOfflineVoice: _resolveVoice,
    );
    addTearDown(controller.dispose);

    await controller.start(
      const ReaderTtsSettings(
        mode: ReaderTtsMode.offline,
        narratorVoiceId: 'narrator',
        autoTurnPage: false,
      ),
    );

    expect(synthesizer.dialogue, isNull);
    expect(synthesizer.segments, hasLength(2));
  });
}

Future<ReaderOfflineVoiceInstance?> _resolveVoice(String id) async {
  if (id != 'narrator' && id != 'dialogue') return null;
  return ReaderOfflineVoiceInstance(
    id: id,
    rootPath: '/tmp/$id',
    model: const ReaderOfflineVoiceModel(
      kind: ReaderOfflineModelKind.vits,
      model: 'model.onnx',
      tokens: 'tokens.txt',
    ),
  );
}

class _FakeSynthesizer implements ReaderOfflineTtsSynthesizer {
  int calls = 0;
  List<ReaderTtsSegment> segments = const <ReaderTtsSegment>[];
  ReaderOfflineVoiceInstance? narrator;
  ReaderOfflineVoiceInstance? dialogue;
  ReaderTtsSettings? settings;

  @override
  Future<List<ReaderTtsClip>> synthesize({
    required List<ReaderTtsSegment> segments,
    required ReaderOfflineVoiceInstance narrator,
    required ReaderOfflineVoiceInstance? dialogue,
    required ReaderTtsSettings settings,
  }) async {
    calls++;
    this.segments = segments;
    this.narrator = narrator;
    this.dialogue = dialogue;
    this.settings = settings;
    return <ReaderTtsClip>[
      for (var index = 0; index < segments.length; index++)
        ReaderTtsClip(
          wav: Uint8List.fromList(<int>[0]),
          sampleRate: 22050,
          sampleCount: 22050,
          index: index,
        ),
    ];
  }
}

class _FakePlayer implements ReaderTtsPlayer {
  final List<ReaderTtsClip> clips = <ReaderTtsClip>[];

  @override
  Future<void> play(ReaderTtsClip clip) async => clips.add(clip);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
