import 'dart:io';

import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/position/cfi.dart';

/// 从阅微或局域网设备换算出的本地可保存阅读位置。
class ReaMicroMappedProgress {
  /// 创建换算结果。
  const ReaMicroMappedProgress({
    required this.cfi,
    required this.spineIndex,
    required this.progress,
  });

  /// 已通过本地 EPUB 原文核验的 CFI。
  final String cfi;

  /// CFI 对应的本地章节序号。
  final int spineIndex;

  /// 与本地回收站结构一致的全书进度（0～1）。
  final double progress;
}

/// 把外部阅读位置映射到本地书籍。
///
/// 阅微历史版本会省略 spine 后的 `!`，不同客户端对叶节点编号也可能
/// 存在差异，因此不能把外部 CFI 直接写入本地进度。这里先尝试规范形态，
/// 失败时按对方提供的全书比例重新生成本地 CFI；只有通过原文核验的位置
/// 才会返回。
Future<ReaMicroMappedProgress?> mapReaMicroProgressToBook({
  required String sourcePath,
  required String cfi,
  required double progress,
}) async {
  if (sourcePath.trim().isEmpty) return null;
  final file = File(sourcePath);
  if (!await file.exists()) return null;
  final source = await EpubChapterSource.openFile(file, verifyCrc: false);
  try {
    final normalizedProgress = _unitProgress(progress);
    ReaMicroMappedProgress? exact;
    for (final candidate in epubCfiCandidates(cfi)) {
      final mapped = await _verifyCandidate(
        source,
        candidate,
        normalizedProgress,
      );
      if (mapped != null) {
        exact = mapped;
        break;
      }
    }
    final generated = await source.prepareCfiForReadingPercent(
      normalizedProgress,
    );
    if (generated != null) {
      final mapped = await _verifyCandidate(
        source,
        generated,
        normalizedProgress,
      );
      if (mapped != null) return mapped;
    }
    return exact;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on StateError {
    return null;
  } finally {
    source.close();
  }
}

Future<ReaMicroMappedProgress?> _verifyCandidate(
  EpubChapterSource source,
  String candidate,
  double fallbackProgress,
) async {
  final parsed = EpubCfi.parse(candidate);
  final spineIndex = parsed == null ? null : spineIndexOfCfi(parsed);
  if (spineIndex == null ||
      spineIndex < 0 ||
      spineIndex >= source.chapterCount ||
      source.isChapterMissing(spineIndex)) {
    return null;
  }
  final chapter = await source.loadAnchorChapter(spineIndex);
  final valid =
      chapter.offsetFor(candidate) != null ||
      source.isValidElementCfi(candidate);
  if (!valid) return null;
  final percent = source.readingPercentForCfi(candidate) ?? fallbackProgress;
  return ReaMicroMappedProgress(
    cfi: candidate,
    spineIndex: spineIndex,
    progress: _unitProgress(percent),
  );
}

double _unitProgress(double value) =>
    value.isNaN ? 0 : value.clamp(0.0, 1.0).toDouble();
