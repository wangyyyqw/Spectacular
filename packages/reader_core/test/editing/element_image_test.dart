import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:xml/xml.dart';

import 'edit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late EpubEditSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('element-image-');
    session = await EpubEditSession.open(await createEditingFixture(directory));
  });
  tearDown(() async {
    session.close();
    await directory.delete(recursive: true);
  });

  test('导入图片与插入正文同一事务，相对路径与命名空间保留且一步撤销', () {
    final before = session.readText('OPS/chapter.xhtml');
    final opf = session.readText(session.opfPath);
    final node = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .firstWhere((element) => element.attributes['id'] == 'second');
    final bytes = session.readBytes('OPS/image.png')!;
    session.insertImage(
      node,
      resourcePath: 'OPS/Images/插图 1.png',
      alt: '图 & "说明"',
      after: false,
      imageBytes: bytes,
      mediaType: 'image/png',
    );
    expect(session.history, hasLength(1));
    expect(
      session.readText(node.path),
      contains('Images/%E6%8F%92%E5%9B%BE%201.png'),
    );
    final image = session
        .editableDocument(node.path)
        .elements
        .firstWhere((e) => e.tag == 'img');
    expect(image.attributes['alt'], '图 & "说明"');
    expect(
      image.end,
      lessThanOrEqualTo(session.readText(node.path).indexOf('<p id="second"')),
    );
    final manifest = XmlDocument.parse(session.readText(session.opfPath));
    expect(
      manifest.descendants.whereType<XmlElement>().where(
        (e) =>
            e.name.local == 'item' &&
            e.getAttribute('media-type') == 'image/png',
      ),
      hasLength(2),
    );
    session.validate();
    session.undo();
    expect(session.readBytes('OPS/Images/插图 1.png'), isNull);
    expect(session.readText(node.path), before);
    expect(session.readText(session.opfPath), opf);
    session.redo();
    expect(session.readBytes('OPS/Images/插图 1.png'), bytes);
    session.validate();
  });

  test('替换只改目标引用，导入失败不遗留图片或修改 OPF', () {
    final paragraph = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .firstWhere((e) => e.tag == 'p');
    session.insertAfter(
      paragraph,
      '<img id="first" src="image.png"/><img id="other" src="image.png"/>',
    );
    final image = session
        .editableDocument(paragraph.path)
        .elements
        .firstWhere((e) => e.attributes['id'] == 'first');
    final before = session.readText(paragraph.path),
        opf = session.readText(session.opfPath);
    final count = session.history.length;
    expect(
      () => session.replaceImage(
        image,
        'OPS/image.png',
        imageBytes: session.readBytes('OPS/image.png'),
        mediaType: 'image/png',
      ),
      throwsA(isA<EpubEditException>()),
    );
    expect(session.history.length, count);
    expect(session.readText(paragraph.path), before);
    session.replaceImage(
      image,
      'OPS/new.png',
      alt: '新图',
      imageBytes: session.readBytes('OPS/image.png'),
      mediaType: 'image/png',
    );
    expect(session.history.length, count + 1);
    expect(
      session.readText(paragraph.path),
      contains('<img id="other" src="image.png"/>'),
    );
    session.undo();
    expect(session.readText(paragraph.path), before);
    expect(session.readText(session.opfPath), opf);
    expect(session.readBytes('OPS/new.png'), isNull);
  });

  test('空白自闭合 body 插图位于正文内部，沿用 XHTML 前缀', () {
    session.transaction(
      '准备空白章节',
      (tx) => tx.writeText(
        'OPS/chapter.xhtml',
        '<x:html xmlns:x="http://www.w3.org/1999/xhtml"><x:head><x:title>空白</x:title></x:head><x:body/></x:html>',
      ),
    );
    final body = session
        .editableDocument('OPS/chapter.xhtml')
        .elements
        .firstWhere((e) => e.tag == 'body');
    session.insertImage(body, resourcePath: 'OPS/image.png', after: false);
    final document = session.editableDocument(body.path);
    final image = document.elements.singleWhere((e) => e.tag == 'img');
    expect(image.qualifiedName, 'x:img');
    expect(image.parent!.tag, 'body');
    session.validate();
  });
}
