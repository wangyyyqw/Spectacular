part of 'package_editor.dart';

class EditSearchMatch {
  const EditSearchMatch({
    required this.path,
    required this.start,
    required this.end,
    required this.text,
    required this.revision,
    this.groups = const [],
  });
  final String path;
  final int start;
  final int end;
  final String text;
  final int revision;
  final List<String?> groups;
}

extension PackageSearchCommands on PackageEditor {
  /// [paths] 限定搜索文件；为空集合表示当前范围没有可搜索文件。
  List<EditSearchMatch> find(
    String query, {
    bool caseSensitive = true,
    bool regex = false,
    Set<String>? paths,
  }) {
    if (query.isEmpty) return [];
    final pattern = RegExp(
      regex ? query : RegExp.escape(query),
      caseSensitive: caseSensitive,
      multiLine: true,
    );
    return [
      for (final resource in session.resources.where(
        (resource) =>
            _textResource(resource) &&
            (paths == null || paths.contains(resource.path)),
      ))
        for (final match in pattern.allMatches(session.readText(resource.path)))
          EditSearchMatch(
            path: resource.path,
            start: match.start,
            end: match.end,
            text: match[0]!,
            revision: session.revision,
            groups: [for (var i = 1; i <= match.groupCount; i++) match[i]],
          ),
    ];
  }

  void replaceAll(List<EditSearchMatch> matches, String replacement) {
    final byPath = <String, List<EditSearchMatch>>{};
    for (final match in matches) {
      if (match.revision != session.revision) throw StateError('文档已变化，请重新查找');
      byPath.putIfAbsent(match.path, () => []).add(match);
    }
    session.transaction('全书查找替换', (tx) {
      for (final entry in byPath.entries) {
        var source = tx.readText(entry.key);
        final sorted = entry.value..sort((a, b) => b.start.compareTo(a.start));
        var limit = source.length;
        for (final match in sorted) {
          if (match.end > limit ||
              source.substring(match.start, match.end) != match.text) {
            throw StateError('匹配范围冲突，请重新查找');
          }
          final value = replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (
            group,
          ) {
            final index = int.parse(group[1]!);
            return index == 0
                ? match.text
                : index <= match.groups.length
                ? match.groups[index - 1] ?? ''
                : group[0]!;
          });
          source = source.replaceRange(match.start, match.end, value);
          limit = match.start;
        }
        tx.writeText(entry.key, source);
      }
    });
  }
}
