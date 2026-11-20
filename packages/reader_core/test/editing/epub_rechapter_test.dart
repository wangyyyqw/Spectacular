import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/revision_relocator.dart';

const _options = ChapterDetectionOptions(
  mode: ChapterDetectionMode.custom,
  rule: ChapterRule(id: 'test', name: '章节', pattern: r'^第[一二三四]章.*$'),
);

Future<File> _fixture(
  List<String> bodies, {
  List<String>? styles,
  bool marker = true,
}) async {
  final dir = await Directory.systemTemp.createTemp('rechapter-test-');
  addTearDown(() => dir.delete(recursive: true));
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    'OPS/book.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:test</dc:identifier><dc:title>当前书</dc:title></metadata>'
        '<manifest>${[for (var i = 0; i < bodies.length; i++) '<item id="c$i" href="c$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
        '<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '<item id="img" href="image.svg" media-type="image/svg+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>'
        '${marker ? '<item id="spectacular-txt-info" href="txt.json" media-type="application/json"/>' : ''}'
        '</manifest><spine toc="ncx">${[for (var i = 0; i < bodies.length; i++) '<itemref idref="c$i"/>'].join()}</spine></package>',
    for (var i = 0; i < bodies.length; i++)
      'OPS/c$i.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>旧章节$i</title><link rel="stylesheet" href="style.css"/>${styles == null ? '' : '<style>${styles[i]}</style>'}</head><body>${bodies[i]}</body></html>',
    'OPS/nav.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="c0.xhtml">旧目录</a></li></ol></nav></body></html>',
    'OPS/toc.ncx': '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>当前书</text></docTitle><navMap/></ncx>',
    'OPS/image.svg': '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20"/></svg>',
    'OPS/style.css': 'p { margin: 1em 0; } .keep { color: #123456; }',
    if (marker)
      'OPS/txt.json': jsonEncode({
        'schema': 1,
        'sourceDigest': 'a' * 64,
        'encoding': 'UTF-8',
        'options': const ChapterDetectionOptions().toJson(),
      }),
  };
  final zip = Archive();
  for (final entry in files.entries) {
    zip.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  final file = File('${dir.path}/source.epub');
  await file.writeAsBytes(ZipEncoder().encodeBytes(zip));
  return file;
}

