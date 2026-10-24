import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_core/epub/resource_index.dart';

/// 8 字节 PNG 魔数开头的伪图片（嗅探只读魔数）。
final Uint8List _pngMagic = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0, 0, 0, 0,
]);

final Uint8List _otfMagic = Uint8List.fromList(<int>[
  0x4F, 0x54, 0x54, 0x4F, 0, 0, 0, 0, 0, 0, 0, 0,
]);

Uint8List _buildEpub(Map<String, Object> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = content is String ? utf8.encode(content) : content as List<int>;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _opf = '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:repair</dc:identifier>
    <dc:title>R</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
    <item id="font" href="fonts/body.otf" media-type="application/vnd.ms-opentype"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''';

ResourceIndex _index(List<String> extraHrefs) {
  final archive = EpubArchive.fromBytes(_buildEpub(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
    'OEBPS/content.opf': _opf,
    'OEBPS/c1.xhtml': '<html><body><p>x</p></body></html>',
    'OEBPS/images/pic.png': _pngMagic,
    'OEBPS/fonts/body.otf': _otfMagic,
  }));
  final opf = OpfParser.parse(
    utf8.decode(archive.readBytes('OEBPS/content.opf')!),
  );
  final manifest = [
    ...opf.manifest,
    for (final href in extraHrefs)
      OpfManifestItem(
        id: 'x${href.hashCode}',
        href: href,
        mediaType: href.endsWith('.otf')
            ? 'application/vnd.ms-opentype'
            : 'image/png',
      ),
  ];
  return ResourceIndex.build(
    archive: archive,
    manifest: manifest,
    opfPath: 'OEBPS/content.opf',
  );
}

void main() {
  group('导入期资源修复（P3-25，§54 七级链路 + 内容嗅探）', () {
    test('1～6 级：大小写错、反斜杠、query/fragment 均可解析', () {
      final index = _index(const <String>[]);
      const base = 'OEBPS';
      expect(index.resolve('Images/PIC.PNG', baseDir: base),
          'OEBPS/images/pic.png', reason: '大小写错（小写表兜底）');
      expect(index.resolve(r'images\pic.png', baseDir: base),
          'OEBPS/images/pic.png', reason: '反斜杠归一');
      expect(index.resolve('images/pic.png?v=2#frag', baseDir: base),
          'OEBPS/images/pic.png', reason: 'query/fragment 剥离');
      expect(index.resolve('images/%70ic.png', baseDir: base),
          'OEBPS/images/pic.png', reason: 'URL 编码解码');
    });

    test('7 级内容嗅探：缺扩展名的图片引用按魔数命中', () {
      final index = _index(const <String>['images/pic']);
      expect(
        index.sniffResolve(
          EpubArchive.fromBytes(_buildEpub(<String, Object>{
            'OEBPS/images/pic.png': _pngMagic,
          })),
          'images/pic',
          baseDir: 'OEBPS',
          mediaType: 'image/png',
        ),
        'OEBPS/images/pic.png',
      );
    });

    test('7 级内容嗅探：扩展名写错（gif 引用指向 png 文件）可修复', () {
      final index = _index(const <String>['images/pic.gif']);
      expect(
        index.sniffResolve(
          EpubArchive.fromBytes(_buildEpub(<String, Object>{
            'OEBPS/images/pic.png': _pngMagic,
          })),
          'images/pic.gif',
          baseDir: 'OEBPS',
          mediaType: 'image/gif',
        ),
        'OEBPS/images/pic.png',
      );
    });

    test('7 级内容嗅探：字体按类匹配，类型不符不误命中', () {
      final index = _index(const <String>['fonts/body']);
      expect(
        index.sniffResolve(
          EpubArchive.fromBytes(_buildEpub(<String, Object>{
            'OEBPS/fonts/body.otf': _otfMagic,
          })),
          'fonts/body',
          baseDir: 'OEBPS',
          mediaType: 'application/vnd.ms-opentype',
        ),
        'OEBPS/fonts/body.otf',
      );
      // 图片引用指向字体文件：类不匹配，明确降级。
      expect(
        index.sniffResolve(
          EpubArchive.fromBytes(_buildEpub(<String, Object>{
            'OEBPS/fonts/body.otf': _otfMagic,
          })),
          'images/pic',
          baseDir: 'OEBPS',
          mediaType: 'image/png',
        ),
        isNull,
      );
    });

    test('不可归类（text/html 等）不尝试嗅探，明确降级', () {
      final index = _index(const <String>['c1']);
      expect(
        index.sniffResolve(
          EpubArchive.fromBytes(_buildEpub(<String, Object>{
            'OEBPS/c1.xhtml': '<html/>',
          })),
          'c1',
          baseDir: 'OEBPS',
          mediaType: 'application/xhtml+xml',
        ),
        isNull,
      );
    });

    test('修复过程不改写原书：解析前后 EPUB 字节哈希一致', () {
      final bytes = _buildEpub(<String, Object>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '<container/>',
        'OEBPS/content.opf': _opf,
        'OEBPS/c1.xhtml': '<html><body><p>x</p></body></html>',
        'OEBPS/images/pic.png': _pngMagic,
        'OEBPS/fonts/body.otf': _otfMagic,
      });
      final before = sha256.convert(bytes).toString();
      final archive = EpubArchive.fromBytes(bytes);
      final opf = OpfParser.parse(
        utf8.decode(archive.readBytes('OEBPS/content.opf')!),
      );
      final index = ResourceIndex.build(
        archive: archive,
        manifest: opf.manifest,
        opfPath: 'OEBPS/content.opf',
      );
      index.resolve(r'IMAGES\PIC.PNG?v=1', baseDir: 'OEBPS');
      index.sniffResolve(archive, 'images/pic', baseDir: 'OEBPS',
          mediaType: 'image/png');
      final after = sha256.convert(bytes).toString();
      expect(after, before, reason: '§54.3 建索引不改文件');
    });
  });
}
