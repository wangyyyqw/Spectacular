import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/rea_micro/rea_micro_progress_mapping.dart';

import '../support/test_epub.dart';

void main() {
  test('阅微省略间接引用分隔符时按全书比例生成本地位置', () async {
    final dir = Directory.systemTemp.createTempSync('rea-progress-map');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/book.epub');
    await file.writeAsBytes(
      buildTestEpub(
        title: '局域网进度',
        paragraphs: const <String>[
          '第一段用于验证外部阅读位置可以安全换算到本地原文。',
          '第二段提供足够的正文偏移，确保比例不会落在章节之外。',
          '第三段继续补充内容，以便生成稳定的章节内位置。',
        ],
      ),
      flush: true,
    );

    final mapped = await mapReaMicroProgressToBook(
      sourcePath: file.path,
      cfi: 'epubcfi(/6/2/4/2/1)',
      progress: 0.42,
    );

    expect(mapped, isNotNull);
    expect(EpubCfi.parse(mapped!.cfi), isNotNull);
    expect(mapped.spineIndex, 0);
    expect(mapped.progress, closeTo(0.42, 0.08));
  });

  test('请求比例超出范围时钳制到书首或书尾', () async {
    final dir = Directory.systemTemp.createTempSync('rea-progress-map');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/book.epub');
    await file.writeAsBytes(buildTestEpub(), flush: true);

    final mapped = await mapReaMicroProgressToBook(
      sourcePath: file.path,
      cfi: 'epubcfi(/6/2!/4/2/1)',
      progress: 2,
    );

    expect(mapped, isNotNull);
    expect(mapped!.progress, inInclusiveRange(0, 1));
    expect(mapped.spineIndex, 0);
  });
}
