import 'dart:convert';

import 'book_source_models.dart';

/// 平台只显示可识别的来源标记，未知时保留标签而不以书源名称代替。
({String platform, String tags}) onlineBookPlatformAndTags(String kind) {
  final parts = kind.trim().split(RegExp(r'\s+'));
  const platforms = {
    'qidian': '起点中文网',
    'fanqie': '番茄小说',
    'jjwxc': '晋江文学城',
    'po18': 'PO18',
    'popo': 'POPO',
    'hbooker': '刺猬猫阅读',
    'haitang': '海棠',
    'myrics': '米国度',
    'hotpub': '河图文化',
    'zongheng': '纵横中文网',
  };
  final platform = platforms[parts.first.toLowerCase()];
  return (
    platform: platform ?? '',
    tags: platform == null ? kind.trim() : parts.skip(1).join(' '),
  );
}

/// 书源声明的一个发现分类。
class BookDiscoverCategory {
  const BookDiscoverCategory(this.title, this.url, {this.options = const {}});

  final String title;
  final String url;
  final Map<String, Object?> options;

  String get key => '$title|$url|${jsonEncode(options)}';
}

/// 筛选选项只携带书源声明的参数，不在本地过滤分页结果。
class BookDiscoverFilterOption {
  const BookDiscoverFilterOption(this.title, this.parameters);
  final String title;
  final Map<String, String> parameters;
}

class BookDiscoverFilterGroup {
  const BookDiscoverFilterGroup(this.name, this.options);
  final String name;
  final List<BookDiscoverFilterOption> options;
}

class BookDiscoverFilter {
  const BookDiscoverFilter(this.base, this.groups);
  final BookDiscoverCategory base;
  final List<BookDiscoverFilterGroup> groups;

  Map<String, String> get defaults => {
    for (final group in groups) group.name: group.options.first.title,
  };

  BookDiscoverCategory category(Map<String, String> selection) {
    final uri = Uri.parse(base.url);
    final parameters = Map<String, String>.from(uri.queryParameters);
    for (final group in groups) {
      for (final option in group.options) {
        for (final key in option.parameters.keys) {
          parameters.remove(key);
        }
      }
      final option =
          group.options
              .where((item) => item.title == selection[group.name])
              .firstOrNull ??
          group.options.first;
      parameters.addAll(option.parameters);
    }
    final title = groups
        .where((group) => selection[group.name] != group.options.first.title)
        .map((group) => selection[group.name])
        .whereType<String>()
        .join('·');
    return BookDiscoverCategory(
      title.isEmpty ? '筛选结果' : title,
      uri
          .replace(queryParameters: parameters)
          .toString()
          .replaceAll('%7B%7Bpage%7D%7D', '{{page}}'),
      options: base.options,
    );
  }
}

