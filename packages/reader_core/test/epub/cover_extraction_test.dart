import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';

/// 构造最小 EPUB；[metadataExtra] 追加到 metadata，[manifestExtra] 追加
/// 到 manifest，[body] 是首章正文。
Uint8List _buildEpub({
  String metadataExtra = '',
  String manifestExtra = '',
  String body = '<p>正文</p>',
  List<({String path, List<int> bytes})> images = const [],
}) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
  addText(
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '<rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  addText(
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="uid"><metadata '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:cover-test</dc:identifier>'
    '<dc:title>封面测试</dc:title><dc:language>zh</dc:language>'
    '$metadataExtra</metadata><manifest>'
    '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
    '$manifestExtra</manifest><spine><itemref idref="c1"/></spine></package>',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c1</title>'
    '</head><body>$body</body></html>',
  );
  for (final image in images) {
    archive.addFile(
      ArchiveFile(image.path, image.bytes.length, image.bytes),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

final List<int> _jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4];

Future<EpubDocumentImpl> _open(Uint8List bytes) async {
  final result = await openEpub(bytes);
  expect(result.document, isNotNull, reason: result.report.message ?? '打开失败');
  return result.document!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('第 1 级：manifest properties 含 cover-image', () async {
    final document = await _open(
      _buildEpub(
        manifestExtra: '<item id="cover" href="Images/cover.jpg" '
            'media-type="image/jpeg" properties="cover-image"/>',
        images: [(path: 'OEBPS/Images/cover.jpg', bytes: _jpegBytes)],
      ),
    );
    expect(document.coverResourcePath, 'OEBPS/Images/cover.jpg');
    expect(document.readCoverBytes(), _jpegBytes);
  });

  test('第 2 级：OPF meta name=cover 指向 manifest id', () async {
    final document = await _open(
      _buildEpub(
        metadataExtra: '<meta name="cover" content="cover-img"/>',
        manifestExtra: '<item id="cover-img" href="Images/cover.jpg" '
            'media-type="image/jpeg"/>',
        images: [(path: 'OEBPS/Images/cover.jpg', bytes: _jpegBytes)],
      ),
    );
    expect(document.coverResourcePath, 'OEBPS/Images/cover.jpg');
    expect(document.readCoverBytes(), _jpegBytes);
  });

  test('第 2 级兜底：meta content 直接写 href', () async {
    final document = await _open(
      _buildEpub(
        metadataExtra: '<meta name="cover" content="Images/cover.jpg"/>',
        images: [(path: 'OEBPS/Images/cover.jpg', bytes: _jpegBytes)],
      ),
    );
    expect(document.coverResourcePath, 'OEBPS/Images/cover.jpg');
  });

  test('第 3 级：spine 首章首图', () async {
    final document = await _open(
      _buildEpub(
        body: '<div><img src="Images/first.png" alt=""/><p>正文</p></div>',
        images: [
          (path: 'OEBPS/Images/first.png', bytes: <int>[0x89, 0x50, 0x4E]),
        ],
      ),
    );
    expect(document.coverResourcePath, 'OEBPS/Images/first.png');
    expect(document.readCoverBytes(), <int>[0x89, 0x50, 0x4E]);
  });

  test('三级都没有：返回 null，交给 UI 占位', () async {
    final document = await _open(_buildEpub());
    expect(document.coverResourcePath, isNull);
    expect(document.readCoverBytes(), isNull);
  });
}
