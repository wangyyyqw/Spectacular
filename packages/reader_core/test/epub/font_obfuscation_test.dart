import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/font_obfuscation.dart';
import 'package:reader_core/text/font_coverage.dart';

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

/// 构造含混淆字体的最小 EPUB。
Uint8List _buildEncryptedEpub({
  required Uint8List obfuscatedFont,
  required String algorithmUri,
  bool sinf = false,
}) {
  final archive = Archive();
  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(content.codeUnits);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  addText('META-INF/encryption.xml', '''<?xml version="1.0"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="$algorithmUri"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/Fonts/test.otf"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>''');
  if (sinf) {
    addText('META-INF/sinf.xml', '<sinf/>');
  }
  addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">$_identifier</dc:identifier>
    <dc:title>Enc</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="font1" href="Fonts/test.otf" media-type="font/otf"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''');
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>正文</p></body></html>',
  );
  archive.addFile(
    ArchiveFile('OEBPS/Fonts/test.otf', obfuscatedFont.length, obfuscatedFont),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    fontBytes = _loadFontBytes();
  });

  group('FontObfuscator 密钥与往返（P0-17 修正口径）', () {
    test('IDPF：SHA-1(去空白 identifier)，1040 字节', () {
      expect(
        FontObfuscator.idpfKey('  urn:x \t\r\n y'),
        FontObfuscator.idpfKey('urn:xy'),
      );
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

    test('Adobe：UUID 16 字节密钥，1024 字节（Readium 参考实现）', () {
      const uuid = 'urn:uuid:00112233-4455-6677-8899-aabbccddeeff';
      expect(
        FontObfuscator.adobeKey(uuid),
        Uint8List.fromList(<int>[
          0x00,
          0x11,
          0x22,
          0x33,
          0x44,
          0x55,
          0x66,
          0x77,
          0x88,
          0x99,
          0xaa,
          0xbb,
          0xcc,
          0xdd,
          0xee,
          0xff,
        ]),
      );
      // 独立固定向量：输入为 0x00..0x1f，按 16 字节 UUID 循环 XOR。
      expect(
        FontObfuscator.deobfuscate(
          Uint8List.fromList(List<int>.generate(32, (index) => index)),
          identifier: uuid,
          algorithm: FontObfuscationAlgorithm.adobe,
        ),
        Uint8List.fromList(<int>[
          0x00,
          0x10,
          0x20,
          0x30,
          0x40,
          0x50,
          0x60,
          0x70,
          0x80,
          0x90,
          0xa0,
          0xb0,
          0xc0,
          0xd0,
          0xe0,
          0xf0,
          0x10,
          0x00,
          0x30,
          0x20,
          0x50,
          0x40,
          0x70,
          0x60,
          0x90,
          0x80,
          0xb0,
          0xa0,
          0xd0,
          0xc0,
          0xf0,
          0xe0,
        ]),
      );
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
  });

  group('FontEncryptionMap 解析（P3-05）', () {
    test('替代前缀与默认命名空间均按同一 XML Encryption URI 识别', () {
      for (final prefix in <String>['enc:', 'other:', '']) {
        final declaration = prefix.isEmpty
            ? 'xmlns="http://www.w3.org/2001/04/xmlenc#"'
            : 'xmlns:${prefix.substring(0, prefix.length - 1)}="http://www.w3.org/2001/04/xmlenc#"';
        final map = FontEncryptionMap.parse('''
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <${prefix}EncryptedData $declaration>
    <${prefix}EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
    <${prefix}CipherData><${prefix}CipherReference URI="OEBPS/a.otf"/></${prefix}CipherData>
  </${prefix}EncryptedData>
</encryption>''');
        expect(map.entries, <String, FontObfuscationAlgorithm>{
          'OEBPS/a.otf': FontObfuscationAlgorithm.idpf,
        }, reason: 'prefix=$prefix');
      }
    });

    test('同名但命名空间不匹配的元素不能声明字体混淆', () {
      final map = FontEncryptionMap.parse('''
<encryption xmlns:enc="urn:not-xml-encryption">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/a.otf"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>''');
      expect(map.isEmpty, isTrue);
    });

    test('识别 IDPF/Adobe URI，未知算法记录', () {
      const xml = '''
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/a.otf"/></enc:CipherData>
  </enc:EncryptedData>
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://ns.adobe.com/pdf/enc#RC"/>
    <enc:CipherData><enc:CipherReference URI="/OEBPS/b.ttf"/></enc:CipherData>
  </enc:EncryptedData>
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://example.com/unknown"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/c.otf"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>''';
      final map = FontEncryptionMap.parse(xml);
      expect(map.entries['OEBPS/a.otf'], FontObfuscationAlgorithm.idpf);
      expect(
        map.entries['OEBPS/b.ttf'],
        FontObfuscationAlgorithm.adobe,
        reason: '前导 / 归一为 ZIP 根路径',
      );
      expect(map.entries.containsKey('OEBPS/c.otf'), isFalse);
      expect(map.unknownAlgorithms, ['http://example.com/unknown']);
    });

    test('损坏 XML 返回空表不抛异常', () {
      final map = FontEncryptionMap.parse('<encryption><unclosed>');
      expect(map.isEmpty, isTrue);
    });
  });

  group('openEpub 接线与缓存（P3-05）', () {
    test('混淆书 readFontBytes 解出可渲染字体，原书字节不动', () async {
      final obfuscated = FontObfuscator.obfuscate(
        fontBytes,
        identifier: _identifier,
        algorithm: FontObfuscationAlgorithm.idpf,
      );
      final epubBytes = _buildEncryptedEpub(
        obfuscatedFont: obfuscated,
        algorithmUri: 'http://www.idpf.org/2008/embedding',
      );
      final result = await openEpub(epubBytes);
      expect(result.ok, isTrue, reason: result.report.message);
      final doc = result.document!;
      final restored = await doc.readFontBytes('Fonts/test.otf');
      expect(restored, fontBytes, reason: '解混淆产物与原字体一致');
      expect(FontCoverage.parse(restored!), isNotNull, reason: '解出的字体可解析（可渲染）');
      // ZIP 内原始条目保持混淆态：原书不被改写。
      expect(doc.archive.readBytes('OEBPS/Fonts/test.otf'), obfuscated);
    });

    test('Adobe 算法同样解出可渲染字体', () async {
      final obfuscated = FontObfuscator.obfuscate(
        fontBytes,
        identifier: _identifier,
        algorithm: FontObfuscationAlgorithm.adobe,
      );
      final epubBytes = _buildEncryptedEpub(
        obfuscatedFont: obfuscated,
        algorithmUri: 'http://ns.adobe.com/pdf/enc#RC',
      );
      final result = await openEpub(epubBytes);
      expect(result.ok, isTrue);
      final restored = await result.document!.readFontBytes('Fonts/test.otf');
      expect(restored, fontBytes);
    });

    test('FairPlay 检测进诊断且不解密', () async {
      final obfuscated = FontObfuscator.obfuscate(
        fontBytes,
        identifier: _identifier,
        algorithm: FontObfuscationAlgorithm.idpf,
      );
      final epubBytes = _buildEncryptedEpub(
        obfuscatedFont: obfuscated,
        algorithmUri: 'http://www.idpf.org/2008/embedding',
        sinf: true,
      );
      final result = await openEpub(epubBytes);
      expect(result.ok, isTrue);
      expect(
        result.report.warnings.any((w) => w.contains('E_FAIRPLAY_ENCRYPTION')),
        isTrue,
      );
    });

    test('DirectoryFontCache：命中不重复解密', () async {
      final cache = DirectoryFontCache(
        await Directory.systemTemp.createTemp('font_cache'),
      );
      var computeCalls = 0;
      Future<Uint8List> compute() async {
        computeCalls += 1;
        return Uint8List.fromList(<int>[1, 2, 3, 4]);
      }

      final first = await cache.getOrCompute('k1', compute);
      final second = await cache.getOrCompute('k1', compute);
      expect(first, second);
      expect(computeCalls, 1, reason: '第二次命中缓存');
      // 不同键不串。
      await cache.getOrCompute('k2', compute);
      expect(computeCalls, 2);
      // try/finally 清理临时目录。
      await cache.directory.delete(recursive: true);
    });
  });
}
