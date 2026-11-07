import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/font_obfuscation.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

Uint8List _fallbackFontBook(Uint8List font) {
  final archive = Archive();
  void add(String path, List<int> bytes) =>
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
  void text(String path, String content) => add(path, utf8.encode(content));
  text('mimetype', 'application/epub+zip');
  text('META-INF/container.xml', '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="content.opf"
 media-type="application/oebps-package+xml"/></rootfiles></container>''');
  text('content.opf', '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">font-fallback</dc:identifier><dc:title>字体目录回退</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="a" href="One/a.xhtml" media-type="application/xhtml+xml"/>
<item id="b" href="Two/b.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine>${List.filled(256, '<itemref idref="a"/>').join()}
<itemref idref="b"/></spine></package>''');
  const chapter = '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>字体目录回退</title><style>
@font-face {font-family: fallback; src: url("missing.otf"), url("nested/f.otf");}
p {font-family: fallback, serif;}</style></head>
<body><p>中文书内字体测试</p></body></html>''';
  text('One/a.xhtml', chapter);
  text('Two/b.xhtml', chapter);
  // 两个同名字体使全库文件名回退失效，必须继续尝试后续章节目录。
  add('Two/nested/f.otf', font);
  add('Other/f.otf', Uint8List(12));
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _incrementalFontBook(Uint8List regular, Uint8List bold) {
  final archive = Archive();
  void add(String path, List<int> bytes) =>
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
  void text(String path, String content) => add(path, utf8.encode(content));
  text('mimetype', 'application/epub+zip');
  text('META-INF/container.xml', '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/content.opf"
 media-type="application/oebps-package+xml"/></rootfiles></container>''');
  text(
    'OEBPS/content.opf',
    '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">font-incremental</dc:identifier><dc:title>字体增量</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="a" href="Text/a.xhtml" media-type="application/xhtml+xml"/>
<item id="b" href="Text/b.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>''',
  );
  for (final entry in {'a': 'regular', 'b': 'bold'}.entries) {
    text(
      'OEBPS/Text/${entry.key}.xhtml',
      '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>字体增量</title><style>
@font-face {font-family: incremental; src: url("../Fonts/${entry.value}.otf");
font-weight: ${entry.key == 'a' ? 400 : 700};}
p {font-family: incremental;}</style></head><body><p>中文书内字体测试</p></body></html>''',
    );
  }
  add('OEBPS/Fonts/regular.otf', regular);
  add('OEBPS/Fonts/bold.otf', bold);
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _independentFontBook(Uint8List regular, Uint8List bold) {
  final archive = Archive();
  void add(String path, List<int> bytes) =>
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
  void text(String path, String content) => add(path, utf8.encode(content));
  text('mimetype', 'application/epub+zip');
  text('META-INF/container.xml', '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/content.opf"
 media-type="application/oebps-package+xml"/></rootfiles></container>''');
  text(
    'OEBPS/content.opf',
    '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">font-independent</dc:identifier><dc:title>独立字体</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="a" href="Text/a.xhtml" media-type="application/xhtml+xml"/>
<item id="b" href="Text/b.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>''',
  );
  for (final entry in {
    'a': (name: 'first', weight: 400),
    'b': (name: 'second', weight: 700),
  }.entries) {
    text(
      'OEBPS/Text/${entry.key}.xhtml',
      '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>独立字体</title><style>
@font-face {font-family: ${entry.value.name}; src: url("../Fonts/${entry.value.name}.otf");
font-weight: ${entry.value.weight};}
p {font-family: ${entry.value.name};}</style></head><body><p>中文书内字体测试</p></body></html>''',
    );
  }
  add('OEBPS/Fonts/first.otf', regular);
  add('OEBPS/Fonts/second.otf', bold);
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _encryptedBook(
  Uint8List font,
  FontObfuscationAlgorithm algorithm,
  String family,
) {
  final archive = ZipDecoder().decodeBytes(
    buildCssChapterBook(
      body: '<p>中文书内字体测试</p>',
      css:
          '@font-face {font-family: "$family"; src: url("../Fonts/f.otf");}'
          'p {font-family: "$family", serif;}',
      identifier: 'urn:uuid:12345678-1234-1234-1234-123456789abc',
    ),
  );
  final obfuscated = FontObfuscator.obfuscate(
    font,
    identifier: 'urn:uuid:12345678-1234-1234-1234-123456789abc',
    algorithm: algorithm,
  );
  archive.addFile(
    ArchiveFile('OEBPS/Fonts/f.otf', obfuscated.length, obfuscated),
  );
  final uri = algorithm == FontObfuscationAlgorithm.idpf
      ? 'http://www.idpf.org/2008/embedding'
      : 'http://ns.adobe.com/pdf/enc#RC';
  final encryption = utf8.encode('''
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
 xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
<enc:EncryptedData><enc:EncryptionMethod Algorithm="$uri"/>
<enc:CipherData><enc:CipherReference URI="OEBPS/Fonts/f.otf"/></enc:CipherData>
</enc:EncryptedData></encryption>''');
  archive.addFile(
    ArchiveFile('META-INF/encryption.xml', encryption.length, encryption),
  );
  return ZipEncoder().encodeBytes(archive);
}

Future<Uint8List> _pixels(String family) async {
  final recorder = ui.PictureRecorder();
  final painter = TextPainter(
    text: TextSpan(
      text: '中文书内字体测试',
      style: TextStyle(
        fontFamily: family,
        fontSize: 24,
        color: const Color(0xFF000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 400);
  painter.paint(Canvas(recorder), Offset.zero);
  painter.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 80);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return Uint8List.fromList(
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final font = File('assets/test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytesSync();

  test('缺失字体跳过后仍按章节目录顺序找到同名资源的正确字体', () async {
    final source = await EpubChapterSource.open(_fallbackFontBook(font));
    addTearDown(source.close);
    expect(source.document.spine, hasLength(257));
    expect(source.document.resources.resolve('nested/f.otf'), isNull);
    await ui.loadFontFromList(font, fontFamily: 'fallback_expected');
    for (final chapter in [0, 256]) {
      final pages = await source.loadChapter(chapter);
      final family = pages.first.slices.first.block.style!.fontFamily!;
      expect(family, startsWith('bi_'));
      expect(await _pixels(family), await _pixels('fallback_expected'));
      source.clearPaginationCache();
    }
  });

  for (final algorithm in FontObfuscationAlgorithm.values) {
    test('真实${algorithm.name}混淆字体经过章节源后与原字体像素一致', () async {
      final family = 'pipeline_${algorithm.name}';
      final source = await EpubChapterSource.open(
        _encryptedBook(font, algorithm, family),
      );
      addTearDown(source.close);
      expect(source.document.fontEncryption.entries, hasLength(1));
      expect(await source.document.readFontBytes('Fonts/f.otf'), font);
      final pages = await source.loadChapter(0);
      final engineFamily = pages.first.slices.first.block.style!.fontFamily!;
      expect(engineFamily, startsWith('bi_'));
      await ui.loadFontFromList(font, fontFamily: '${family}_expected');
      final actual = await _pixels(engineFamily);
      expect(actual, await _pixels('${family}_expected'));
      expect(
        actual,
        isNot(await _pixels('pipeline_absent_font')),
        reason: '不能把字体加载失败后的系统回退当作成功',
      );
    });
  }

  test('同OPF路径同标识不同字体字节使用隔离且稳定的引擎族名', () async {
    Future<EpubChapterSource> open(Uint8List bytes) => openCssChapter(
      body: '<p>中文书内字体测试</p>',
      css:
          '@font-face {font-family: shared; src: url("../Fonts/f.otf");}'
          'p {font-family: shared;}',
      binaryFiles: {'OEBPS/Fonts/f.otf': bytes},
    );
    final a = await open(font);
    final b = await open(
      File('assets/test_fonts/SourceHanSerifSC-Bold.otf').readAsBytesSync(),
    );
    final reopened = await open(font);
    for (final source in [a, b, reopened]) {
      addTearDown(source.close);
    }
    Future<String> family(EpubChapterSource source) async =>
        (await source.loadChapter(0))
            .first
            .slices
            .first
            .block
            .style!
            .fontFamily!;
    final nameA = await family(a);
    final before = await _pixels(nameA);
    final nameB = await family(b);
    expect(nameB, isNot(nameA));
    expect(await family(reopened), nameA, reason: '重复打开同一字体不生成新族名');
    expect(await _pixels(nameA), before, reason: '后打开的书不覆盖前一本字体');
    expect(await _pixels(nameB), isNot(before));
  });

  test('后续章节新增字重后旧章分页缓存改用完整的新字体族', () async {
    final source = await EpubChapterSource.open(
      _incrementalFontBook(
        font,
        File('assets/test_fonts/SourceHanSerifSC-Bold.otf').readAsBytesSync(),
      ),
    );
    addTearDown(source.close);
    final first = await source.loadChapter(0);
    final original = first.first.slices.first.block.style!.fontFamily!;
    final added = await source.loadChapter(1);
    final expanded = added.first.slices.first.block.style!.fontFamily!;
    expect(expanded, isNot(original));
    final reloaded = await source.loadChapter(0);
    expect(reloaded, isNot(same(first)), reason: '旧样式缓存不能沿用少字重的引擎族');
    expect(reloaded.first.slices.first.block.style!.fontFamily, expanded);
    expect(await _pixels(expanded), await _pixels(original));
    expect(
      source.invalidationLog.any(
        (entry) => entry.startsWith('fontFacesChanged'),
      ),
      isTrue,
    );
  });

  test('后续章节新增无关字族时保留已读章节分页缓存', () async {
    final source = await EpubChapterSource.open(
      _independentFontBook(
        font,
        File('assets/test_fonts/SourceHanSerifSC-Bold.otf').readAsBytesSync(),
      ),
    );
    addTearDown(source.close);
    final first = await source.loadChapter(0);
    final second = await source.loadChapter(1);
    expect(
      second.first.slices.first.block.style!.fontFamily,
      isNot(first.first.slices.first.block.style!.fontFamily),
    );

    final reloaded = await source.loadChapter(0);
    expect(reloaded, same(first), reason: '新增无关字族不应让旧章重新排版');
    expect(
      source.invalidationLog.where(
        (entry) => entry.startsWith('fontFacesChanged'),
      ),
      hasLength(2),
    );
  });

  test('字体注册在途关闭来源后不回填章节或字体缓存', () async {
    final source = await EpubChapterSource.open(
      _encryptedBook(font, FontObfuscationAlgorithm.idpf, 'closing'),
    );
    final loading = source.loadChapter(0);
    final completed = expectLater(loading, throwsStateError);
    source.close();
    await completed;
    expect(source.cacheReport, contains('页缓存 0/'));
    expect(source.chapterPlainText(0), isEmpty);
    expect(source.document.archive.contains('OEBPS/Fonts/f.otf'), isFalse);
  });
}
