import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../reader/epub_chapter_source.dart';

/// 逐章构建正文锚点索引；不分页全书，不保存第二套原始 DOM。
Future<AnchorBook> buildRevisionAnchorBook(
  Uint8List bytes, {
  String? revision,
}) async {
  final source = await EpubChapterSource.open(bytes);
  try {
    final chapters = <AnchorChapter>[];
    for (var index = 0; index < source.chapterCount; index++) {
      chapters.add(source.anchorChapter(index));
      // 大书按章让出事件循环，保留取消与进度界面的响应。
      await Future<void>.delayed(Duration.zero);
    }
    return AnchorBook(
      revision: revision ?? sha256.convert(bytes).toString(),
      chapters: chapters,
    );
  } finally {
    source.close();
  }
}
