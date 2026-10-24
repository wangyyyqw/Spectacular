import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/container.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/opf.dart';

import '../support/corpus.dart';

/// P7-12：container.xml 不可用时的 OPF 回退扫描 + manifest media-type 推断。
const _opf = '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="bid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="bid">urn:uuid:fb-0001</dc:identifier>'
    '<dc:title>回退书</dc:title><dc:language>zh</dc:language>'
    '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
    '</metadata><manifest>'
    '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
    '</manifest><spine><itemref idref="c1"/></spine></package>';

const _chapter = '<?xml version="1.0"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body><p>回退正文</p></body></html>';

Map<String, String> _files({String? container}) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': ?container,
  'OEBPS/content.opf': _opf,
  'OEBPS/c1.xhtml': _chapter,
};

void main() {
  test('container.xml 损坏时回退扫描 OEBPS/content.opf 并可打开', () async {
    final bytes = buildZip(_files(container: '<?xml 破损'));
    final result = await openEpub(bytes);
    expect(result.ok, isTrue, reason: result.report.message);
    expect(
      result.report.warnings.any((w) => w.startsWith('E_CONTAINER_FALLBACK')),
      isTrue,
    );
    expect(result.report.warnings.any((w) => w.contains('OEBPS/content.opf')),
        isTrue);
    expect(result.document!.spine, isNotEmpty);
  });

  test('container.xml 缺失时同样回退（根目录候选命中）', () async {
    final bytes = buildZip(<String, String>{
      'mimetype': 'application/epub+zip',
      'content.opf': _opf,
      'c1.xhtml': _chapter,
    });
    final result = await openEpub(bytes);
    expect(result.ok, isTrue, reason: result.report.message);
    expect(
      result.report.warnings.any((w) => w.startsWith('E_CONTAINER_FALLBACK')),
      isTrue,
    );
  });

  test('无任何 OPF 时保留拒绝路径（不误兜底）', () async {
    final bytes = buildZip(<String, String>{
      'mimetype': 'application/epub+zip',
      'OEBPS/c1.xhtml': _chapter,
    });
    final result = await openEpub(bytes);
    expect(result.ok, isFalse);
    expect(result.report.errorCode, 'E_CONTAINER_MISSING');
  });

  test('parseWithFallback 正常路径无诊断', () {
    final bytes = buildZip(<String, String>{
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<?xml version="1.0"?><container><rootfiles>'
          '<rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
      'OEBPS/content.opf': _opf,
      'OEBPS/c1.xhtml': _chapter,
    });
    final archive = EpubArchive.fromBytes(bytes);
    final parsed = EpubContainer.parseWithFallback(archive);
    expect(parsed.$1.rootfilePath, 'OEBPS/content.opf');
    expect(parsed.$2, isNull);
  });

  test('media-type 推断矩阵：四类资源归类正确且不误判', () {
    expect(OpfParser.inferMediaType('a/b.xhtml'), 'application/xhtml+xml');
    expect(OpfParser.inferMediaType('nav.xhtml'), 'application/xhtml+xml');
    expect(OpfParser.inferMediaType('style/sheet.css'), 'text/css');
    expect(OpfParser.inferMediaType('toc.ncx'), 'application/x-dtbncx+xml');
    expect(OpfParser.inferMediaType('img/cover.PNG'), 'image/png');
    expect(OpfParser.inferMediaType('font/book.otf'), 'application/vnd.ms-opentype');
    expect(OpfParser.inferMediaType('unknown.xyz'), '');
    expect(OpfParser.inferMediaType('noext'), '');
  });

  test('manifest 项缺 media-type：推断进结果并带诊断告警', () {
    final opf = _opf.replaceAll(
      'media-type="application/xhtml+xml"',
      '',
    );
    final parsed = OpfParser.parse(opf);
    expect(parsed.manifest.single.mediaType, 'application/xhtml+xml');
    expect(
      parsed.warnings.any(
        (w) => w.startsWith('E_MANIFEST_MEDIA_TYPE_INFERRED'),
      ),
      isTrue,
    );
  });
}