/// 参考书源中的 groups 脚本声明；旧逐行书源按查询参数组合筛选。
BookDiscoverFilter? parseDiscoverFilter(
  String raw,
  List<BookDiscoverCategory> categories, {
  List<String> kinds = const [],
}) {
  final scriptGroups = RegExp(r'var\s+groups\s*=\s*(\[[\s\S]*?\])\s*;')
      .firstMatch(raw)
      ?.group(1);
  if (scriptGroups != null) {
    try {
      final decoded = jsonDecode(scriptGroups) as List;
      final prefix = RegExp(r"""return\s*'([^']*)'\s*\+\s*parts\.join""")
          .firstMatch(raw)
          ?.group(1);
      if (prefix != null) {
        final fixed = <String, String>{};
        for (final extra in RegExp(
          r"""parts\.push\('([^']*)'\)""",
        ).allMatches(raw)) {
          final value = extra.group(1)!;
          final index = value.indexOf('=');
          if (index > 0) {
            fixed[value.substring(0, index)] = value.substring(index + 1);
          }
        }
        final groups = <BookDiscoverFilterGroup>[];
        for (final group in decoded) {
          if (group is! List || group.length < 2 || group[1] is! List) continue;
          final rows = group[1] as List;
          final name = '${group[0]}';
          final options = <BookDiscoverFilterOption>[];
          if (name != '排序') {
            options.add(const BookDiscoverFilterOption('全部', {}));
          }
          for (final row in rows) {
            if (row is! List || row.length < 2 || row[1] is! Map) continue;
            final values = {
              for (final entry in (row[1] as Map).entries)
                '${entry.key}': '${entry.value}',
            };
            if (name != '排序') values.remove('sort');
            options.add(BookDiscoverFilterOption('${row[0]}', values));
          }
          if (options.isNotEmpty) {
            groups.add(BookDiscoverFilterGroup(name, options));
          }
        }
        final sorts =
            RegExp(
                  r"""\{\s*label\s*:\s*['"]([^'"]+)['"]\s*,\s*value\s*:\s*['"]([^'"]*)['"]\s*\}""",
                )
                .allMatches(raw)
                .map(
                  (match) => BookDiscoverFilterOption(match.group(1)!, {
                    'sort': match.group(2)!,
                  }),
                )
                .toList();
        if (sorts.isNotEmpty &&
            groups.isNotEmpty &&
            groups.first.name == '排序') {
          groups[0] = BookDiscoverFilterGroup('排序', sorts);
        }
        final base = BookDiscoverCategory(
          '筛选结果',
          '$prefix${fixed.entries.map((item) => '${item.key}=${item.value}').join('&')}',
        );
        return BookDiscoverFilter(base, groups);
      }
    } on FormatException {
      // 不是纯 JSON 声明时继续从已经求值的发现分类中提取。
    }
  }
  if (categories.isEmpty) return null;
  const dimensions = {
    'sort': '排序',
    'platform': '平台',
    'category': '分类',
    'tag': '标签',
  };
  final values = {
    for (final key in dimensions.keys) key: <BookDiscoverFilterOption>[],
  };
  for (final category in categories) {
    final query =
        Uri.tryParse(category.url)?.queryParameters ?? const <String, String>{};
    final filters = query.keys
        .where((key) => dimensions.containsKey(key) && key != 'sort')
        .toList();
    final keys = filters.isEmpty ? ['sort'] : filters;
    for (final key in keys) {
      final value = query[key];
      if (value == null ||
          value.isEmpty ||
          values[key]!.any((item) => item.parameters[key] == value)) {
        continue;
      }
      values[key]!.add(BookDiscoverFilterOption(category.title, {key: value}));
    }
  }
  if (values.values.every((options) => options.isEmpty)) return null;
  // 列表字段同时提供分类与标签时，为旧来源补充当前可用选项。
  for (final kind in kinds) {
    final parts = kind.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 ||
        values['platform']!.every(
          (item) => item.parameters['platform'] != parts.first,
        )) {
      continue;
    }
    for (final (key, rawValue) in [
      ('category', parts[1]),
      ('tag', parts.skip(2).join(',')),
    ]) {
      for (final value in rawValue.split(RegExp('[,，]'))) {
        if (value.isNotEmpty &&
            !values[key]!.any((item) => item.parameters[key] == value)) {
          values[key]!.add(BookDiscoverFilterOption(value, {key: value}));
        }
      }
    }
  }
  return BookDiscoverFilter(categories.first, [
    for (final entry in dimensions.entries)
      BookDiscoverFilterGroup(entry.value, [
        if (entry.key != 'sort' || values[entry.key]!.isEmpty)
          const BookDiscoverFilterOption('全部', {}),
        ...values[entry.key]!,
      ]),
  ]);
}

/// 兼容 JSON 分类与 Legado 的「名称::地址」列表。
List<BookDiscoverCategory> parseDiscoverCategories(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  final result = <BookDiscoverCategory>[];
  void add(String title, String url) {
    final request = splitBookSourceUrlOptions(url.trim());
    if (title.trim().isEmpty || request.url.isEmpty) return;
    final category = BookDiscoverCategory(
      title.trim(),
      request.url,
      options: request.options,
    );
    if (!result.any((item) => item.key == category.key)) result.add(category);
  }

  if (text.startsWith('[') || text.startsWith('{')) {
    try {
      final json = jsonDecode(text);
      final items = json is List ? json : [json];
      for (final item in items) {
        if (item is Map) {
          add('${item['title'] ?? item['name'] ?? ''}', '${item['url'] ?? ''}');
        }
      }
      return result;
    } on FormatException {
      // 旧书源可能给整段文本增加方括号，继续按逐行格式解析。
    }
  }
  for (final line in text.split(RegExp(r'[\r\n]+|&&'))) {
    final value = line.trim();
    if (value.startsWith('#') || value.startsWith('//')) {
      continue;
    }
    final separator = value.indexOf('::');
    if (separator > 0) {
      add(value.substring(0, separator), value.substring(separator + 2));
    }
  }
  if (result.isEmpty && (text.startsWith('http') || text.startsWith('/'))) {
    add('发现', text);
  }
  return result;
}
