import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/importer.dart';

import '../support/corpus.dart';

/// spine 为空时的 L3 恢复（对照 Ferrous `epub_fallback_parser.dart`）：
/// 先按 manifest 章节顺序恢复，再按整库扫描兜底；都失败才保持拒绝。
const _container = '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const _chapter = '<?xml version="1.0"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body><p>恢复正文</p></body></html>';

String _opf({required String manifest, required String spine}) =>
    '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="bid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="bid">urn:uuid:spine-fallback</dc:identifier>'
    '<dc:title>断链书</dc:title><dc:language>zh</dc:language>'
    '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
    '</metadata><manifest>$manifest</manifest><spine>$spine</spine></package>';

const _chapters = '<item id="c1" href="ch01.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="c2" href="sub/ch02.xhtml" '
    'media-type="application/xhtml+xml"/>';

Map<String, String> _files(String opf) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': opf,
  'OEBPS/ch01.xhtml': _chapter,
  'OEBPS/sub/ch02.xhtml': _chapter,
};

void main() {
  test('spine 为空时按 manifest 顺序恢复并降级 L3', () async {
    final result = await openEpub(
      buildZip(_files(_opf(manifest: _chapters, spine: ''))),
    );
    expect(result.ok, isTrue, reason: result.report.message);
    expect(
      result.document!.spine.map((item) => item.href).toList(),
      <String>['ch01.xhtml', 'sub/ch02.xhtml'],
    );
    expect(result.report.readabilityLevel, EpubReadability.l3);
    expect(
      result.report.warnings.any((w) => w.startsWith('E_SPINE_FALLBACK')),
      isTrue,
    );
  });

  test('spine 项全部指向不存在的 id 时同样恢复', () async {
    final result = await openEpub(
      buildZip(
        _files(
          _opf(
            manifest: _chapters,
            spine: '<itemref idref="ghost-1"/><itemref idref="ghost-2"/>',
          ),
        ),
      ),
    );
    expect(result.ok, isTrue, reason: result.report.message);
    expect(result.document!.spine.length, 2);
    expect(
      result.report.warnings.any((w) => w.contains('spine 引用了不存在的 manifest id')),
      isTrue,
    );
  });

  test('manifest 无章节时按整库扫描恢复相对路径', () async {
    final result = await openEpub(
      buildZip(
        _files(
          _opf(
            manifest: '<item id="css" href="s.css" media-type="text/css"/>',
            spine: '',
          ),
        ),
      ),
    );
    expect(result.ok, isTrue, reason: result.report.message);
    expect(
      result.document!.spine.map((item) => item.href).toList(),
      <String>['ch01.xhtml', 'sub/ch02.xhtml'],
    );
    for (final item in result.document!.spine) {
      final path = result.document!.resources.resolve(item.href, baseDir: 'OEBPS');
      expect(path, isNotNull, reason: '恢复出的 href 必须仍能解析：${item.href}');
      expect(result.document!.archive.readBytes(path!), isNotNull);
    }
  });

  test('无可读章节时仍拒绝，不放开 E_SPINE_EMPTY 口径', () async {
    final result = await openEpub(
      buildZip(<String, String>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': _container,
        'OEBPS/content.opf': _opf(
          manifest: '<item id="css" href="s.css" media-type="text/css"/>',
          spine: '',
        ),
      }),
    );
    expect(result.ok, isFalse);
    expect(result.report.errorCode, 'E_SPINE_EMPTY');
  });
}
