import 'dart:typed_data';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:reader_core/position/location_anchor.dart';

import 'package:reader_core/epub/epub_chapter_source.dart';

/// 逐章构建正文锚点索引；不分页全书，不保存第二套原始 DOM。
Future<AnchorBook> buildRevisionAnchorBook(
  Uint8List bytes, {
  String? revision,
}) async {
  final source = await EpubChapterSource.open(bytes);
  try {
    final chapters = <AnchorChapter>[];
    for (var index = 0; index < source.chapterCount; index++) {
      chapters.add(await source.loadAnchorChapter(index));
    }
    return AnchorBook(
      revision: revision ?? sha256.convert(bytes).toString(),
      chapters: chapters,
    );
  } finally {
    source.close();
    await source.preparationsStopped;
  }
}

/// 编辑文件逐章读取，避免为新旧两版各分配一份整书字节。
Future<AnchorBook> buildRevisionAnchorBookFile(
  File file, {
  required String revision,
  int? spineIndex,
}) async {
  final source = await EpubChapterSource.openFile(file);
  try {
    final chapters = [
      if (spineIndex != null)
        await source.loadAnchorChapter(spineIndex)
      else
        for (var index = 0; index < source.chapterCount; index++)
          await source.loadAnchorChapter(index),
    ];
    return AnchorBook(revision: revision, chapters: chapters);
  } finally {
    source.close();
    await source.preparationsStopped;
  }
}
