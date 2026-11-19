import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:spectacular_epub_tools/src/core/epub_image_helper.dart';
import 'package:spectacular_epub_tools/src/core/epub_packer.dart';
import 'package:spectacular_epub_tools/src/features/ad_clean/ad_clean.dart';
import 'package:spectacular_epub_tools/src/features/comment/comment.dart';
import 'package:spectacular_epub_tools/src/features/convert_version/convert_version.dart';
import 'package:spectacular_epub_tools/src/features/epub_health/epub_health.dart';
import 'package:spectacular_epub_tools/src/features/epub_health/epub_health_repair.dart';
import 'package:spectacular_epub_tools/src/features/epub_health/epub_health_report.dart';
import 'package:spectacular_epub_tools/src/features/footnote_to_comment/footnote_to_comment.dart';
import 'package:spectacular_epub_tools/src/features/list_split_targets/list_split_targets.dart';
import 'package:spectacular_epub_tools/src/features/merge/merge.dart';
import 'package:spectacular_epub_tools/src/features/navigation_editor/navigation_editor.dart';
import 'package:spectacular_epub_tools/src/features/navigation_editor/navigation_model.dart';
import 'package:spectacular_epub_tools/src/features/reformat/reformat.dart';
import 'package:spectacular_epub_tools/src/features/span_to_footnote/span_to_footnote.dart';
import 'package:spectacular_epub_tools/src/features/split/split.dart';
import 'package:spectacular_epub_tools/src/features/yuewei/yuewei.dart';
import 'package:spectacular_epub_tools/src/features/zhangyue/zhangyue.dart';
import 'package:xml/xml.dart';

