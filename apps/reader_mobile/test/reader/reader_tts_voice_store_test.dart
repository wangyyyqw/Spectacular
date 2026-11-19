import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

void main() {
  late Directory root;
  late ReaderTtsVoiceStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reader-tts-store-');
    store = ReaderTtsVoiceStore(rootDirectory: root, client: http.Client());
  });

  tearDown(() async {
    store.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('扫描本地 VITS 音色并读取模型卡', () async {
    final directory = Directory('${root.path}/vits-demo')..createSync();
    File('${directory.path}/tokens.txt').writeAsStringSync('a 0\n');
    File('${directory.path}/model.onnx').writeAsBytesSync(<int>[1, 2, 3]);
    File('${directory.path}/MODEL_CARD').writeAsStringSync('''
# Model card for 示例音色

* language: zh
* quality: medium
* speakers: 2
* sample rate: 22,050
''');

    final voices = await store.listInstalled();
    expect(voices, hasLength(1));
    expect(voices.single.name, '示例音色');
    expect(voices.single.language, '中文');
    expect(voices.single.quality, '中等质量');
    expect(voices.single.speakerCount, 2);
    expect(voices.single.sampleRate, 22050);

    final model = await store.modelFor('vits-demo');
    expect(model?.kind, ReaderOfflineModelKind.vits);
    expect(model?.isCompleteIn(directory.path), isTrue);
  });

  test('下载 tar.bz2 后解压、识别并写入元数据', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final package = _voicePackage();
    server.listen((request) async {
      request.response.headers.contentType = ContentType.binary;
      request.response.add(package);
      await request.response.close();
    });
    try {
      final voice = ReaderOfflineVoice(
        id: 'downloaded-voice',
        downloadUrl: 'http://127.0.0.1:${server.port}/voice.tar.bz2',
        name: '下载音色',
      );
      final installed = await store.download(voice);
      expect(installed.installed, isTrue);
      expect(installed.name, '下载音色');
      expect(installed.speakerCount, 3);
      expect(
        File(
          '${root.path}/downloaded-voice/${ReaderTtsVoiceStore.metadataName}',
        ).existsSync(),
        isTrue,
      );
      final model = await store.modelFor('downloaded-voice');
      expect(model?.kind, ReaderOfflineModelKind.kokoro);
      expect(model?.speakerCount, 3);
    } finally {
      await server.close(force: true);
    }
  });

  test('官方音色与远端目录按标识合并', () async {
    final voices = await store.availableVoices(
      remote: const <ReaMicroTtsVoice>[
        ReaMicroTtsVoice(
          id: 'vits-piper-zh_CN-chaowen-medium',
          downloadUrl: 'https://example.com/chaowen.tar.bz2',
        ),
        ReaMicroTtsVoice(
          id: 'kokoro-multi-lang-v1_0',
          downloadUrl: 'https://example.com/kokoro.tar.bz2',
        ),
      ],
    );
    final official = voices.firstWhere(
      (voice) => voice.id == 'vits-piper-zh_CN-chaowen-medium',
    );
    expect(official.downloadUrl, 'https://example.com/chaowen.tar.bz2');
    expect(official.name, '超文');
    final kokoro = voices.firstWhere(
      (voice) => voice.id == 'kokoro-multi-lang-v1_0',
    );
    expect(kokoro.name, 'Kokoro 多语言');
  });
}

List<int> _voicePackage() {
  final archive = Archive()
    ..add(ArchiveFile.string('kokoro-demo/tokens.txt', 'a 0\n'))
    ..add(ArchiveFile.string('kokoro-demo/voices.bin', 'voices'))
    ..add(ArchiveFile.bytes('kokoro-demo/model.onnx', <int>[1, 2, 3]))
    ..add(
      ArchiveFile.string('kokoro-demo/MODEL_CARD', '''
# Model card for Kokoro 示例

* language: multi-lang
* quality: high
* speakers: 3
* sample rate: 24000
'''),
    );
  return BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
}
