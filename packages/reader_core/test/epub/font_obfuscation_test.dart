import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/font_obfuscation.dart';

const String _identifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc';
const String _wrongIdentifier = 'urn:uuid:00000000-0000-0000-0000-000000000000';

late Uint8List fontBytes;

Uint8List _loadFontBytes() {
  final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
  if (!file.existsSync()) {
    throw StateError('缺少测试字体：${file.path}');
  }
  return file.readAsBytesSync();
}

Future<void> _loadFont(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    fontBytes = _loadFontBytes();
  });

  test('IDPF 混淆/解混淆往返一致', () {
    final obfuscated = FontObfuscator.obfuscate(
      fontBytes,
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.idpf,
    );
    expect(obfuscated.sublist(0, 1040), isNot(fontBytes.sublist(0, 1040)));
    expect(obfuscated.sublist(1040), fontBytes.sublist(1040));

    final restored = FontObfuscator.deobfuscate(
      obfuscated,
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.idpf,
    );
    expect(restored, fontBytes);
  });

  test('Adobe 混淆/解混淆往返一致', () {
    final obfuscated = FontObfuscator.obfuscate(
      fontBytes,
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.adobe,
    );
    expect(obfuscated.sublist(0, 1024), isNot(fontBytes.sublist(0, 1024)));
    expect(obfuscated.sublist(1024), fontBytes.sublist(1024));

    final restored = FontObfuscator.deobfuscate(
      obfuscated,
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.adobe,
    );
    expect(restored, fontBytes);
  });

  test('错误 identifier 无法还原头部字节', () {
    final obfuscated = FontObfuscator.obfuscate(
      fontBytes,
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.idpf,
    );
    final wrong = FontObfuscator.deobfuscate(
      obfuscated,
      identifier: _wrongIdentifier,
      algorithm: FontObfuscationAlgorithm.idpf,
    );
    expect(wrong.sublist(0, 1040), isNot(fontBytes.sublist(0, 1040)));
  });

  test('Adobe 缺少 UUID 时抛出参数错误', () {
    expect(() => FontObfuscator.adobeKey('not-a-uuid'), throwsArgumentError);
  });

  test('解混淆后的两种字体都能被 FontLoader 加载并排版', () async {
    final idpfRestored = FontObfuscator.deobfuscate(
      FontObfuscator.obfuscate(
        fontBytes,
        identifier: _identifier,
        algorithm: FontObfuscationAlgorithm.idpf,
      ),
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.idpf,
    );
    final adobeRestored = FontObfuscator.deobfuscate(
      FontObfuscator.obfuscate(
        fontBytes,
        identifier: _identifier,
        algorithm: FontObfuscationAlgorithm.adobe,
      ),
      identifier: _identifier,
      algorithm: FontObfuscationAlgorithm.adobe,
    );

    await _loadFont('ObfuscatedIDPF', idpfRestored);
    await _loadFont('ObfuscatedAdobe', adobeRestored);

    for (final family in <String>['ObfuscatedIDPF', 'ObfuscatedAdobe']) {
      final painter = TextPainter(
        text: TextSpan(
          text: '中文排版',
          style: TextStyle(fontFamily: family, fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(painter.width, greaterThan(0));
      expect(painter.height, greaterThan(0));
      painter.dispose();
    }
  });
}