import 'support/structure_epub_fixture.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('spectacular-structure-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  String output(String name) => path.join(temporary.path, name);

  test('归档换名同步 XHTML、CSS 和 manifest，保留 container 指定的 OPF', () async {
    final fixture = StructureEpubFixture(opfPath: '内容/书籍.opf');
    final decoy = ArchiveFile.string('旧书.opf', '<package/>');
    fixture.archive.addFile(decoy);
    expect(EpubImageHelper.findOpfPath(fixture.archive), fixture.opfPath);
    fixture.archive.removeFile(decoy);
    final originalImage = fixture.pathFor('Images/cover.png');
    final renamedImage = fixture.pathFor('Images/cover.jpg');
    final jpeg = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 2, height: 2)),
    );
    EpubImageHelper.replaceFile(
      fixture.archive,
      originalImage,
      renamedImage,
      jpeg,
    );
    EpubImageHelper.addOrReplaceFileSafe(
      fixture.archive,
      ArchiveFile.string('temporary.bin', '待删除'),
    );
    final archive = EpubImageHelper.removeFiles(fixture.archive, {
      'temporary.bin',
    });
    await EpubImageHelper.saveArchive(
      archive,
      output('renamed.epub'),
      renameMap: {originalImage: renamedImage},
    );
    final reopened = await reopenStructureEpub(output('renamed.epub'));
    expect(reopened.findFile(originalImage), isNull);
    expect(reopened.findFile(renamedImage)!.content, jpeg);
    expect(reopened.findFile('temporary.bin'), isNull);
    expect(
      structureText(
        reopened,
        fixture.pathFor(StructureEpubFixture.chapterHrefs[0]),
      ),
      contains('../Images/cover.jpg'),
    );
    expect(
      structureText(reopened, fixture.pathFor('Styles/main.css')),
      contains('cover.jpg'),
    );
    final cover = structurePackage(reopened)
        .findAllElements('item', namespaceUri: '*')
        .singleWhere((item) => item.getAttribute('id') == 'cover');
    expect(cover.getAttribute('media-type'), 'image/jpeg');
  });

  test('归档换名按规范路径匹配，跨目录同名图片与外部链接保持不变', () async {
    final fixture = StructureEpubFixture(
      opfPath: '内容/书籍.opf',
      navigationDirectory: 'Navigation',
    );
    final originalImage = fixture.pathFor('Images/cover.png');
    final renamedImage = fixture.pathFor('转换 图/封面.jpg');
    final otherImage = fixture.pathFor('其他 图/cover.png');
    final otherBytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 3, height: 2)),
    );
    fixture.archive.addFile(ArchiveFile.bytes(otherImage, otherBytes));
    fixture.archive.addFile(
      ArchiveFile.string(
        fixture.opfPath,
        structureText(fixture.archive, fixture.opfPath).replaceFirst(
          '</manifest>',
          '<item id="other-cover" href="${Uri.encodeFull('其他 图/cover.png')}" media-type="image/png"/></manifest>',
        ),
      ),
    );
    fixture.setText(
      StructureEpubFixture.chapterHrefs[0],
      fixture
          .text(StructureEpubFixture.chapterHrefs[0])
          .replaceFirst(
            '</head>',
            '<style>.inline { background: url("../Images/cover.png#style"); }</style></head>',
          )
          .replaceFirst(
            '</body>',
            '''<img id="other" src="../其他%20图/cover.png"/>
<a id="normalized" href="../Images/../Images/cover.png?size=2&amp;mode=fit#preview">预览</a>
<img id="external" src="https://example.com/Images/cover.png"/>
<img id="remote" src="//example.com/Images/cover.png"/>
<p id="literal">cover.png ../Images/cover.png</p>
<p id="styled" style="background-image: url('../Images/cover.png#inline')">正文</p></body>''',
          ),
    );
    fixture.setText(
      'Styles/main.css',
      '''.target { background-image: url(../Images/./cover.png#css); }
.other { background-image: url("../其他%20图/cover.png"); }
.external { background-image: url("https://example.com/Images/cover.png"); }''',
    );
    fixture.setText(
      fixture.navHref,
      fixture
          .text(fixture.navHref)
          .replaceFirst(
            '</body>',
            '<img src="../Images/cover.png#nav" alt="封面"/></body>',
          ),
    );
    fixture.setText(
      fixture.ncxHref,
      fixture
          .text(fixture.ncxHref)
          .replaceFirst(
            '<navLabel>',
            '<navLabel><img src="../Images/cover.png#ncx"/>',
          ),
    );
    final jpeg = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 2, height: 2)),
    );
    EpubImageHelper.replaceFile(
      fixture.archive,
      originalImage,
      renamedImage,
      jpeg,
    );
    await EpubImageHelper.saveArchive(
      fixture.archive,
      output('same-name.epub'),
      renameMap: {originalImage: renamedImage},
    );
    final reopened = await reopenStructureEpub(output('same-name.epub'));
    expect(reopened.findFile(originalImage), isNull);
    expect(reopened.findFile(renamedImage)!.content, jpeg);
    expect(reopened.findFile(otherImage)!.content, otherBytes);
    final items = structurePackage(reopened)
        .findAllElements('item', namespaceUri: '*')
        .toList();
    final cover = items.singleWhere(
      (item) => item.getAttribute('id') == 'cover',
    );
    final other = items.singleWhere(
      (item) => item.getAttribute('id') == 'other-cover',
    );
    expect(cover.getAttribute('href'), Uri.encodeFull('转换 图/封面.jpg'));
    expect(cover.getAttribute('media-type'), 'image/jpeg');
    expect(other.getAttribute('href'), Uri.encodeFull('其他 图/cover.png'));
    expect(other.getAttribute('media-type'), 'image/png');
    final chapter = XmlDocument.parse(
      structureText(
        reopened,
        fixture.pathFor(StructureEpubFixture.chapterHrefs[0]),
      ),
    );
    final elementsById = {
      for (final element in chapter.descendants.whereType<XmlElement>())
        if (element.getAttribute('id') != null)
          element.getAttribute('id')!: element,
    };
    final targetHref = Uri.encodeFull('../转换 图/封面.jpg');
    expect(elementsById['other']!.getAttribute('src'), '../其他%20图/cover.png');
    expect(
      elementsById['normalized']!.getAttribute('href'),
      '$targetHref?size=2&mode=fit#preview',
    );
    expect(
      elementsById['external']!.getAttribute('src'),
      'https://example.com/Images/cover.png',
    );
    expect(
      elementsById['remote']!.getAttribute('src'),
      '//example.com/Images/cover.png',
    );
    expect(elementsById['literal']!.innerText, 'cover.png ../Images/cover.png');
    expect(
      elementsById['styled']!.getAttribute('style'),
      contains('$targetHref#inline'),
    );
    expect(
      chapter.findAllElements('style', namespaceUri: '*').single.innerText,
      contains('$targetHref#style'),
    );
    final css = structureText(reopened, fixture.pathFor('Styles/main.css'));
    expect(css, contains('$targetHref#css'));
    expect(css, contains('../其他%20图/cover.png'));
    expect(css, contains('https://example.com/Images/cover.png'));
    expect(
      structureText(reopened, fixture.pathFor(fixture.navHref)),
      contains('$targetHref#nav'),
    );
    expect(
      structureText(reopened, fixture.pathFor(fixture.ncxHref)),
      contains('$targetHref#ncx'),
    );
  });

  test('内存与流式打包生成 OCF 并补齐 XHTML，保留 SVG 和共享输入流', () async {
    final fixture = StructureEpubFixture(opfPath: 'book.opf');
    fixture.setText(
      StructureEpubFixture.chapterHrefs[0],
      '<h1 id="top">第一章</h1><h2 id="part">分节</h2><p>正文</p>',
    );
    fixture.archive.addFile(
      ArchiveFile.string(
        'cover.html',
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>',
      ),
    );
    await EpubPacker.pack(
      archive: fixture.archive,
      outputPath: output('packed.epub'),
    );
    final packed = await reopenStructureEpub(output('packed.epub'));
    final chapter = XmlDocument.parse(
      structureText(
        packed,
        fixture.pathFor(StructureEpubFixture.chapterHrefs[0]),
      ),
    );
    expect(chapter.rootElement.name.local, 'html');
    expect(chapter.findAllElements('head', namespaceUri: '*'), hasLength(1));
    expect(chapter.findAllElements('body', namespaceUri: '*'), hasLength(1));
    expect(
      XmlDocument.parse(structureText(packed, 'cover.html'))
          .rootElement
          .name
          .local,
      'svg',
    );
    final stream = InputFileStream(output('packed.epub'));
    try {
      final lazyArchive = ZipDecoder().decodeStream(stream);
      await EpubPacker.packStreaming(
        files: lazyArchive.files,
        outputPath: output('streamed.epub'),
      );
      await reopenStructureEpub(output('streamed.epub'));
      expect(
        lazyArchive.findFile(fixture.pathFor('Images/cover.png'))!.content,
        structurePngBytes,
      );
    } finally {
      stream.closeSync();
    }
  });

  for (final startVersion in ['2.0', '3.0']) {
    test('EPUB $startVersion 往返保留中文路径、正文、目录层级与锚点', () async {
      final fixture = StructureEpubFixture(
        opfPath: startVersion == '2.0' ? '内容/包/书籍.opf' : 'book.opf',
        version: startVersion,
        navigationDirectory: 'Navigation',
      );
      if (startVersion == '3.0') {
        await fixture.write(output('already3.epub'));
        await ConvertVersionOperation.execute(
          epubPath: output('already3.epub'),
          outputPath: output('same-version.epub'),
          targetVersion: '3.0',
        );
        final sameVersion = await reopenStructureEpub(
          output('same-version.epub'),
        );
        expect(
          structurePackage(sameVersion)
              .findAllElements('item', namespaceUri: '*')
              .where((item) => item.getAttribute('properties') == 'nav'),
          hasLength(1),
        );
        fixture.archive.removeFile(
          fixture.archive.findFile(fixture.pathFor(fixture.ncxHref))!,
        );
        fixture.archive.addFile(
          ArchiveFile.string(
            fixture.opfPath,
            structureText(fixture.archive, fixture.opfPath)
                .replaceFirst(RegExp(r'<item id="ncx"[^>]*/>'), '')
                .replaceFirst(' toc="ncx"', ''),
          ),
        );
      }
      await fixture.write(output('input.epub'));
      final originalText = _spineBodyText(
        await reopenStructureEpub(output('input.epub')),
      );
      final oppositeVersion = startVersion == '2.0' ? '3.0' : '2.0';
      await ConvertVersionOperation.execute(
        epubPath: output('input.epub'),
        outputPath: output('converted.epub'),
        targetVersion: oppositeVersion,
      );
      final converted = await reopenStructureEpub(output('converted.epub'));
      expect(
        structurePackage(converted).rootElement.getAttribute('version'),
        oppositeVersion,
      );
      await ConvertVersionOperation.execute(
        epubPath: output('converted.epub'),
        outputPath: output('roundtrip.epub'),
        targetVersion: startVersion,
      );
      final reopened = await reopenStructureEpub(output('roundtrip.epub'));
      expect(
        structurePackage(reopened).rootElement.getAttribute('version'),
        startVersion,
      );
      final navigation = await NavigationEditorOperation.load(
        output('roundtrip.epub'),
      );
      final toc = navigation.entries(NavigationSection.toc);
      expect(toc.map((entry) => entry.title), ['第一章', '分节', '第二章']);
      expect(toc.map((entry) => entry.level), [1, 2, 1]);
      expect(
        toc.first.href,
        '${fixture.pathFor(StructureEpubFixture.chapterHrefs[0])}#top',
      );
      expect(
        toc[1].href,
        '${fixture.pathFor(StructureEpubFixture.chapterHrefs[0])}#part',
      );
      expect(_spineBodyText(reopened), originalText);
    });
  }

  test('结构重排修复 manifest、大小写引用、CSS 和导航路径', () async {
    final fixture = StructureEpubFixture(opfPath: '内容/包/书籍.opf');
    fixture.setText(
      StructureEpubFixture.chapterHrefs[0],
      fixture
          .text(StructureEpubFixture.chapterHrefs[0])
          .replaceAll('../Styles/main.css', '../styles/MAIN.css')
          .replaceAll('../Images/cover.png', '../images/COVER.png'),
    );
    fixture.archive.addFile(
      ArchiveFile.string(
        fixture.opfPath,
        structureText(fixture.archive, fixture.opfPath).replaceFirst(
          '</manifest>',
          '<item id="invalid" href="missing.xhtml" media-type="application/xhtml+xml"/></manifest>',
        ),
      ),
    );
    fixture.setText('Styles/extra.css', 'p { margin: 0; }');
    await fixture.write(output('input.epub'));
    final log = await ReformatOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('reformatted.epub'),
    );
    final reopened = await reopenStructureEpub(output('reformatted.epub'));
    expect(log, contains('重构完成'));
    expect(EpubImageHelper.findOpfPath(reopened), 'OEBPS/content.opf');
    expect(reopened.findFile('OEBPS/Styles/extra.css'), isNotNull);
    final first = structureText(reopened, 'OEBPS/Text/chapter1.xhtml');
    expect(first, contains('../Styles/style.css'));
    expect(first, contains('../Images/cover.png'));
    final report = await EpubHealthInspector.scan(output('reformatted.epub'));
    expect(report.errorCount, 0, reason: report.toPrettyJson());
    final nav = await NavigationEditorOperation.load(
      output('reformatted.epub'),
    );
    expect(nav.entries(NavigationSection.toc).map((entry) => entry.title), [
      '第一章',
      '分节',
      '第二章',
    ]);
  });

  for (final version in ['2.0', '3.0']) {
    test('EPUB $version 导航由标题重建并 save 同步 NAV、NCX 和稳定锚点', () async {
      final fixture = StructureEpubFixture(
        opfPath: '内容/书籍.opf',
        version: version,
        navigationDirectory: 'Navigation',
      );
      await fixture.write(output('input.epub'));
      final generated = await NavigationEditorOperation.regenerateFromHeadings(
        output('input.epub'),
      );
      final toc = [...generated.entries(NavigationSection.toc)];
      expect(toc.map((entry) => entry.level), [1, 2, 1]);
      expect(toc.last.sourceHeadingIndex, 0);
      expect(
        toc.last.href,
        '${fixture.pathFor(StructureEpubFixture.chapterHrefs[1])}#epub-toolkit-heading-1-2',
      );
      toc[0] = toc[0].copyWith(title: '新的章名');
      final edited = generated.copyWith(
        sections: {
          for (final section in NavigationSection.values)
            section: section == NavigationSection.toc
                ? toc
                : [...generated.entries(section)],
        },
      );
      final result = await NavigationEditorOperation.save(
        epubPath: output('input.epub'),
        outputPath: output('navigation.epub'),
        navigation: edited,
      );
      final reopened = await reopenStructureEpub(
        result['outputPath']! as String,
      );
      final reloaded = await NavigationEditorOperation.load(
        output('navigation.epub'),
      );
      expect(reloaded.entries(NavigationSection.toc).first.title, '新的章名');
      expect(reloaded.entries(NavigationSection.toc).last.href, toc.last.href);
      expect(reloaded.entries(NavigationSection.pageList).single.title, '1');
      expect(reloaded.entries(NavigationSection.landmarks).single.title, '正文');
      expect(
        reloaded.issues.where(
          (issue) => issue.severity == NavigationValidationSeverity.error,
        ),
        isEmpty,
      );
      expect(
        structureText(
          reopened,
          fixture.pathFor(StructureEpubFixture.chapterHrefs[1]),
        ),
        contains('id="epub-toolkit-heading-1-2"'),
      );
      expect(
        structureText(reopened, fixture.pathFor(fixture.ncxHref)),
        contains('新的章名'),
      );
      if (version == '3.0') {
        expect(
          structureText(reopened, fixture.pathFor(fixture.navHref)),
          contains('新的章名'),
        );
      }
      final model = EpubNavigationDocument.fromJson(reloaded.toJson());
      expect(model.entries(NavigationSection.toc).last.href, toc.last.href);
    });
  }

  test('体检识别 ZIP、manifest 和 NAV 问题，selective 修复保留未选项', () async {
    final fixture = StructureEpubFixture(opfPath: '内容/书籍.opf');
    await fixture.write(output('valid.epub'));
    final valid = await EpubHealthInspector.scan(output('valid.epub'));
    expect(valid.errorCount, 0, reason: valid.toPrettyJson());
    expect(valid.warningCount, 0, reason: valid.toPrettyJson());
    fixture.archive.addFile(
      ArchiveFile.string(
        fixture.opfPath,
        structureText(fixture.archive, fixture.opfPath)
            .replaceFirst(
              'media-type="text/css"',
              'media-type="application/octet-stream"',
            )
            .replaceFirst(' properties="nav"', '')
            .replaceFirst(' properties="cover-image"', ''),
      ),
    );
    final mimetype = fixture.archive.findFile('mimetype')!;
    fixture.archive.removeFile(mimetype);
    fixture.archive.addFile(ArchiveFile.string('mimetype', 'text/plain'));
    await fixture.write(output('broken.epub'));
    final before = await EpubHealthInspector.scan(output('broken.epub'));
    final codes = before.issues.map((issue) => issue.code).toSet();
    expect(
      codes,
      containsAll([
        'mimetype-order',
        'mimetype-content',
        'mimetype-compressed',
        'manifest-media-type',
        'nav-missing',
        'cover-missing',
      ]),
    );
    final selected = before.fixes.singleWhere(
      (fix) => fix.kind == 'correctMediaType',
    );
    final partial = await EpubHealthRepairOperation.execute(
      epubPath: output('broken.epub'),
      outputPath: output('partial.epub'),
      selectedFixIds: [selected.id],
      reportDirectory: output('reports'),
    );
    final partialReport = EpubHealthReport.fromJson(
      partial['after']! as Map<String, Object?>,
    );
    expect(
      partialReport.issues.map((issue) => issue.code),
      isNot(contains('manifest-media-type')),
    );
    expect(
      partialReport.issues.map((issue) => issue.code),
      containsAll(['mimetype-content', 'nav-missing', 'cover-missing']),
    );
    final partiallyReopened = await EpubImageHelper.readArchive(
      output('partial.epub'),
    );
    expect(
      partiallyReopened
          .findFile(fixture.pathFor(StructureEpubFixture.chapterHrefs[0]))!
          .content,
      fixture.archive
          .findFile(fixture.pathFor(StructureEpubFixture.chapterHrefs[0]))!
          .content,
    );
    final fixed = await EpubHealthRepairOperation.execute(
      epubPath: output('partial.epub'),
      outputPath: output('healthy.epub'),
      selectedFixIds: partialReport.fixes.map((fix) => fix.id).toList(),
      reportDirectory: output('reports'),
    );
    await reopenStructureEpub(output('healthy.epub'));
    final after = await EpubHealthInspector.scan(output('healthy.epub'));
    expect(after.errorCount, 0, reason: after.toPrettyJson());
    expect(after.warningCount, 0, reason: after.toPrettyJson());
    final jsonReport = jsonDecode(
      await File(fixed['afterJsonReportPath']! as String).readAsString(),
    ) as Map<String, Object?>;
    expect(EpubHealthReport.fromJson(jsonReport).errorCount, 0);
    expect(
      await File(fixed['afterHtmlReportPath']! as String).readAsString(),
      contains('未发现错误、警告或建议'),
    );
  });

  test('缺失 container 的安全修复仍定位任意 OPF 路径', () async {
    final fixture = StructureEpubFixture(opfPath: '内容/包/任意.opf');
    fixture.archive.removeFile(
      fixture.archive.findFile('META-INF/container.xml')!,
    );
    await fixture.write(output('input.epub'));
    final before = await EpubHealthInspector.scan(output('input.epub'));
    final fix = before.fixes.singleWhere(
      (fix) => fix.kind == 'repairContainer',
    );
    await EpubHealthRepairOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('container.epub'),
      selectedFixIds: [fix.id],
    );
    final reopened = await reopenStructureEpub(output('container.epub'));
    expect(EpubImageHelper.findOpfPath(reopened), fixture.opfPath);
  });

  test('广告正则按多条规则改写实际正文，输出仍可打开', () async {
    final fixture = StructureEpubFixture(opfPath: '内容/包/书籍.opf');
    fixture.setText(
      StructureEpubFixture.chapterHrefs[0],
      fixture
          .text(StructureEpubFixture.chapterHrefs[0])
          .replaceFirst('甲书正文', '甲书正文广告123结束待替换'),
    );
    await fixture.write(output('input.epub'));
    await AdCleanOperation.execute(
      epubPath: output('input.epub'),
      outputPath: output('clean.epub'),
      patterns: r'广告\d+结束||||||待替换|||保留文本',
    );
    final reopened = await reopenStructureEpub(output('clean.epub'));
    final chapter = structureText(
      reopened,
      fixture.pathFor(StructureEpubFixture.chapterHrefs[0]),
    );
    expect(chapter, contains('甲书正文保留文本'));
    expect(chapter, isNot(contains('广告123')));
    expect(
      structureText(
        reopened,
        fixture.pathFor(StructureEpubFixture.chapterHrefs[1]),
      ),
      fixture.text(StructureEpubFixture.chapterHrefs[1]),
    );
    await expectLater(
      AdCleanOperation.execute(
        epubPath: output('input.epub'),
        outputPath: output('invalid.epub'),
        patterns: '[|||',
      ),
      throwsFormatException,
    );
    expect(await File(output('invalid.epub')).exists(), isFalse);
  });

  for (final withIcon in [false, true]) {
    test('三种批注保存正文、规避已有 ID 并支持图标可选：$withIcon', () async {
      final fixture = StructureEpubFixture(opfPath: '内容/书籍.opf');
      fixture.setText(
        StructureEpubFixture.chapterHrefs[0],
        fixture
            .text(StructureEpubFixture.chapterHrefs[0])
            .replaceFirst('甲书正文', '甲书正文<span id="fn1"></span>[批注甲]继续[批注乙]'),
      );
      await fixture.write(output('input.epub'));
      final commentLog = await CommentOperation.execute(
        epubPath: output('input.epub'),
        outputPath: output('comments.epub'),
        regexPattern: r'\[(.*?)\]',
        notePngBytes: withIcon ? structurePngBytes : null,
      );
      expect(commentLog, contains('共替换 2 处'));
      final commented = await reopenStructureEpub(output('comments.epub'));
      final chapterPath = fixture.pathFor(StructureEpubFixture.chapterHrefs[0]);
      expect(
        structureText(commented, chapterPath),
        contains('data-wr-footernote="批注甲"'),
      );
      if (withIcon) {
        expect(
          commented.findFile(fixture.pathFor('Images/note.png'))!.content,
          structurePngBytes,
        );
      }
      final commentedReport = await EpubHealthInspector.scan(
        output('comments.epub'),
      );
      expect(
        commentedReport.errorCount,
        0,
        reason: commentedReport.toPrettyJson(),
      );
      await SpanToFootnoteOperation.execute(
        epubPath: output('comments.epub'),
        outputPath: output('footnotes.epub'),
        footnoteColor: '#123456',
        noterefColor: '#654321',
      );
      final footnotes = await reopenStructureEpub(output('footnotes.epub'));
      final parsed = XmlDocument.parse(structureText(footnotes, chapterPath));
      expect(parsed.findAllElements('aside', namespaceUri: '*'), hasLength(2));
      expect(structureText(footnotes, chapterPath), contains('#123456'));
      expect(structureText(footnotes, chapterPath), contains('href="#fn2"'));
      await FootnoteToCommentOperation.execute(
        epubPath: output('footnotes.epub'),
        outputPath: output('popups.epub'),
        regexPattern: r'^#fn',
        notePngBytes: withIcon ? structurePngBytes : null,
      );
      final popups = await reopenStructureEpub(output('popups.epub'));
      final popupChapter = XmlDocument.parse(
        structureText(popups, chapterPath),
      );
      expect(popupChapter.findAllElements('aside', namespaceUri: '*'), isEmpty);
      expect(
        popupChapter
            .findAllElements('span', namespaceUri: '*')
            .map((span) => span.getAttribute('data-wr-footernote'))
            .whereType<String>(),
        ['批注甲', '批注乙'],
      );
      final report = await EpubHealthInspector.scan(output('popups.epub'));
      expect(report.errorCount, 0, reason: report.toPrettyJson());
    });
  }

  for (final withIcon in [false, true]) {
    test('阅微与掌阅保留脚注、返回锚点并支持图标可选：$withIcon', () async {
      final fixture = StructureEpubFixture(opfPath: '内容/书籍.opf');
      fixture.setText(
        StructureEpubFixture.chapterHrefs[0],
        fixture
            .text(StructureEpubFixture.chapterHrefs[0])
            .replaceFirst(
              '甲书正文',
              '甲书正文<span class="reader js_readerFooterNote" data-wr-footernote="甲 &amp; &quot;乙&quot;"></span>',
            ),
      );
      await fixture.write(output('yuewei.epub'));
      await YueweiOperation.execute(
        epubPath: output('yuewei.epub'),
        outputPath: output('duokan.epub'),
        notePngBytes: withIcon ? structurePngBytes : null,
      );
      final chapterPath = fixture.pathFor(StructureEpubFixture.chapterHrefs[0]);
      final converted = await reopenStructureEpub(output('duokan.epub'));
      final yueweiChapter = XmlDocument.parse(
        structureText(converted, chapterPath),
      );
      final aside = yueweiChapter
          .findAllElements('aside', namespaceUri: '*')
          .single;
      expect(aside.innerText.trim(), '甲 & "乙"');
      expect(
        aside
            .findAllElements('a', namespaceUri: '*')
            .single
            .getAttribute('href'),
        '#note_ref1',
      );
      if (withIcon) {
        expect(
          structureText(converted, chapterPath),
          contains('src="../Images/note.png"'),
        );
      }
      final inline = fixture
          .text(StructureEpubFixture.chapterHrefs[0])
          .replaceFirst('甲书正文<span class="reader js_readerFooterNote" data-wr-footernote="甲 &amp; &quot;乙&quot;"></span>', '''甲书正文<sup><a class="duokan-footnote" epub:type="noteref" href="#zy1" id="zy_ref1">
<img class="zhangyue-footnote" src="../Images/cover.png" alt="注"/></a></sup>
<aside epub:type="footnote" id="zy1"><ol class="duokan-footnote-content">
<li class="duokan-footnote-item">掌阅 &amp; <em>注释</em></li></ol></aside>''');
      fixture.setText(StructureEpubFixture.chapterHrefs[0], inline);
      await fixture.write(output('zhangyue.epub'));
      await ZhangyueOperation.execute(
        epubPath: output('zhangyue.epub'),
        outputPath: output('zhangyue-duokan.epub'),
        notePngBytes: withIcon ? structurePngBytes : null,
      );
      final zhangyue = await reopenStructureEpub(
        output('zhangyue-duokan.epub'),
      );
      final zhangyueChapter = XmlDocument.parse(
        structureText(zhangyue, chapterPath),
      );
      final zhangyueAside = zhangyueChapter
          .findAllElements('aside', namespaceUri: '*')
          .single;
      expect(zhangyueAside.innerText.trim(), '掌阅 & 注释');
      expect(
        zhangyueAside
            .findAllElements('a', namespaceUri: '*')
            .single
            .getAttribute('href'),
        '#zy_ref1',
      );
      for (final filePath in [
        output('duokan.epub'),
        output('zhangyue-duokan.epub'),
      ]) {
        final report = await EpubHealthInspector.scan(filePath);
        expect(report.errorCount, 0, reason: report.toPrettyJson());
      }
    });
  }

  test('EPUB 2 拆分保留目录层级，NCX 标识符与分卷 OPF 一致', () async {
    final fixture = StructureEpubFixture(
      opfPath: '内容/包/书籍.opf',
      version: '2.0',
      navigationDirectory: 'Navigation',
    );
    await fixture.write(output('input.epub'));
    final files = <String>[];
    await SplitOperation.execute(
      epubPath: output('input.epub'),
      outputDir: output('parts'),
      splitPoints: [2],
      onOutput: files.add,
    );
    expect(files, hasLength(2));
    for (final filePath in files) {
      final reopened = await reopenStructureEpub(filePath);
      final package = structurePackage(reopened);
      expect(package.rootElement.getAttribute('version'), '2.0');
      final identifier = package
          .findAllElements('identifier', namespaceUri: '*')
          .single
          .innerText;
      final ncx = XmlDocument.parse(
        structureText(reopened, fixture.pathFor('toc_split.ncx')),
      );
      expect(
        ncx
            .findAllElements('meta', namespaceUri: '*')
            .singleWhere((element) => element.getAttribute('name') == 'dtb:uid')
            .getAttribute('content'),
        identifier,
      );
      final report = await EpubHealthInspector.scan(filePath);
      expect(report.errorCount, 0, reason: report.toPrettyJson());
    }
    final firstNavigation = await NavigationEditorOperation.load(files.first);
    expect(
      firstNavigation
          .entries(NavigationSection.toc)
          .map((entry) => entry.level),
      [1, 2],
    );
    final secondNavigation = await NavigationEditorOperation.load(files.last);
    expect(secondNavigation.entries(NavigationSection.toc).single.title, '第二章');
  });

  test('跨书 merge 处理同名文件和 ID 冲突，split 保持各分卷正文与资源', () async {
    final first = StructureEpubFixture(
      opfPath: '内容/第一本.opf',
      version: '2.0',
      title: '甲书',
      identifier: 'urn:structure:first',
      navigationDirectory: 'Navigation',
    );
    final second = StructureEpubFixture(
      opfPath: '内容/第二本.opf',
      title: '乙书',
      identifier: 'urn:structure:second',
      navigationDirectory: 'Navigation',
    );
    second.setText(
      StructureEpubFixture.chapterHrefs[0],
      second
          .text(StructureEpubFixture.chapterHrefs[0])
          .replaceFirst('甲书正文', '丙书正文'),
    );
    second.setText(
      StructureEpubFixture.chapterHrefs[1],
      second
          .text(StructureEpubFixture.chapterHrefs[1])
          .replaceFirst('乙书正文', '丁书正文'),
    );
    await first.write(output('first.epub'));
    await second.write(output('second.epub'));
    final log = await MergeOperation.execute(
      inputPaths: [output('first.epub'), output('second.epub')],
      outputPath: output('merged.epub'),
      options: const MergeOptions(
        title: '合集',
        author: '合集作者',
        language: 'zh-CN',
      ),
    );
    final merged = await reopenStructureEpub(output('merged.epub'));
    expect(log, contains('路径冲突'));
    expect(structurePackage(merged).rootElement.getAttribute('version'), '3.0');
    expect(
      structurePackage(merged)
          .findAllElements('creator', namespaceUri: '*')
          .single
          .innerText,
      '合集作者',
    );
    final navigation = await NavigationEditorOperation.load(
      output('merged.epub'),
    );
    expect(navigation.entries(NavigationSection.toc), hasLength(8));
    expect(
      navigation.entries(NavigationSection.toc).map((entry) => entry.level),
      [1, 2, 3, 2, 1, 2, 3, 2],
    );
    expect(
      navigation.issues.where(
        (issue) => issue.severity == NavigationValidationSeverity.error,
      ),
      isEmpty,
    );
    final targets = await ListSplitTargetsOperation.execute(
      epubPath: output('merged.epub'),
    );
    expect(targets, hasLength(8));
    final splitPoint = targets.indexWhere(
      (target) => target.href.contains('vol2_'),
    );
    expect(splitPoint, greaterThan(0));
    final written = <String>[];
    await SplitOperation.execute(
      epubPath: output('merged.epub'),
      outputDir: output('parts'),
      splitPoints: [splitPoint],
      onOutput: written.add,
    );
    expect(written, hasLength(2));
    final identifiers = <String>{};
    final bodyTexts = <String>[];
    for (final part in written) {
      final reopened = await reopenStructureEpub(part);
      identifiers.add(
        structurePackage(reopened)
            .findAllElements('identifier', namespaceUri: '*')
            .single
            .innerText,
      );
      bodyTexts.add(_spineBodyText(reopened));
      final report = await EpubHealthInspector.scan(part);
      expect(report.errorCount, 0, reason: report.toPrettyJson());
    }
    expect(identifiers, hasLength(2));
    expect(bodyTexts.first, contains('甲书正文'));
    expect(bodyTexts.first, contains('乙书正文'));
    expect(bodyTexts.first, isNot(contains('丙书正文')));
    expect(bodyTexts.last, contains('丙书正文'));
    expect(bodyTexts.last, contains('丁书正文'));
    expect(bodyTexts.last, isNot(contains('甲书正文')));
  });
}

String _spineBodyText(Archive archive) {
  final package = structurePackage(archive);
  final opfDirectory = path.posix.dirname(
    EpubImageHelper.findOpfPath(archive)!,
  );
  final hrefs = {
    for (final item in package.findAllElements('item', namespaceUri: '*'))
      item.getAttribute('id')!: item.getAttribute('href')!,
  };
  return package
      .findAllElements('itemref', namespaceUri: '*')
      .map((itemref) {
        final resource = path.posix.normalize(
          path.posix.join(
            opfDirectory,
            Uri.decodeFull(hrefs[itemref.getAttribute('idref')]!),
          ),
        );
        return XmlDocument.parse(structureText(archive, resource))
            .findAllElements('body', namespaceUri: '*')
            .single
            .innerText;
      })
      .join('\n');
}
