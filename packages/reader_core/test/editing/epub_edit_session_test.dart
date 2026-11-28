import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';
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

  test('连续保存切换基线后可撤销重做、恢复草稿并再次导出', () async {
    const path = 'OPS/chapter.xhtml';
    final first = editingXhtml.replaceFirst('甲&amp;', '第一次&amp;');
    session.transaction('第一次修改', (tx) => tx.writeText(path, first));
    final saved = File('${directory.path}/第一次.epub');
    await EpubWriter.write(session, saved);
    await session.acceptSavedFile(saved);
    expect(session.changedPaths, isEmpty);
    expect(session.baseFile.path, saved.absolute.path);
    session.undo();
    expect(session.readText(path), editingXhtml);
    session.redo();
    expect(session.readText(path), first);
    expect(session.changedPaths, isEmpty);

    final second = first.replaceFirst('第一次', '第二次');
    session.transaction('第二次修改', (tx) => tx.writeText(path, second));
    final recovered = await EpubEditSession.open(
      saved,
      draft: session.toDraft(),
    );
    expect(recovered.readText(path), second);
    recovered.close();
    final output = File('${directory.path}/第二次.epub');
    await EpubWriter.write(session, output);
    await session.acceptSavedFile(output);
    session.undo();
    expect(session.readText(path), first);
    session.undo();
    expect(session.readText(path), editingXhtml);
    session.redo();
    session.redo();
    expect(session.readText(path), second);
    expect(session.changedPaths, isEmpty);
  });

  test('保存新增和删除资源后保留撤销与重做分支', () async {
    const resource = 'OPS/extra.txt';
    session.transaction('新增资源', (tx) => tx.writeText(resource, '保留的资源'));
    final added = File('${directory.path}/新增.epub');
    await EpubWriter.write(session, added);
    await session.acceptSavedFile(added);
    session.undo();
    expect(session.readBytes(resource), isNull);
    final removed = File('${directory.path}/移除.epub');
    await EpubWriter.write(session, removed);
    await session.acceptSavedFile(removed);
    expect(session.canRedo, isTrue);
    session.redo();
    expect(session.readText(resource), '保留的资源');
    final reopened = await EpubEditSession.open(
      removed,
      draft: session.toDraft(),
    );
    expect(reopened.readText(resource), '保留的资源');
    reopened.close();
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

  EpubParagraphEdit select(String start, [String? end]) {
    const path = 'OPS/chapter.xhtml';
    final chapter = session.readText(path);
    String point(String text) =>
        session.cfiForSourceOffset(path, chapter.indexOf(text) + 1);
    return EpubParagraphEdit.fromSelection(
      session,
      0,
      point(start),
      point(end ?? start),
    );
  }

  test('单标签显示整段文本，保留原标签属性并转义输入', () {
    final edit = select('另一段');
    expect(edit.isHtml, isFalse);
    expect(edit.initialText, '另一段');
    edit.apply('另一段');
    expect(session.changedPaths, isEmpty);
    edit.apply('文字 <em> &');
    expect(
      session.readText(edit.first.path),
      editingXhtml.replaceFirst('另一段', '文字 &lt;em&gt; &amp;'),
    );
  });

  test('选中行内文字编辑完整源码，错误闭合不写入，修正后只替换该段', () {
    final edit = select('乙😀');
    const original = '<p id="p" class="note">甲&amp;<em id="e">乙😀</em>丙</p>';
    expect(edit.initialText, original);
    for (final invalid in [
      '<p><em>正文</p>',
      '<p>正文',
      '</p><p>',
      '<p><br></p>',
    ]) {
      expect(() => edit.apply(invalid), throwsA(isA<EpubEditException>()));
      expect(session.changedPaths, isEmpty);
      expect(session.readText(edit.first.path), editingXhtml);
    }
    const corrected = '<p data-text=">"><em>新正文</em><br/></p>';
    edit.apply(corrected);
    expect(
      session.readText(edit.first.path),
      editingXhtml.replaceFirst(original, corrected),
    );
  });

  test('跨同级段落保留中间源码和换行，自闭合标签进入源码模式', () {
    final edit = select('乙😀', '另一段');
    expect(edit.initialText, contains('</p>\n<p id="second">'));
    edit.apply('<p>上行<br/>下行</p>');
    final withBreak = select('下行');
    expect(withBreak.isHtml, isTrue);
    expect(withBreak.initialText, '<p>上行<br/>下行</p>');
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

  test('源码光标按实体解码后的 UTF-16 位置定位，标签回退到元素', () {
    const path = 'OPS/chapter.xhtml';
    final source = session.readText(path);
    final parsed = DocumentParser.parse(xhtml: source, spineIndex: 0);
    final offset = source.indexOf('乙😀') + '乙😀'.length;
    final cfi = EpubCfi.parse(session.cfiForSourceOffset(path, offset))!;
    expect((parsed.nodeAtCfi(cfi) as ParsedText).text, '乙😀');
    expect(cfi.charOffset, 3);
    final ampersand = source.indexOf('&amp;');
    for (var index = 1; index < 5; index++) {
      final partial = EpubCfi.parse(
        session.cfiForSourceOffset(path, ampersand + index),
      )!;
      expect(partial.charOffset, 1);
    }
    expect(
      EpubCfi.parse(session.cfiForSourceOffset(path, ampersand + 5))!
          .charOffset,
      2,
    );
    expect(
      session.cfiForSourceOffset(path, source.indexOf('id="e"') + 3),
      session.cfiForElement(
        session
            .editableDocument(path)
            .elements
            .singleWhere((element) => element.attributes['id'] == 'e'),
      ),
    );
    expect(
      () => session.cfiForSourceOffset(path, source.indexOf('<title>') + 2),
      throwsA(isA<EpubEditException>()),
    );
  });

  test('源码字符定位合并注释和 CDATA，数字实体按真实字符计数', () {
    const path = 'OPS/chapter.xhtml';
    final source = editingXhtml.replaceFirst(
      '甲&amp;<em id="e">乙😀</em>丙',
      '甲&#x1F600;<!--忽略--><![CDATA[乙&amp;]]><?位置 忽略?>丙',
    );
    session.transaction('设置字符样本', (tx) => tx.writeText(path, source));
    final parsed = DocumentParser.parse(xhtml: source, spineIndex: 0);
    for (final target in <(int, int)>[
      (source.indexOf('<!--'), 3),
      (source.indexOf('乙&amp;') + 3, 6),
      (source.indexOf(']]>'), 9),
      (source.indexOf('丙</p>') + 1, 10),
    ]) {
      final cfi = EpubCfi.parse(session.cfiForSourceOffset(path, target.$1))!;
      expect((parsed.nodeAtCfi(cfi) as ParsedText).text, '甲😀乙&amp;丙');
      expect(cfi.charOffset, target.$2);
    }
  });

  for (final (href, path) in [
    ('Fonts/像素.ttf', 'OPS/Fonts/像素.ttf'),
    ('Fonts/像素%20常规.ttf', 'OPS/Fonts/像素 常规.ttf'),
    ('Fonts/%E5%83%8F%E7%B4%A0.ttf', 'OPS/Fonts/像素.ttf'),
    ('Fonts/像素%2520.ttf', 'OPS/Fonts/像素%20.ttf'),
  ]) {
    test('资源树和预览正确解析清单中的多语言路径：$href', () async {
      final package = session
          .readText(session.opfPath)
          .replaceFirst(
            '</manifest>',
            '<item id="font" href="$href" media-type="font/ttf"/></manifest>',
          );
      session.transaction('添加多语言字体路径', (tx) {
        tx.writeText(session.opfPath, package);
        tx.writeBytes(path, Uint8List(12));
      });

      expect(
        session.resources
            .singleWhere((resource) => resource.path == path)
            .mediaType,
        'font/ttf',
      );
      expect(session.spinePaths, ['OPS/chapter.xhtml']);
      expect(session.previewPaths, ['OPS/chapter.xhtml']);
      final preview = await session.createPreviewSource(
        includeUnlistedHtml: true,
      );
      try {
        expect((await preview.loadAnchorChapter(0)).text, contains('甲&乙😀丙'));
        expect(session.readText(session.opfPath), package);
      } finally {
        preview.close();
        await preview.preparationsStopped;
      }
    });
  }

  test('非 spine HTML 独立加入预览，源码定位与预览顺序一致且不改书籍', () async {
    final package = PackageEditor(session);
    for (final name in ['z', 'a']) {
      package.addResource(
        'OPS/$name.xhtml',
        utf8.encode(editingXhtml.replaceFirst('另一段', '$name 附录')),
        'application/xhtml+xml',
      );
    }
    final original = session.readText(session.opfPath);
    final revision = session.revision;
    final paths = session.previewPaths;
    expect(paths, ['OPS/chapter.xhtml', 'OPS/z.xhtml', 'OPS/a.xhtml']);
    final preview = await session.createPreviewSource(
      includeUnlistedHtml: true,
    );
    try {
      for (var index = 1; index < paths.length; index++) {
        final path = paths[index];
        final source = session.readText(path);
        final cfi = session.cfiForSourceOffset(
          path,
          source.indexOf('附录') + 1,
          preview: true,
        );
        expect(preview.document.spine[index].href, path.split('/').last);
        expect((await preview.loadAnchorChapter(index)).text, contains('附录'));
        expect(
          session.resolveEditableElement(index, cfi, preview: true).text,
          contains('附录'),
        );
      }
      expect(session.spinePaths, ['OPS/chapter.xhtml']);
      expect(session.readText(session.opfPath), original);
      expect(session.revision, revision);
      expect(
        () => session.cfiForSourceOffset('OPS/z.xhtml', 1),
        throwsA(isA<EpubEditException>()),
      );
    } finally {
      preview.close();
      await preview.preparationsStopped;
    }
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
