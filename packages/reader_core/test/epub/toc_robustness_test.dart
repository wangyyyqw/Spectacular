import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../support/corpus.dart';

/// P7-13：目录健壮性——目标不在 spine 的条目降级到最近章节；
/// spine 全部非 linear 时退化目录回退包含全部项（§35.2 绝不返回空目录）。
String _opf({
  bool allNonLinear = false,
  bool withNav = true,
  bool withNcx = false,
}) {
  final linearAttr = allNonLinear ? ' linear="no"' : '';
  return '<?xml version="1.0"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bid">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">urn:uuid:tr-0001</dc:identifier>'
      '<dc:title>目录健壮性</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '${withNav ? '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' : ''}'
      '${withNcx ? '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' : ''}'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine${withNcx ? ' toc="ncx"' : ''}>'
      '<itemref idref="c1"$linearAttr/>'
      '<itemref idref="c2"$linearAttr/>'
      '</spine></package>';
}

const _navWithOutsideTarget =
    '<?xml version="1.0"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
    '<nav epub:type="toc"><ol>'
    '<li><a href="c1.xhtml">第一章</a></li>'
    '<li><a href="plates.xhtml">插图页（不在 spine）</a></li>'
    '<li><a href="c2.xhtml">第二章</a></li>'
    '</ol></nav></body></html>';

const _navLeadingOutside =
    '<?xml version="1.0"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
    '<nav epub:type="toc"><ol>'
    '<li><a href="front.xhtml">前置页（不在 spine）</a></li>'
    '<li><a href="c2.xhtml">第二章</a></li>'
    '</ol></nav></body></html>';

const _chapter = '<?xml version="1.0"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>正文</p></body></html>';

Map<String, String> _book({
  required String opf,
  String? nav,
  bool includeNcxFile = false,
}) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<?xml version="1.0"?><container><rootfiles>'
      '<rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
  'OEBPS/content.opf': opf,
  'OEBPS/nav.xhtml': ?nav,
  if (includeNcxFile)
    'OEBPS/toc.ncx':
        '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">'
        '<navMap><navPoint id="n1"><navLabel><text>第一章</text></navLabel>'
        '<content src="c1.xhtml"/></navPoint></navMap></ncx>',
  'OEBPS/c1.xhtml': _chapter,
  'OEBPS/c2.xhtml': _chapter,
};

void main() {
  test('目录项指向 spine 外文档：降级到前向最近章节并留诊断（同目标由既有去重合并）', () async {
    final bytes = buildZip(
      _book(opf: _opf(), nav: _navWithOutsideTarget),
    );
    final result = await openEpub(bytes);
    expect(result.ok, isTrue, reason: result.report.message);
    final entries = result.document!.toc;
    // 插图页降级到第一章（spine#0）后与第一章同键，被 §35.2 既有
    // 去重合并——条目去向记录在诊断告警中，不静默。
    expect(entries, hasLength(2));
    expect(entries[0].spineIndex, 0);
    expect(entries[1].spineIndex, 1);
    expect(
      result.report.warnings.any(
        (w) => w.startsWith('E_TOC_TARGET_OUTSIDE_SPINE'),
      ),
      isTrue,
    );
    expect(
      result.report.warnings.any((w) => w.contains('插图页')),
      isTrue,
      reason: '降级明细应包含条目名',
    );
  });

  test('首项目标不在 spine：降级到后向最近章节且跳转落点正确', () async {
    final bytes = buildZip(_book(opf: _opf(), nav: _navLeadingOutside));
    final result = await openEpub(bytes);
    expect(result.ok, isTrue);
    final entries = result.document!.toc;
    // 前置页先建键（降级到 spine#1），第二章随后并入同键。
    expect(entries, hasLength(1));
    expect(entries.first.spineIndex, 1, reason: '跳转落到后向最近章节 c2');
    expect(
      result.report.warnings.any(
        (w) => w.startsWith('E_TOC_TARGET_OUTSIDE_SPINE'),
      ),
      isTrue,
    );
  });

  test('spine 全部非 linear：退化目录回退包含全部项', () async {
    final bytes = buildZip(_book(opf: _opf(allNonLinear: true)));
    final result = await openEpub(bytes);
    expect(result.ok, isTrue, reason: result.report.message);
    final document = result.document!;
    expect(document.toc, isNotEmpty, reason: '§35.2 绝不返回空目录');
    expect(document.toc.length, document.spine.length);
    expect(
      result.report.warnings.any(
        (w) => w.startsWith('E_SPINE_ALL_NON_LINEAR'),
      ),
      isTrue,
    );
  });

  test('§35.2 回退链：无 nav 无 ncx 时 spine 兜底目录非空可跳转', () async {
    final bytes = buildZip(
      _book(opf: _opf(withNav: false, withNcx: false)),
    );
    final result = await openEpub(bytes);
    expect(result.ok, isTrue);
    final document = result.document!;
    expect(document.toc, isNotEmpty);
    expect(document.tocSource, 'spine');
    expect(document.toc.first.spineIndex, greaterThanOrEqualTo(0));
  });

  test('正常目录不受降级影响（无告警、序号原样）', () async {
    final nav = _navWithOutsideTarget.replaceAll(
      '<li><a href="plates.xhtml">插图页（不在 spine）</a></li>',
      '',
    );
    final bytes = buildZip(_book(opf: _opf(), nav: nav));
    final result = await openEpub(bytes);
    expect(result.ok, isTrue);
    expect(result.document!.toc, hasLength(2));
    expect(
      result.report.warnings.any(
        (w) => w.startsWith('E_TOC_TARGET_OUTSIDE_SPINE'),
      ),
      isFalse,
    );
  });
}
