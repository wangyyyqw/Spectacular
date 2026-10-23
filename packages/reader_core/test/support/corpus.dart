import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 从当前目录向上查找仓库根的本地样本库（不入库）。
Directory? findCorpusRoot() {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}

/// 读取本地样本字节；样本缺失返回 null。
Uint8List? readSampleBytes(Directory? corpus, String fileName) {
  if (corpus == null) {
    return null;
  }
  final file = File('${corpus.path}/$fileName');
  if (!file.existsSync()) {
    return null;
  }
  return file.readAsBytesSync();
}

/// 构造一个最小 ZIP 字节（测试损坏/缺文件场景）。
Uint8List buildZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encodeBytes(archive);
}

/// 非 ZIP 的垃圾字节，用于错误路径测试。
Uint8List buildGarbage() =>
    Uint8List.fromList(List<int>.generate(128, (i) => i));
