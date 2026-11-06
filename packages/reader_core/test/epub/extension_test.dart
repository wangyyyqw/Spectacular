import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/extension.dart';
import 'package:reader_core/src/api/models.dart';

import '../support/corpus.dart';

const String _opf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="b">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="b">urn:uuid:extension</dc:identifier>
    <dc:title>扩展测试</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c"/></spine>
</package>
''';

Uint8List _book({String? extensionXml}) {
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''',
    'OEBPS/content.opf': _opf,
    'OEBPS/Text/c.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>正文</p></body></html>',
  };
  if (extensionXml != null) {
    files[DuokanExtensionParser.path] = extensionXml;
  }
  return buildZip(files);
}

String _extension({String layout = 'reflow', String? width, String? height}) =>
    '''
<duokan-extension version="1.0">
  <display-options>
    <layout> $layout </layout>
    ${width == null ? '' : '<option name="page-width"> $width </option>'}
    ${height == null ? '' : '<option name="page-height"> $height </option>'}
  </display-options>
</duokan-extension>
''';

void main() {
  group('duokan-extension.xml', () {
    test('缺失文件保持 reflow 默认值', () {
      final config = DuokanExtensionParser.parse(null);
      expect(config.layout, EpubLayoutType.reflow);
      expect(config.sourceFound, isFalse);
      expect(config.warnings, isEmpty);
      expect(config.aspectRatio, isNull);
    });

    test('五种布局映射', () {
      for (final layout in EpubLayoutType.values) {
        final config = DuokanExtensionParser.parse(
          _extension(layout: layout.token),
        );
        expect(config.layout, layout, reason: layout.token);
        expect(config.sourceFound, isTrue);
        expect(config.warnings, isEmpty);
      }
    });

    test('页宽高去空白并生成页面比例', () {
      final config = DuokanExtensionParser.parse(
        _extension(layout: 'fixed-page', width: ' 1200 ', height: ' 1800 '),
      );
      expect(config.pageWidth, 1200);
      expect(config.pageHeight, 1800);
      expect(config.aspectRatio, closeTo(2 / 3, 0.000001));
    });

    test('宽高必须同时为正数才生成比例', () {
      final cases = <({String? width, String? height})>[
        (width: '1200', height: null),
        (width: null, height: '1800'),
        (width: '0', height: '1800'),
        (width: '1200', height: '-1'),
        (width: 'NaN', height: '1800'),
      ];
      for (final value in cases) {
        final config = DuokanExtensionParser.parse(
          _extension(
            layout: 'fixed-page',
            width: value.width,
            height: value.height,
          ),
        );
        expect(config.aspectRatio, isNull, reason: '$value');
      }
    });

    test('损坏 XML 记录 E_DUOKAN_EXTENSION_XML 并回退 reflow', () {
      final config = DuokanExtensionParser.parse(
        '<duokan-extension><display-options>',
      );
      expect(config.layout, EpubLayoutType.reflow);
      expect(config.sourceFound, isTrue);
      expect(config.warnings.single, startsWith('E_DUOKAN_EXTENSION_XML:'));
    });

    test('根元素错误记录 E_DUOKAN_EXTENSION_XML 并回退 reflow', () {
      final config = DuokanExtensionParser.parse('<not-duokan/>');
      expect(config.layout, EpubLayoutType.reflow);
      expect(config.sourceFound, isTrue);
      expect(config.warnings.single, startsWith('E_DUOKAN_EXTENSION_XML:'));
    });

    test('未知布局与非法尺寸记录 E_DUOKAN_EXTENSION_VALUE', () {
      final config = DuokanExtensionParser.parse(
        _extension(layout: 'manga', width: '-1', height: '1800'),
      );
      expect(config.layout, EpubLayoutType.reflow);
      expect(config.aspectRatio, isNull);
      expect(
        config.warnings.where(
          (warning) => warning.startsWith('E_DUOKAN_EXTENSION_VALUE:'),
        ),
        hasLength(2),
      );
    });

    test('打开书籍时解析一次并并入导入报告，但不可读性分级不变', () async {
      final result = await openEpub(
        _book(extensionXml: '<duokan-extension><broken>'),
      );
      expect(result.ok, isTrue);
      final document = result.document!;
      expect(document.extensionConfig.layout, EpubLayoutType.reflow);
      expect(document.extensionConfig.sourceFound, isTrue);
      expect(
        result.report.warnings,
        contains(startsWith('E_DUOKAN_EXTENSION_XML:')),
      );
      expect(result.report.readabilityLevel, 0);
    });
  });
}
