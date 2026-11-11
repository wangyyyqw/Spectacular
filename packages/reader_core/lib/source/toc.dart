import '../src/api/models.dart' show TocEntry;

/// 目录项 + 层级（P4-11：面板按层级缩进展示）。
typedef TocRow = ({TocEntry entry, int depth});

/// 把目录树展开成线性行（深度优先，depth 从 1 起）。
List<TocRow> flattenToc(List<TocEntry> entries, {int depth = 1}) {
  final rows = <TocRow>[];
  for (final entry in entries) {
    rows.add((entry: entry, depth: depth));
    if (entry.children.isNotEmpty) {
      rows.addAll(flattenToc(entry.children, depth: depth + 1));
    }
  }
  return rows;
}
