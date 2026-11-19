import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/source/format_opener.dart';

import 'edit_fixture.dart';

Future<File> _relocated(File input, Directory directory) async {
  final original = ZipDecoder().decodeBytes(await input.readAsBytes());
  final archive = Archive();
  for (final file in original.files) {
    final name = file.name.replaceFirst('OPS/', 'OEBPS/');
    final bytes = file.name == 'META-INF/container.xml'
        ? utf8.encode(
            utf8
                .decode(file.content as List<int>)
                .replaceFirst('OPS/book.opf', 'OEBPS/book.opf'),
          )
        : file.content as List<int>;
    archive.addFile(
      name == 'mimetype'
          ? ArchiveFile.noCompress(name, bytes.length, bytes)
          : ArchiveFile.bytes(name, bytes),
    );
  }
  final output = File('${directory.path}/relocated.epub');
  await output.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return output;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('整包结果一次发布，OPF 迁移可撤销，正式分页与导出重开有效', () async {
    final directory = await Directory.systemTemp.createTemp('tool-result-');
    final input = await createEditingFixture(directory);
    final original = await input.readAsBytes();
    final session = await EpubEditSession.open(input);
    final candidate = await EpubEditSession.open(
      await _relocated(input, directory),
    );
    addTearDown(() async {
      session.close();
      candidate.close();
      await directory.delete(recursive: true);
    });
    final events = <EpubEditChange>[];
    final subscription = session.changes.listen(events.add);
    addTearDown(subscription.cancel);

    session.replaceWith(candidate, label: '结构迁移');
    expect(session.revision, 1);
    expect(events, hasLength(1));
    expect(session.opfPath, 'OEBPS/book.opf');
    expect(session.spinePaths, ['OEBPS/chapter.xhtml']);
    expect(session.readBytes('OPS/chapter.xhtml'), isNull);
    expect(
      session.readBytes('OEBPS/image.png'),
      candidate.readBytes('OEBPS/image.png'),
    );
    final preview = await session.createPreviewSource(
      options: const ReaderOpenOptions(contentWidth: 320, contentHeight: 728),
    );
    expect((await preview.loadAnchorChapter(0)).text, contains('另一段'));
    expect(await preview.loadChapter(0), isNotEmpty);
    preview.close();
    await preview.preparationsStopped;
    final output = File('${directory.path}/saved.epub');
    await EpubWriter.write(session, output);
    final reopened = await openEpubFile(output, verifyCrc: true);
    expect(reopened.ok, isTrue);
    expect(reopened.document!.opfPath, 'OEBPS/book.opf');
    reopened.document!.archive.close();

    session.undo();
    expect(session.opfPath, 'OPS/book.opf');
    expect(session.spinePaths, ['OPS/chapter.xhtml']);
    expect(session.readText('OPS/chapter.xhtml'), editingXhtml);
    session.redo();
    expect(session.opfPath, 'OEBPS/book.opf');
    expect(await input.readAsBytes(), original);
  });

  test('相同结果不增加历史，新增断链或非法候选不会发布', () async {
    final directory = await Directory.systemTemp.createTemp('tool-atomic-');
    final input = await createEditingFixture(directory);
    final session = await EpubEditSession.open(input);
    final candidate = await EpubEditSession.open(input);
    addTearDown(() async {
      session.close();
      candidate.close();
      await directory.delete(recursive: true);
    });
    session.replaceWith(candidate, label: '无变化');
    expect(session.revision, 0);
    candidate.transaction(
      '坏引用',
      (tx) => tx.writeText(
        'OPS/chapter.xhtml',
        editingXhtml.replaceFirst('另一段', '<img src="missing.png"/>'),
      ),
    );
    expect(
      () => session.replaceWith(candidate, label: '失败结果'),
      throwsA(isA<EpubEditException>()),
    );
    expect(session.revision, 0);
    expect(session.changedPaths, isEmpty);
    expect(session.readText('OPS/chapter.xhtml'), editingXhtml);
  });
}