Future<String> _text(File file) async {
  final source = await EpubChapterSource.openFile(file);
  try {
    final parts = <String>[];
    for (var i = 0; i < source.chapterCount; i++) {
      parts.add((await source.loadAnchorChapter(i)).text);
    }
    return parts.join();
  } finally {
    source.close();
    await source.preparationsStopped;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('从当前 EPUB 拆分嵌套章节，保留修改文字、行内标签、图片与脚注链接', () async {
    final file = await _fixture([
      '<div class="keep"><h2 id="a">第一章 已修改</h2><p>已经<b>加粗</b>的新正文。</p>'
          '<p><img src="image.svg"/><a href="#note">注释</a></p>'
          '<section><h2 id="b">第二章 新标题</h2><p>第二段😀正文。</p>'
          '<aside epub:type="footnote" id="note"><p>第三章 这是注释内容</p><a href="#a">返回</a></aside></section></div>',
    ]);
    final before = await _text(file);
    final preview = await EpubRechapterService.preview(file, options: _options);
    expect(preview.canApply, isTrue, reason: preview.diagnostics.join('\n'));
    expect(preview.chapterCount, 2);
    expect(preview.sampleForChapter(0), contains('已经加粗'));
    final target = File('${file.parent.path}/result.epub');
    final summary = await EpubRechapterService.write(preview, target);
    expect(summary.cssOnly, isFalse);
    expect(await _text(target), before);
    final opened = await EpubEditSession.open(target);
    addTearDown(opened.close);
    expect(opened.spinePaths, hasLength(2));
    final first = opened.readText(opened.spinePaths[0]);
    final second = opened.readText(opened.spinePaths[1]);
    expect(first, contains('<b>加粗</b>'));
    expect(first, contains('../image.svg'));
    expect(first, contains('${opened.spinePaths[1].split('/').last}#note'));
    expect(second, contains('${opened.spinePaths[0].split('/').last}#a'));
    expect(second, contains('epub:type="footnote"'));
    expect(PackageEditor(opened).toc.map((e) => e.label), [
      '第一章 已修改',
      '第二章 新标题',
    ]);
    expect(
      opened.readText('OPS/style.css'),
      'p { margin: 1em 0; } .keep { color: #123456; }',
    );
    opened.validate();
  });

  test('删除旧误分章边界可以跨当前文件合章，样式一致时无重复文字', () async {
    final file = await _fixture([
      '<h2>第一章</h2><p>第一段</p>',
      '<p id="second">同一章的后半段</p>',
      '<h2>第二章</h2><p>真正第二章</p>',
    ]);
    final preview = await EpubRechapterService.preview(file, options: _options);
    expect(preview.canApply, isTrue, reason: preview.diagnostics.join('\n'));
    final target = File('${file.parent.path}/merged.epub');
    await EpubRechapterService.write(preview, target);
    expect(await _text(target), await _text(file));
    final opened = await openEpubFile(target);
    expect(opened.document!.spine, hasLength(2));
    opened.document!.archive.close();
  });

  test('仅有行内内容的 div 作为完整标题匹配，正文仍保留行内格式', () async {
    final file = await _fixture([
      '<div>第一章 <b>标题</b></div><p>正文一</p>'
          '<div>第二章 <em>另一个标题</em></div><p>正文二</p>',
    ]);
    final preview = await EpubRechapterService.preview(file, options: _options);
    expect(preview.canApply, isTrue, reason: preview.diagnostics.join('\n'));
    expect(preview.detection.boundaries.map((item) => item.title), [
      '第一章 标题',
      '第二章 另一个标题',
    ]);
    final target = File('${file.parent.path}/inline.epub');
    await EpubRechapterService.write(preview, target);
    expect(await _text(target), await _text(file));
  });

  test('相邻多幅图片以 DOM 身份迁移，不能落到同位置的文字或另一幅图', () async {
    final file = await _fixture([
      '<p>第一章</p><p>正文</p><div><p>第二章</p>'
          '<p><img src="image.svg"/><img src="image.svg"/></p><p>图后文字</p></div>',
    ]);
    final session = await EpubEditSession.open(file);
    final parsed = DocumentParser.parse(
      xhtml: session.readText(session.spinePaths.single),
      spineIndex: 0,
    );
    final images = <ParsedElement>[];
    void collect(ParsedElement node) {
      if (node.tag == 'img') images.add(node);
      for (final child in node.children.whereType<ParsedElement>()) {
        collect(child);
      }
    }

    collect(parsed.root);
    final oldCfi = images[1].cfi.serialize();
    session.close();
    final preview = await EpubRechapterService.preview(file, options: _options);
    expect(preview.canApply, isTrue, reason: preview.diagnostics.join('\n'));
    expect(
      preview.elementCfiMap[images[0].cfi.serialize()],
      isNot(preview.elementCfiMap[oldCfi]),
    );
    final target = File('${file.parent.path}/images.epub');
    await EpubRechapterService.write(preview, target);
    Future<AnchorBook> anchors(File source, String revision) async {
      final chapters = await EpubChapterSource.openFile(source);
      try {
        return AnchorBook(
          revision: revision,
          chapters: [
            for (var i = 0; i < chapters.chapterCount; i++)
              await chapters.loadAnchorChapter(i),
          ],
        );
      } finally {
        chapters.close();
        await chapters.preparationsStopped;
      }
    }

    final old = await anchors(file, preview.baseRevision);
    final next = await anchors(target, 'next');
    final record = AnchorRecord(original: old.capture(oldCfi)!);
    final moved = RevisionRelocator.relocate(
      oldBook: old,
      newBook: next,
      record: record,
      preserveTextPositions: true,
      elementCfiMap: preview.elementCfiMap,
    );
    expect(moved.status, 'relocated');
    expect(moved.current!.start.cfi, preview.elementCfiMap[oldCfi]);
    expect(moved.current!.start.spineIndex, 1);
    final withoutMap = RevisionRelocator.relocate(
      oldBook: old,
      newBook: next,
      record: record,
      preserveTextPositions: true,
    );
    expect(withoutMap.status, 'pending');
  });

  test('body ID 样式及专用 spine 属性在预览时拒绝，避免格式丢失', () async {
    for (final specialSpine in [false, true]) {
      final file = await _fixture(['<p>第一章</p><p>正文一</p><p>第二章</p><p>正文二</p>']);
      final session = await EpubEditSession.open(file);
      session.transaction('准备已编辑 EPUB', (tx) {
        if (specialSpine) {
          tx.writeText(
            session.opfPath,
            session
                .readText(session.opfPath)
                .replaceFirst('idref="c0"', 'idref="c0" linear="no"'),
          );
        } else {
          tx.writeText(
            session.spinePaths.single,
            session
                .readText(session.spinePaths.single)
                .replaceFirst('<body>', '<body id="styled">'),
          );
          tx.writeText('OPS/style.css', 'body#styled { color: red; }');
        }
      });
      final edited = File('${file.parent.path}/edited.epub');
      await EpubWriter.write(session, edited);
      session.close();
      final preview = await EpubRechapterService.preview(
        edited,
        options: _options,
      );
      expect(preview.canApply, isFalse);
      expect(
        preview.diagnostics.join(),
        contains(specialSpine ? '专用属性' : '根元素 ID'),
      );
    }
  });

  test('样式冲突及重复 ID 在预览阶段阻止合章，原文件保持不变', () async {
    for (final conflictingStyles in [true, false]) {
      final file = await _fixture(
        ['<h2>第一章</h2><p id="same">前半段</p>', '<p id="same">后半段</p>'],
        styles: conflictingStyles ? ['p {color:red}', 'p {color:blue}'] : null,
      );
      final before = await file.readAsBytes();
      final preview = await EpubRechapterService.preview(
        file,
        options: _options,
      );
      expect(preview.canApply, isFalse);
      expect(
        preview.diagnostics.join(),
        contains(conflictingStyles ? '样式不同' : '重复 ID'),
      );
      expect(await file.readAsBytes(), before);
    }
  });

  test('结构选择器和计数器拒绝改变章节边界，原边界不变时允许写出重开', () async {
    for (final sample in [
      (css: 'body > section > p:nth-child(2n + 1) { color: red; }', inline: ''),
      (css: 'section p:first-child { color: red; }', inline: ''),
      (css: 'p + p { margin-top: 2em; }', inline: ''),
      (css: 'p::before { content: counter(chapter); }', inline: ''),
      (css: 'p { counter-increment: chapter; }', inline: ''),
      (css: '', inline: 'counter-reset: chapter; counter-set: chapter 2;'),
    ]) {
      String section(String content) =>
          '<section style="${sample.inline}">$content</section>';
      const first = '<p>第一章</p><p>正文一</p>';
      const second = '<p>第二章</p><p>正文二</p>';
      final changing = await _fixture(
        [section('$first$second')],
        styles: [sample.css],
      );
      final before = await changing.readAsBytes();
      final blocked = await EpubRechapterService.preview(
        changing,
        options: _options,
      );
      expect(blocked.canApply, isFalse, reason: '$sample');
      expect(blocked.diagnostics.join(), contains('保守检查'));
      expect(await changing.readAsBytes(), before);

      final unchanged = await _fixture(
        [section(first), section(second)],
        styles: [sample.css, sample.css],
      );
      final preview = await EpubRechapterService.preview(
        unchanged,
        options: _options,
      );
      expect(preview.canApply, isTrue, reason: preview.diagnostics.join('\n'));
      final target = File('${unchanged.parent.path}/unchanged.epub');
      await EpubRechapterService.write(preview, target);
      expect(await _text(target), await _text(unchanged));
      final opened = await openEpubFile(target);
      expect(opened.document!.spine, hasLength(2));
      opened.document!.archive.close();
    }
  });

  test('预览过期、无匹配、普通 EPUB、取消均不写回原书', () async {
    final file = await _fixture(['<p>第一章</p><p>正文</p>']);
    final preview = await EpubRechapterService.preview(file, options: _options);
    final target = File('${file.parent.path}/result.epub');
    await expectLater(
      EpubRechapterService.write(preview, target, isCancelled: () => true),
      throwsA(isA<EpubEditException>()),
    );
    expect(await target.exists(), isFalse);
    final noMatch = await EpubRechapterService.preview(
      file,
      options: const ChapterDetectionOptions(
        mode: ChapterDetectionMode.custom,
        rule: ChapterRule(id: 'x', name: '无', pattern: '^不会命中\$'),
      ),
    );
    expect(noMatch.canApply, isFalse);
    final changed = await EpubEditSession.open(file);
    changed.transaction(
      '保存正文编辑',
      (tx) => tx.writeText(
        changed.spinePaths.single,
        changed.readText(changed.spinePaths.single).replaceAll('正文', '编辑后的正文'),
      ),
    );
    final modified = File('${file.parent.path}/modified.epub');
    await EpubWriter.write(changed, modified);
    changed.close();
    await modified.copy(file.path);
    await expectLater(
      EpubRechapterService.write(preview, target),
      throwsA(isA<EpubEditException>()),
    );
    expect(await target.exists(), isFalse);
    final ordinary = await _fixture(['<p>第一章</p>'], marker: false);
    await expectLater(
      EpubRechapterService.preview(ordinary),
      throwsA(isA<EpubEditException>()),
    );
  });

  test('输入是实际 TXT 转换结果，重分章修改规则并生成可重开的 EPUB', () async {
    final dir = await Directory.systemTemp.createTemp('txt-rechapter-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/source.epub');
    await TxtEpubConverter.convertBytes(
      utf8.encode('第一章 起点\n正文一\n第二章 继续\n正文二'),
      file,
      options: const ChapterDetectionOptions(mode: ChapterDetectionMode.length),
    );
    final preview = await EpubRechapterService.preview(file, options: _options);
    expect(preview.canApply, isTrue, reason: preview.diagnostics.join('\n'));
    final target = File('${dir.path}/new.epub');
    await EpubRechapterService.write(preview, target);
    final session = await EpubEditSession.open(target);
    addTearDown(session.close);
    expect(session.spinePaths, hasLength(2));
    final info =
        jsonDecode(session.readText(txtMetadataPath)) as Map<String, dynamic>;
    expect((info['options'] as Map)['mode'], 'custom');
    expect(await _text(file), await _text(target));
    expect(
      sha256.convert(await file.readAsBytes()),
      isNot(sha256.convert(await target.readAsBytes())),
    );
  });
}
