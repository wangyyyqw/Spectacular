import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/source/format_opener.dart';

import 'edit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late EpubEditSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('epub-edit-test-');
    session = await EpubEditSession.open(await createEditingFixture(directory));
  });
  tearDown(() async {
    session.close();
    await directory.delete(recursive: true);
  });

  test('精确源码索引保留开始标签、结束标签、属性及 CFI 身份', () {
    final doc = session.editableDocument('OPS/chapter.xhtml');
    final node = doc.elements.singleWhere((e) => e.attributes['id'] == 'p');
    expect(node.innerXml, '甲&amp;<em id="e">乙😀</em>丙');
    expect(node.text, '甲&乙😀丙');
    expect(doc.source.substring(node.closeStart, node.end), '</p>');
    final parsed = DocumentParser.parse(xhtml: doc.source, spineIndex: 0);
    final resolved = session.resolveEditableElement(
      0,
      parsed.elementById('p')!.cfi.serialize(),
    );
    expect(resolved.start, node.start);
    expect(resolved.classes, {'note'});
    expect(resolved.parent!.tag, 'body');
    final changed = resolved.replaceAttribute('class', 'new & other');
    expect(changed, contains('class="new &amp; other"'));
    expect(changed, contains('<em id="e">乙😀</em>'));
    expect(
      () => session.resolveEditableElement(
        0,
        parsed.elementById('p')!.cfi.serialize().replaceFirst('!/4', '!/2'),
      ),
      throwsA(isA<EpubEditException>()),
    );
    expect(
      () => session.resolveEditableElement(
        0,
        parsed.textNodes.first.cfi.withCharOffset(99999).serialize(),
      ),
      throwsA(isA<EpubEditException>()),
    );
  });

  test('正文替换保留行内结构，撤销重做和过期目标防护生效', () {
    final node = _paragraph(session);
    session.replaceText(node, '甲&新😀丙');
    expect(session.readText(node.path), contains('<em id="e">新😀</em>'));
    expect(
      () => session.replaceText(node, '旧目标'),
      throwsA(isA<EpubEditException>()),
    );
    session.undo();
    expect(session.readText(node.path), editingXhtml);
    session.redo();
    expect(_paragraph(session).text, '甲&新😀丙');
  });

  test('源码到预览定位精确匹配中文行内元素，拒绝 head 和过期源码', () {
    final doc = session.editableDocument('OPS/chapter.xhtml');
    final inline = doc.elements.singleWhere(
      (node) => node.attributes['id'] == 'e',
    );
    final cfi = session.cfiForElement(inline);
    final resolved = session.resolveEditableElement(0, cfi);
    expect(resolved.outerXml, '<em id="e">乙😀</em>');
    expect(resolved.start, inline.start);
    expect(
      () => session.cfiForElement(
        doc.elements.firstWhere((node) => node.tag == 'head'),
      ),
      throwsA(isA<EpubEditException>()),
    );
    expect(session.revision, 0);
    session.replaceText(_paragraph(session), '甲&新😀丙');
    expect(
      () => session.cfiForElement(inline),
      throwsA(isA<EpubEditException>()),
    );
  });

  test('拆分跨行内元素保留标签且不复制 ID，插入删除共享同一历史', () {
    session.splitAtTextOffset(_paragraph(session), 3);
    final nodes = session.editableDocument('OPS/chapter.xhtml').elements;
    final paragraphs = nodes.where((e) => e.tag == 'p').toList();
    expect(paragraphs.map((e) => e.text), ['甲&乙', '😀丙', '另一段']);
    expect(nodes.where((e) => e.attributes['id'] == 'e'), hasLength(1));
    session.insertAfter(paragraphs[1], '<p>新增</p>');
    final added = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .singleWhere((e) => e.tag == 'p' && e.text == '新增');
    session.deleteElement(added);
    expect(session.readText(added.path), isNot(contains('新增')));
    session.undo();
    expect(session.readText(added.path), contains('新增'));
  });

  test('事务验证失败不发布部分资源和元数据，草稿恢复绑定原书', () async {
    final events = <EpubEditChange>[];
    final subscription = session.changes.listen(events.add);
    expect(
      () => session.transaction('失败', (tx) {
        tx.writeText('OPS/style.css', 'p{color:red}');
        tx.metadata['owner'] = 'note';
        tx.writeText('OPS/chapter.xhtml', '<html>');
      }),
      throwsA(isA<EpubEditException>()),
    );
    expect(session.changedPaths, isEmpty);
    expect(session.metadata, isEmpty);
    expect(events, isEmpty);
    session.transaction('修改样式', (tx) {
      tx.writeText('OPS/style.css', 'p{color:red}');
      tx.metadata['owner'] = 'note';
    });
    final blobs = <String, Uint8List>{};
    final draft = session.toDraft(
      storeBlob: (path, bytes) {
        blobs[path] = bytes;
        return path;
      },
    );
    final restored = await EpubEditSession.open(
      session.baseFile,
      draft: draft,
      readBlob: (ref) => blobs[ref]!,
    );
    expect(restored.readText('OPS/style.css'), 'p{color:red}');
    expect(restored.metadata['owner'], 'note');
    restored.close();
    await subscription.cancel();
  });

  test('拆分不复制 xml:id，拒绝 UTF-16 代理对内部的拆分点', () {
    session.transaction(
      '添加 XML 身份',
      (tx) => tx.writeText(
        'OPS/chapter.xhtml',
        editingXhtml.replaceFirst('id="e"', 'xml:id="e"'),
      ),
    );
    expect(
      () => session.splitAtTextOffset(_paragraph(session), 4),
      throwsA(isA<EpubEditException>()),
    );
    session.splitAtTextOffset(_paragraph(session), 3);
    final elements = session.editableDocument('OPS/chapter.xhtml').elements;
    expect(elements.where((e) => e.attributes['xml:id'] == 'e'), hasLength(1));
    expect(elements.where((e) => e.tag == 'p').map((e) => e.text), [
      '甲&乙',
      '😀丙',
      '另一段',
    ]);
  });

  test('大资源连续替换受历史字节预算约束，当前资源不被裁剪', () {
    for (var i = 0; i < 4; i++) {
      final bytes = Uint8List(17 * 1024 * 1024)..[0] = i;
      session.transaction(
        '替换大图',
        (tx) => tx.writeBytes('OPS/image.png', bytes),
      );
    }
    expect(
      session.historyBytes,
      lessThanOrEqualTo(EpubEditSession.maxHistoryBytes),
    );
    expect(session.historyDiscarded, greaterThan(0));
    expect(session.readBytes('OPS/image.png')!.first, 3);
    session.undo();
    expect(session.readBytes('OPS/image.png')!.first, 2);
  });

  test('非法源码可存草稿且保留资源树，但不能预览', () async {
    session.transaction(
      '暂存源码',
      (tx) => tx.writeText(session.opfPath, '<package'),
      validate: false,
    );
    expect(session.resources, hasLength(6));
    expect(session.spinePaths, ['OPS/chapter.xhtml']);
    expect(
      () => session.createPreviewSource(),
      throwsA(isA<EpubEditException>()),
    );
    final restored = await EpubEditSession.open(
      session.baseFile,
      draft: session.toDraft(),
    );
    expect(restored.readText(restored.opfPath), '<package');
    restored.close();
    session.undo();
    session.validate();
  });

  test('覆盖预览走正式章节入口，独立快照不污染原归档', () async {
    final original = session.readText('OPS/chapter.xhtml');
    session.replaceText(_paragraph(session), '预览新正文');
    final source = await session.createPreviewSource(
      options: const ReaderOpenOptions(contentWidth: 220, contentHeight: 200),
    );
    try {
      final pages = await source.loadChapter(0);
      expect(pages, isNotEmpty);
      expect((await source.loadAnchorChapter(0)).text, contains('预览新正文'));
      session.undo();
      expect(source.document.chapterXhtml(0), contains('预览新正文'));
      final fresh = await EpubEditSession.open(session.baseFile);
      expect(fresh.readText('OPS/chapter.xhtml'), original);
      fresh.close();
    } finally {
      source.close();
      await source.preparationsStopped;
    }
  });

  test('保存拒绝被阅读器容错跳过的坏 spine 引用，包源码草稿保留资源树', () {
    final original = session.readText(session.opfPath);
    session.transaction(
      '坏引用源码',
      (tx) => tx.writeText(
        session.opfPath,
        original.replaceFirst('</spine>', '<itemref idref="missing"/></spine>'),
      ),
    );
    expect(session.spinePaths, ['OPS/chapter.xhtml']);
    expect(session.validate, throwsA(isA<EpubEditException>()));
    session.transaction(
      '未完成包源码',
      (tx) => tx.writeText(session.opfPath, '<package/>'),
    );
    expect(session.spinePaths, ['OPS/chapter.xhtml']);
    expect(
      session.resources.firstWhere((e) => e.path == 'OPS/style.css').mediaType,
      'text/css',
    );
    expect(session.validate, throwsA(isA<EpubEditException>()));
    session.undo();
    session.undo();
    session.validate();
  });

  test('图片命令只写相对引用，历史受条数预算约束', () {
    session.insertImage(
      _paragraph(session),
      resourcePath: 'OPS/image.png',
      alt: '示意 & 图',
    );
    expect(
      session.readText('OPS/chapter.xhtml'),
      contains('src="image.png" alt="示意 &amp; 图"'),
    );
    final image = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .singleWhere((e) => e.tag == 'img');
    session.replaceImage(image, 'OPS/image.png', alt: '替换后的图片');
    expect(session.readText(image.path), contains('alt="替换后的图片"'));
    session.undo();
    expect(session.readText(image.path), contains('alt="示意 &amp; 图"'));
    for (var i = 0; i < 105; i++) {
      session.transaction(
        '第$i次',
        (tx) => tx.writeText('OPS/style.css', 'p{opacity:${i / 105}}'),
      );
    }
    expect(session.history.length, EpubEditSession.maxHistoryEntries);
    expect(session.historyDiscarded, greaterThan(0));
    expect(
      session.historyBytes,
      lessThanOrEqualTo(EpubEditSession.maxHistoryBytes),
    );
  });
}

EditableElementRef _paragraph(EpubEditSession session) => session
    .editableDocument('OPS/chapter.xhtml')
    .elements
    .singleWhere((node) => node.attributes['id'] == 'p');
