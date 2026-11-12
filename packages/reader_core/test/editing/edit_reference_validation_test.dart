import 'dart:convert';
import 'dart:io';

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
