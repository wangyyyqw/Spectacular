import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/encryption_inspector.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/font_obfuscation.dart';
import 'package:reader_core/epub/importer.dart';

import '../support/encryption_fixture.dart';

void main() {
  final mappings = {for (var i = 0; i < 60; i++) 0x4e00 + i: i + 5};
  final names = {
    for (var i = 0; i < 60; i++) i + 5: 'uni${(0x4e00 + i).toRadixString(16)}',
  };
  final ordinaryFont = mappingFont(mappings, names: names);

  for (final marker in [null, 'META-INF/rights.xml']) {
    test('普通 EPUB 与单独版权文件不误判：$marker', () async {
      final result = await EpubEncryptionInspector.inspectBytes(
        encryptionEpub(marker: marker),
      );
      expect(result.status, EpubEncryptionStatus.notDetected);
    });
  }

  test('空加密声明合法，不报损坏或加密', () async {
    final bytes = encryptionEpub(
      declaration: '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"/>',
    );
    final opened = await openEpub(bytes);
    addTearDown(opened.document!.archive.close);
    expect(
      EpubReadability.codesIn(opened.report.warnings),
      isNot(contains('E_FONT_OBFUSCATION_FAILED')),
    );
    expect(
      (await EpubEncryptionInspector.inspectBytes(bytes)).status,
      EpubEncryptionStatus.notDetected,
    );
  });

  for (final algorithm in FontObfuscationAlgorithm.values) {
    test('标准字体混淆可读且检测不改原书：${algorithm.name}', () async {
      final obfuscated = FontObfuscator.obfuscate(
        ordinaryFont,
        identifier: encryptionIdentifier,
        algorithm: algorithm,
      );
      final bytes = encryptionEpub(
        declaration: encryptionXml(
          algorithm == FontObfuscationAlgorithm.idpf
              ? 'http://www.idpf.org/2008/embedding'
              : 'http://ns.adobe.com/pdf/enc#RC',
        ),
        font: obfuscated,
      );
      final before = Uint8List.fromList(bytes);
      final result = await EpubEncryptionInspector.inspectBytes(bytes);
      expect(result.status, EpubEncryptionStatus.fontObfuscated);
      expect(bytes, before);
      final opened = await openEpub(bytes);
      addTearDown(opened.document!.archive.close);
      expect(await opened.document!.readFontBytes('font.ttf'), ordinaryFont);
    });
  }

  for (final path in [
    'OEBPS/chapter.xhtml',
    'OEBPS/font.ttf',
    'OEBPS/style.css',
  ]) {
    test('非字体混淆算法优先于坏 OPF 报加密：$path', () async {
      final bytes = encryptionEpub(
        declaration: encryptionXml(
          'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
          path: path,
        ),
        brokenOpf: true,
        font: ordinaryFont,
      );
      final opened = await openEpub(bytes);
      expect(opened.ok, isFalse);
      expect(opened.report.errorCode, 'E_EPUB_ENCRYPTED');
      expect(opened.report.readabilityLevel, EpubReadability.l4);
      expect(
        (await EpubEncryptionInspector.inspectBytes(bytes)).status,
        EpubEncryptionStatus.encrypted,
      );
    });
  }

  for (final marker in ['META-INF/sinf.xml', 'META-INF/license.lcpl']) {
    test('缺少 encryption.xml 时独立识别 DRM 标记：$marker', () async {
      final result = await openEpub(encryptionEpub(marker: marker));
      expect(result.report.errorCode, 'E_EPUB_ENCRYPTED');
    });
  }

  test('ZIP 密码加密在字节和文件导入中一致拒绝', () async {
    final bytes = encryptionEpub(password: '仅用于加密夹具');
    final directory = await Directory.systemTemp.createTemp('encrypted-epub-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/book.epub').writeAsBytes(bytes);
    for (final result in [
      await openEpub(bytes),
      await openEpubFile(file, verifyCrc: true),
    ]) {
      expect(result.report.errorCode, 'E_ZIP_ENCRYPTED');
      expect(result.ok, isFalse);
    }
    expect(
      (await EpubEncryptionInspector.inspectFile(file.path)).status,
      EpubEncryptionStatus.encrypted,
    );
    expect(
      EpubRejectionMessages.forCode('E_ZIP_ENCRYPTED', null).title,
      contains('密码'),
    );
    expect(await file.readAsBytes(), bytes);
  });

  for (final declaration in [
    '<encryption><broken>',
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData/></encryption>',
  ]) {
    test('损坏或错误命名空间的声明保留未知状态：$declaration', () async {
      final result = await EpubEncryptionInspector.inspectBytes(
        encryptionEpub(declaration: declaration),
      );
      expect(result.status, EpubEncryptionStatus.inconclusive);
    });
  }

  test('遗留声明仅指向缺失资源时允许阅读', () async {
    final result = await openEpub(
      encryptionEpub(
        declaration: encryptionXml('urn:encryption', path: 'missing.css'),
      ),
    );
    expect(result.ok, isTrue);
    result.document?.archive.close();
  });

  test('无法解析的 EPUB 不误报加密', () async {
    final report = await EpubEncryptionInspector.inspectBytes(
      Uint8List.fromList([1, 2, 3]),
    );
    expect(report.status, EpubEncryptionStatus.inconclusive);
  });

  test('未知或缺省资源算法仍识别加密，缺失字体声明保留未知状态', () async {
    for (final algorithm in ['urn:private:encryption', '']) {
      final bytes = encryptionEpub(
        declaration: encryptionXml(algorithm),
        font: ordinaryFont,
      );
      expect((await openEpub(bytes)).report.errorCode, 'E_EPUB_ENCRYPTED');
    }
    final missing = encryptionEpub(
      declaration: encryptionXml('http://www.idpf.org/2008/embedding'),
    );
    expect(
      (await EpubEncryptionInspector.inspectBytes(missing)).status,
      EpubEncryptionStatus.inconclusive,
    );
  });

  test('补充平面 Unicode format 12 的字形名矛盾可检测', () async {
    final font = mappingFont(
      {for (var i = 0; i < 60; i++) 0x20000 + i: i + 5},
      names: {
        for (var i = 0; i < 60; i++)
          i + 5: 'u${(0x21000 + i).toRadixString(16)}',
      },
    );
    final report = await EpubEncryptionInspector.inspectBytes(
      encryptionEpub(font: font),
    );
    expect(report.status, EpubEncryptionStatus.suspiciousFontMapping);
  });

  test('本地真实思源宋体不误判字体映射混淆', () async {
    final font = File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytesSync();
    final report = await EpubEncryptionInspector.inspectBytes(
      encryptionEpub(font: font),
    );
    expect(report.status, EpubEncryptionStatus.notDetected);
  });

  for (final format4 in [false, true]) {
    for (final rangeOffsets in format4 ? [false, true] : [false]) {
      test('正式引擎识别字形名矛盾：format4=$format4，偏移表=$rangeOffsets', () async {
        final wrongNames = {
          for (var i = 0; i < 60; i++)
            i + 5: 'uni${(0x5000 + i).toRadixString(16)}',
        };
        final bytes = encryptionEpub(
          font: mappingFont(
            mappings,
            names: wrongNames,
            format4: format4,
            rangeOffsets: rangeOffsets,
          ),
        );
        final report = await EpubEncryptionInspector.inspectBytes(bytes);
        expect(report.status, EpubEncryptionStatus.suspiciousFontMapping);
        final opened = await openEpub(bytes);
        addTearDown(opened.document!.archive.close);
        expect(opened.ok, isTrue, reason: '疑似映射混淆不阻断阅读');
      });
    }
  }

  test('缺少 post 时识别韩文或私用区复用汉字字形', () async {
    for (final shadowStart in [0xac00, 0xe000]) {
      final font = mappingFont({
        ...mappings,
        for (var i = 0; i < 60; i++) shadowStart + i: i + 5,
      });
      final report = await EpubEncryptionInspector.inspectBytes(
        encryptionEpub(font: font),
      );
      expect(report.status, EpubEncryptionStatus.suspiciousFontMapping);
    }
  });

  test('普通字体、仅编号乱序与字形复用不直接判断加密', () async {
    for (final font in [
      ordinaryFont,
      mappingFont({for (var i = 0; i < 250; i++) 0x4e00 + i: 251 - i}),
      mappingFont({for (var i = 0; i < 250; i++) 0x4e00 + i: 7}),
      mappingFont({for (var i = 0; i < 250; i++) 0xac00 + i: i + 1}),
    ]) {
      final report = await EpubEncryptionInspector.inspectBytes(
        encryptionEpub(font: font),
      );
      expect(report.status, EpubEncryptionStatus.notDetected);
    }
  });

  test('不支持或截断字体明确报告检测不完整', () async {
    for (final font in [
      Uint8List.fromList('wOF2'.codeUnits),
      ordinaryFont.sublist(0, 35),
    ]) {
      final report = await EpubEncryptionInspector.inspectBytes(
        encryptionEpub(font: font),
      );
      expect(report.status, EpubEncryptionStatus.inconclusive);
    }
  });

  test('文件与字节检测输出一致', () async {
    final dir = await Directory.systemTemp.createTemp('inspect-epub-');
    addTearDown(() => dir.delete(recursive: true));
    final bytes = encryptionEpub(font: ordinaryFont);
    final file = await File('${dir.path}/book.epub').writeAsBytes(bytes);
    final memory = await EpubEncryptionInspector.inspectBytes(bytes);
    final disk = await EpubEncryptionInspector.inspectFile(file.path);
    expect(disk.status, memory.status);
    expect(disk.details, memory.details);
  });
}
