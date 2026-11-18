import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';

import 'edit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late EpubEditSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('edit-reference-test-');
    session = await EpubEditSession.open(await createEditingFixture(directory));
  });
  tearDown(() async {
    session.close();
    await directory.delete(recursive: true);
  });

  test('新增图片、超链接和片段断链阻止正式预览与导出', () async {
    for (final html in [
      '<img src="missing.png"/>',
      '<a href="missing.xhtml">缺页</a>',
      '<a href="chapter.xhtml#missing">缺片段</a>',
    ]) {
      _append(session, html);
      expect(
        () => session.createPreviewSource(),
        throwsA(isA<EpubEditException>()),
      );
      await expectLater(
        EpubWriter.write(session, File('${directory.path}/bad.epub')),
        throwsA(isA<EpubEditException>()),
      );
      expect(File('${directory.path}/bad.epub').existsSync(), isFalse);
      session.undo();
    }
  });

  test('只改正文 ID 也会阻止导出断链 NAV，同步目录后可导出', () async {
    const chapter = 'OPS/chapter.xhtml';
    PackageEditor(session)
        .setToc([const EditTocEntry('另一段', chapter, fragment: 'second')]);
    final base = File('${directory.path}/with-toc.epub');
    await EpubWriter.write(session, base);
    session.close();
    session = await EpubEditSession.open(base);
    ClassStyleEditor(session).writeSources({
      chapter: session
          .readText(chapter)
          .replaceFirst('id="second"', 'id="new"'),
    }, validate: true);
    expect(session.changedPaths, {chapter});
    final output = File('${directory.path}/export.epub');
    final broken = _brokenLink('OPS/edit-nav.xhtml', '$chapter#second');
    await expectLater(EpubWriter.write(session, output), broken);
    expect(output.existsSync(), isFalse);
    expect(() => session.createPreviewSource(), broken);

    PackageEditor(session)
        .setToc([const EditTocEntry('另一段', chapter, fragment: 'new')]);
    await EpubWriter.write(session, output);
    final reopened = await EpubEditSession.open(output);
    addTearDown(reopened.close);
    expect(PackageEditor(reopened).toc.single.fragment, 'new');
    expect(reopened.readText(chapter), contains('id="new"'));
  });

  test('只删除资源也会阻止导出仍引用它的未改动文件', () async {
    const target = 'OPS/image.png';
    session.transaction('删除图片', (tx) => tx.remove(target));
    final output = File('${directory.path}/deleted.epub');
    await expectLater(
      EpubWriter.write(session, output),
      _brokenLink(session.opfPath, target),
    );
    expect(output.existsSync(), isFalse);
  });

  test('反查入链保留历史断链告警，不因无关原书 XML 损坏阻止导出', () async {
    const chapter = 'OPS/chapter.xhtml';
    const notes = 'OPS/notes.xhtml';
    final base = session.baseFile;
    session.close();
    final archive = ZipDecoder().decodeBytes(await base.readAsBytes())
      ..addFile(ArchiveFile.string('OPS/invalid.xml', '<未闭合>'))
      ..addFile(
        ArchiveFile.string(
          chapter,
          editingXhtml.replaceFirst('id="e"', 'xml:id="e"'),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          notes,
          '<html><body>'
          '<a href="chapter.xhtml#legacy">旧断链</a>'
          '<a href="chapter.xhtml#e">有效链接</a></body></html>',
        ),
      );
    await base.writeAsBytes(ZipEncoder().encodeBytes(archive));
    session = await EpubEditSession.open(base);

    final source = session.readText(chapter).replaceFirst(' id="second"', '');
    ClassStyleEditor(session).writeSource(chapter, source);
    await EpubWriter.write(session, File('${directory.path}/legacy.epub'));
    expect(
      session.validationWarnings,
      contains(contains('$notes → $chapter#legacy')),
    );

    ClassStyleEditor(session)
        .writeSource(chapter, source.replaceFirst(' xml:id="e"', ''));
    final output = File('${directory.path}/removed-id.epub');
    await expectLater(
      EpubWriter.write(session, output),
      _brokenLink(notes, '$chapter#e'),
    );
    expect(output.existsSync(), isFalse);
  });

  test('新增 CSS url、import 和行内样式断链被识别，注释与字符串不误报', () {
    for (final css in [
      'p{background:url("missing.png")}',
      '@import "missing.css"; p{color:red}',
    ]) {
      session.transaction('改 CSS', (tx) => tx.writeText('OPS/style.css', css));
      expect(session.validate, throwsA(isA<EpubEditException>()));
      session.undo();
    }
    _append(session, '<p style="background:url(missing.png)">新段</p>');
    expect(session.validate, throwsA(isA<EpubEditException>()));
    session.undo();
    session.transaction(
      'CSS 字符串',
      (tx) => tx.writeText(
        'OPS/style.css',
        '/* url(missing.png) */ p::before{content:"url(missing.png)"}',
      ),
    );
    session.validate();
  });

  test('相对路径、XML ID、行内 style 与远程引用可以保存', () {
    _append(
      session,
      '<span xml:id="new-id">锚点</span><a href="#new-id">链接</a>'
      '<img src="image.png"/><a href="https://example.invalid/">远程</a>'
      '<p style="background:url(image.png)">图片</p>',
    );
    session.transaction(
      '有效 CSS',
      (tx) => tx.writeText(
        'OPS/style.css',
        '@import "style.css"; p{background:url(image.png)}',
      ),
    );
    session.validate();
  });

  test('原书既有断链保留告警，新增不同断链仍被拒绝', () async {
    session.close();
    final original = editingXhtml.replaceFirst(
      '</body>',
      '<a href="legacy.xhtml">原有断链</a></body>',
    );
    session = await EpubEditSession.open(
      await createEditingFixture(
        directory,
        chapterBytes: utf8.encode(original),
      ),
    );
    _append(session, '<p>新增正文</p>');
    session.validate();
    expect(session.validationWarnings, contains(contains('legacy.xhtml')));
    _append(session, '<a href="another.xhtml">新断链</a>');
    expect(session.validate, throwsA(isA<EpubEditException>()));
  });

  test('OPF 原有缺失资源和坏 idref不阻塞正文编辑，新增坏项拒绝', () async {
    final package = session
        .readText(session.opfPath)
        .replaceFirst(
          '</manifest>',
          '<item id="legacy" href="missing.png" media-type="image/png"/></manifest>',
        )
        .replaceFirst('</spine>', '<itemref idref="old-missing"/></spine>');
    session.close();
    session = await EpubEditSession.open(
      await createEditingFixture(directory, packageText: package),
    );
    _append(session, '<p>正文修改</p>');
    session.transaction(
      '包元数据修改',
      (tx) =>
          tx.writeText(session.opfPath, package.replaceFirst('编辑测试', '新书名')),
    );
    session.validate();
    expect(session.validationWarnings, contains(contains('missing.png')));
    expect(session.validationWarnings, contains(contains('old-missing')));
    session.transaction(
      '添加坏清单',
      (tx) => tx.writeText(
        session.opfPath,
        session
            .readText(session.opfPath)
            .replaceFirst(
              '</manifest>',
              '<item id="new" href="another.png" media-type="image/png"/></manifest>',
            ),
      ),
    );
    expect(session.validate, throwsA(isA<EpubEditException>()));
  });
}

Matcher _brokenLink(String source, String target) => throwsA(
  isA<EpubEditException>().having(
    (error) => error.message,
    '断链',
    contains('新增引用无效：$source → $target'),
  ),
);

void _append(EpubEditSession session, String html) {
  const path = 'OPS/chapter.xhtml';
  session.transaction(
    '改 XHTML',
    (tx) => tx.writeText(
      path,
      session.readText(path).replaceFirst('</body>', '$html</body>'),
    ),
  );
}
