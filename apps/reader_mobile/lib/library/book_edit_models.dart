import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

typedef EditDraftSerializer = Map<String, dynamic> Function(
  String Function(String path, Uint8List bytes) storeBlob,
);

/// 一个已原子提交的草稿快照；资源引用只能指向该快照内文件。
class BookEditDraft {
  const BookEditDraft({
    required this.baseRevision,
    required this.sourceFile,
    required this.data,
    required this.directory,
  });

  final String baseRevision;
  final File sourceFile;
  final Map<String, dynamic> data;
  final Directory directory;

  Uint8List readBlob(String reference) {
    if (!RegExp(r'^[a-f0-9]{64}\.blob$').hasMatch(reference)) {
      throw const FormatException('草稿资源引用无效');
    }
    return File(p.join(directory.path, reference)).readAsBytesSync();
  }
}

class BookEditVersion {
  const BookEditVersion({
    required this.kind,
    required this.sourceFile,
    required this.revision,
    required this.summary,
    required this.createdAt,
  });

  final String kind;
  final File sourceFile;
  final String revision;
  final String summary;
  final DateTime createdAt;
}
