import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:spectacular_epub_tools/src/features/phonetic/phonetic.dart';
import 'package:xml/xml.dart';

const _container = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="内容/书籍.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';
const _navigation = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head><body><nav epub:type="toc"><ol>
<li><a href="第一章.xhtml#正文">第一章</a></li>
</ol></nav></body></html>''';
const _stylesheet = 'p::before { content: "中文"; } ruby rt { font-size: 50%; }';
final _cover = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
);

String _document(String body) => '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>中文标题</title><link rel="stylesheet" href="样式.css"/></head>
<body>$body</body></html>''';

Archive _buildEpub(Map<String, String> chapters) {
  final manifest = StringBuffer();
  final spine = StringBuffer();
  var index = 0;
  for (final name in chapters.keys) {
    manifest.writeln(
      '<item id="c$index" href="${Uri.encodeFull(name)}" media-type="application/xhtml+xml"/>',
    );
    spine.writeln('<itemref idref="c$index"/>');
    index++;
  }
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..addFile(ArchiveFile.string('META-INF/container.xml', _container))
    ..addFile(
      ArchiveFile.string('内容/书籍.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">urn:phonetic:test</dc:identifier><dc:title>注音回归</dc:title>
<dc:creator>测试作者</dc:creator><dc:language>zh-CN</dc:language>
<meta property="dcterms:modified">2026-11-19T00:00:00Z</meta></metadata>
<manifest>$manifest
<item id="nav" href="目录.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="css" href="样式.css" media-type="text/css"/>
<item id="cover" href="封面.png" media-type="image/png" properties="cover-image"/>
</manifest><spine>$spine</spine></package>'''),
    )
    ..addFile(ArchiveFile.string('内容/目录.xhtml', _navigation))
    ..addFile(ArchiveFile.string('内容/样式.css', _stylesheet))
    ..addFile(ArchiveFile.bytes('内容/封面.png', _cover));
  for (final entry in chapters.entries) {
    archive.addFile(ArchiveFile.string('内容/${entry.key}', entry.value));
  }
  return archive;
}

String _text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content);

XmlDocument _chapter(Archive archive, [String name = '第一章.xhtml']) =>
    XmlDocument.parse(_text(archive, '内容/$name'));

List<String> _bases(XmlDocument document) => document
    .findAllElements('ruby', namespaceUri: '*')
    .map(
      (ruby) =>
          ruby.children.whereType<XmlText>().map((text) => text.value).join(),
    )
    .toList();

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('spectacular-phonetic-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  String output(String name) => path.join(temporary.path, name);

  Future<Archive> read(String name) async =>
      ZipDecoder().decodeBytes(await File(output(name)).readAsBytes());

  Future<void> write(Map<String, String> chapters) async {
    await File(output('input.epub'))
        .writeAsBytes(ZipEncoder().encodeBytes(_buildEpub(chapters)));
  }

  for (final (mode, expected) in [
    (PhoneticOperation.toneModeMark, ['zhōng', 'wén', 'hǎo']),
    (PhoneticOperation.toneModeNone, ['zhong', 'wen', 'hao']),
    (PhoneticOperation.toneModeNumber, ['zhong1', 'wen2', 'hao3']),
  ]) {
    test('从 EPUB 入口以 $mode 声调逐字生成 ruby 与 rt', () async {
      await write({'第一章.xhtml': _document('<p id="正文">中文好</p>')});
      final log = await PhoneticOperation.execute(
        epubPath: output('input.epub'),
        outputPath: output('annotated.epub'),
        toneMode: mode,
      );
      final document = _chapter(await read('annotated.epub'));
      expect(_bases(document), ['中', '文', '好']);
      expect(
        document
            .findAllElements('rt', namespaceUri: '*')
            .map((element) => element.innerText),
        expected,
      );
      expect(
        document.findAllElements('title', namespaceUri: '*').single.innerText,
        '中文标题',
      );
      expect(log, contains('全文注音'));
      expect(log, contains('2 个文件有标注'));
      expect(log, isNot(contains('标注失败')));
    });
  }

  test('仅生僻字模式依据 GB2312 一级字表识别扩展 A 与常用高码点字', () async {
    await write({'第一章.xhtml': _document('<p id="正文">中国大好图龙龘㐀𠀀👩‍💻</p>')});
    final log = await PhoneticOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('rare.epub'),
      annotateAll: false,
    );
    final archive = await read('rare.epub');
    final document = _chapter(archive);
    expect(_bases(document), ['龘', '㐀']);
    expect(
      _text(archive, '内容/第一章.xhtml'),
      contains('<ruby>㐀<rt>qiū</rt></ruby>'),
    );
    expect(
      document.findAllElements('p', namespaceUri: '*').single.innerText,
      contains('中国大好图龙'),
    );
    expect(_text(archive, '内容/第一章.xhtml'), contains('𠀀👩‍💻'));
    expect(log, contains('仅生僻字'));
    expect(log, contains('共标注 2 个字符'));
    expect(log, isNot(contains('标注失败')));
  });

  test('全文模式保留中文标点、实体、辅助平面字符与 emoji', () async {
    const tail = '，。“”！？&amp;&lt;&gt;&quot;&apos;&#x3001;&#160;&nbsp;𠀀😀👩‍💻';
    await write({'第一章.xhtml': _document('<p id="正文">中文龘㐀$tail</p>')});
    await PhoneticOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('unicode.epub'),
    );
    final text = _text(await read('unicode.epub'), '内容/第一章.xhtml');
    expect(text, contains('<ruby>中<rt>zhōng</rt></ruby>'));
    expect(text, contains('<ruby>龘<rt>dá</rt></ruby>'));
    expect(text, contains('<ruby>㐀<rt>qiū</rt></ruby>'));
    expect(text, contains(tail));
    expect(text, isNot(contains('\uFFFD')));
  });

  test('跳过脚本样式代码块与已有 ruby，连续文本和实体不丢失', () async {
    const existingRuby =
        '<ruby class="原注音">中<rp>（</rp><rt>zhōng</rt><rp>）</rp></ruby>';
    const protected =
        '''<script>const text = "<pre>中文</pre>"; if (1 < 2) text;</script>
<style>p::before { content: "中文 > 好"; }</style>
<pre data-label="中文 > 原样"><span>中文</span><code>龘</code></pre>
<code><em>㐀</em>中文</code>
<PRE>中文</PRE><textarea>中文</textarea>
<h:code xmlns:h="http://www.w3.org/1999/xhtml">中文</h:code>
<!-- 中文 <p>龘</p> -->
<![CDATA[中文 <ruby>原文</ruby>]]>''';
    await write({
      '第一章.xhtml': _document(
        '<p id="正文" title="中文 > 好">中<em>文</em>好&amp;@@SCRIPT0@@</p>'
        '$protected$existingRuby<p>文</p>',
      ),
    });
    final log = await PhoneticOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('protected.epub'),
    );
    final text = _text(await read('protected.epub'), '内容/第一章.xhtml');
    expect(text, contains(protected));
    expect(text, contains(existingRuby));
    expect(text, contains('title="中文 > 好"'));
    expect(text, contains('<em><ruby>文<rt>wén</rt></ruby></em>'));
    expect(text, contains('<ruby>好<rt>hǎo</rt></ruby>&amp;@@SCRIPT0@@'));
    expect(text, contains('$existingRuby<p><ruby>文<rt>wén</rt></ruby></p>'));
    expect(log, isNot(contains('标注失败')));
  });

  test('重复执行输出不嵌套或重复 ruby，既有注音与章节原文保持一致', () async {
    await write({
      '第一章.xhtml': _document('<p id="正文">中文<ruby>龘<rt>原有读音</rt></ruby>㐀</p>'),
    });
    await PhoneticOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('first.epub'),
    );
    final log = await PhoneticOperation.execute(
      epubPath: output('first.epub'),
      outputPath: output('second.epub'),
      toneMode: PhoneticOperation.toneModeNumber,
    );
    final first = await read('first.epub');
    final second = await read('second.epub');
    for (final name in ['内容/第一章.xhtml', '内容/目录.xhtml']) {
      expect(_text(second, name), _text(first, name));
    }
    final document = _chapter(second);
    expect(_bases(document), ['中', '文', '龘', '㐀']);
    for (final ruby in document.findAllElements('ruby', namespaceUri: '*')) {
      expect(ruby.findAllElements('ruby', namespaceUri: '*'), isEmpty);
      expect(ruby.findElements('rt', namespaceUri: '*'), hasLength(1));
    }
    expect(
      _text(second, '内容/第一章.xhtml'),
      contains('<ruby>龘<rt>原有读音</rt></ruby>'),
    );
    expect(log, contains('0 个文件有标注, 共标注 0 个字符'));
  });

  test('输出 EPUB 保留 OCF、元数据、manifest、spine、路径和二进制资源', () async {
    await write({
      '第一章.xhtml': _document('<p id="正文">中文</p>'),
      '第二章.HTML': _document('<p>好</p>'),
      '第三章.HtM': _document('<p>㐀</p>'),
    });
    final inputBytes = await File(output('input.epub')).readAsBytes();
    final input = ZipDecoder().decodeBytes(inputBytes);
    final log = await PhoneticOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('structure.epub'),
    );
    final bytes = await File(output('structure.epub')).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.map((file) => file.name),
      input.files.map((file) => file.name),
    );
    expect(
      archive.files.map((file) => file.name).toSet(),
      hasLength(archive.files.length),
    );
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(0, Endian.little), 0x04034b50);
    expect(header.getUint16(8, Endian.little), 0);
    expect(header.getUint16(28, Endian.little), 0);
    final nameLength = header.getUint16(26, Endian.little);
    expect(utf8.decode(bytes.sublist(30, 30 + nameLength)), 'mimetype');
    expect(_text(archive, 'mimetype'), 'application/epub+zip');
    for (final name in [
      'META-INF/container.xml',
      '内容/书籍.opf',
      '内容/样式.css',
      '内容/封面.png',
    ]) {
      expect(archive.findFile(name)!.content, input.findFile(name)!.content);
    }
    final package = XmlDocument.parse(_text(archive, '内容/书籍.opf'));
    expect(package.findAllElements('itemref', namespaceUri: '*'), hasLength(3));
    for (final name in ['第一章.xhtml', '第二章.HTML', '第三章.HtM', '目录.xhtml']) {
      final document = _chapter(archive, name);
      expect(document.rootElement.namespaceUri, 'http://www.w3.org/1999/xhtml');
      expect(document.findAllElements('ruby', namespaceUri: '*'), isNotEmpty);
      expect(document.findAllElements('body', namespaceUri: '*'), hasLength(1));
    }
    expect(await File(output('input.epub')).readAsBytes(), inputBytes);
    expect(log, contains('处理 4 个 HTML 文件, 4 个文件有标注'));
  });

  test('无法解码的章节保留并报告，其他章节继续标注', () async {
    final archive = _buildEpub({
      '第一章.xhtml': _document('<p id="正文">中文</p>'),
      '第二章.xhtml': '',
    });
    archive.addFile(ArchiveFile.bytes('内容/第二章.xhtml', [0xFF, 0xFE]));
    await File(output('input.epub'))
        .writeAsBytes(ZipEncoder().encodeBytes(archive));
    final log = await PhoneticOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('partial.epub'),
    );
    final outputArchive = await read('partial.epub');
    expect(_bases(_chapter(outputArchive)), ['中', '文']);
    expect(outputArchive.findFile('内容/第二章.xhtml')!.content, [0xFF, 0xFE]);
    expect(log, contains('文件 内容/第二章.xhtml 标注失败'));
    expect(log, contains('1 个文件失败'));
  });
}
