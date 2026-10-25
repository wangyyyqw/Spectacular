import 'package:reader_core/layout/paginator.dart';

/// 章节纯文本与块偏移表（P4-24/25 共用，保证索引与定位同一套偏移）。
///
/// 规则（§66.1）：块按页序去重，块间插一个 `\n`；块的起始偏移就是它在
/// 纯文本里的下标。
class ChapterText {
  ChapterText._(this.text, this.blocks);

  /// 由分页结果构建。
  factory ChapterText.fromPages(List<PageContent> pages) {
    final blocks = <ChapterBlock>[];
    final seen = <Object>{};
    final buffer = StringBuffer();
    for (final page in pages) {
      for (final slice in page.slices) {
        final block = slice.block;
        if (!seen.add(block)) {
          continue;
        }
        final content = block.layout.text;
        if (content.isEmpty) {
          continue;
        }
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        blocks.add(ChapterBlock(start: buffer.length, block: block));
        buffer.write(content);
      }
    }
    return ChapterText._(buffer.toString(), blocks);
  }

  /// 纯文本。
  final String text;

  /// 块偏移表（按起始偏移升序）。
  final List<ChapterBlock> blocks;

  /// 包含该字符偏移的块；越界返回 null。
  ChapterBlock? blockAt(int charOffset) {
    for (final item in blocks) {
      final end = item.start + item.block.layout.text.length;
      if (charOffset >= item.start && charOffset < end) {
        return item;
      }
    }
    return null;
  }

  /// 字符偏移 → (块, 块内偏移)。
  ({ChapterBlock block, int localOffset})? locate(int charOffset) {
    final block = blockAt(charOffset);
    if (block == null) {
      return null;
    }
    return (block: block, localOffset: charOffset - block.start);
  }
}

/// 一个块在章节纯文本中的位置。
class ChapterBlock {
  /// 创建块偏移。
  const ChapterBlock({required this.start, required this.block});

  /// 块在纯文本中的起始偏移。
  final int start;

  /// 块本身。
  final PageBlock block;
}
