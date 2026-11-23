import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reader_mobile/reader/reader_tts_voice_store.dart';

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
        sha256Checksum: sha256.convert(package).toString(),
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
      expect(installed.sha256Checksum, voice.sha256Checksum);
      await expectLater(
        store.download(voice.copyWith(sha256Checksum: '0' * 64)),
        throwsFormatException,
      );
      expect(await store.modelFor(voice.id), isNotNull);
    } finally {
      await server.close(force: true);
    }
  });

  test('预设音色与本地音色按标识合并并保留下载地址', () async {
    const id = 'vits-piper-zh_CN-chaowen-medium';
    final directory = Directory('${root.path}/$id')..createSync();
    File('${directory.path}/tokens.txt').writeAsStringSync('a 0\n');
    File('${directory.path}/model.onnx').writeAsBytesSync(<int>[1, 2, 3]);
    final voices = await store.availableVoices();
    final voice = voices.firstWhere((voice) => voice.id == id);
    expect(voices.where((voice) => voice.id == id), hasLength(1));
    expect(voice.installed, isTrue);
    expect(voice.name, '超文');
    expect(voice.downloadUrl, isNotEmpty);
    await store.delete(id);
    expect(await store.modelFor(id), isNull);
    expect(
      (await store.availableVoices()).firstWhere((v) => v.id == id).installed,
      isFalse,
    );
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
