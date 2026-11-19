import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 书籍详情或搜索结果中的在线书籍。
class OnlineBook {
  const OnlineBook({
    required this.sourceId,
    required this.sourceName,
    required this.name,
    required this.author,
    required this.bookUrl,
    this.tocUrl = '',
    this.coverUrl = '',
    this.intro = '',
    this.kind = '',
    this.wordCount = '',
    this.lastChapter = '',
    this.bookOptions = const <String, Object?>{},
    this.tocOptions = const <String, Object?>{},
  });

  /// 来源标识。
  final String sourceId;

  /// 来源显示名称。
  final String sourceName;

  /// 书名。
  final String name;

  /// 作者。
  final String author;

  /// 详情页地址。
  final String bookUrl;

  /// 目录页地址；为空时使用详情页。
  final String tocUrl;

  /// 封面地址。
  final String coverUrl;

  /// 简介。
  final String intro;

  /// 分类或状态。
  final String kind;

  /// 字数描述。
  final String wordCount;

  /// 最新章节。
  final String lastChapter;

  /// 详情页请求参数。
  final Map<String, Object?> bookOptions;

  /// 目录页请求参数。
  final Map<String, Object?> tocOptions;

  OnlineBook copyWith({
    String? sourceId,
    String? sourceName,
    String? name,
    String? author,
    String? bookUrl,
    String? tocUrl,
    String? coverUrl,
    String? intro,
    String? kind,
    String? wordCount,
    String? lastChapter,
    Map<String, Object?>? bookOptions,
    Map<String, Object?>? tocOptions,
  }) {
    return OnlineBook(
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      name: name ?? this.name,
      author: author ?? this.author,
      bookUrl: bookUrl ?? this.bookUrl,
      tocUrl: tocUrl ?? this.tocUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      kind: kind ?? this.kind,
      wordCount: wordCount ?? this.wordCount,
      lastChapter: lastChapter ?? this.lastChapter,
      bookOptions: bookOptions ?? this.bookOptions,
      tocOptions: tocOptions ?? this.tocOptions,
    );
  }
}

/// 在线目录章节。
class OnlineChapter {
  const OnlineChapter({
    required this.index,
    required this.title,
    required this.url,
    this.volume = '',
    this.updateTime = '',
    this.requestOptions = const <String, Object?>{},
  });

  /// 从 0 开始的章节序号。
  final int index;

  /// 章节标题。
  final String title;

  /// 正文地址。
  final String url;

  /// 分卷标题；当前只用于去重和展示。
  final String volume;

  /// 更新时间描述。
  final String updateTime;

  /// 正文请求参数（如逐章 headers）。
  final Map<String, Object?> requestOptions;
}

/// 搜索结果字段规则。
class BookListRule {
  const BookListRule({
    this.bookList = '',
    this.name = '',
    this.author = '',
    this.kind = '',
    this.wordCount = '',
    this.lastChapter = '',
    this.intro = '',
    this.coverUrl = '',
    this.bookUrl = '',
  });

  factory BookListRule.fromJson(Map<String, Object?> json) {
    return BookListRule(
      bookList: _string(json, 'bookList'),
      name: _string(json, 'name'),
      author: _string(json, 'author'),
      kind: _string(json, 'kind'),
      wordCount: _string(json, 'wordCount'),
      lastChapter: _string(json, 'lastChapter'),
      intro: _string(json, 'intro'),
      coverUrl: _string(json, 'coverUrl'),
      bookUrl: _string(json, 'bookUrl'),
    );
  }

  final String bookList;
  final String name;
  final String author;
  final String kind;
  final String wordCount;
  final String lastChapter;
  final String intro;
  final String coverUrl;
  final String bookUrl;
}

/// 详情页字段规则。
class BookInfoRule {
  const BookInfoRule({
    this.name = '',
    this.author = '',
    this.kind = '',
    this.wordCount = '',
    this.lastChapter = '',
    this.intro = '',
    this.coverUrl = '',
    this.tocUrl = '',
    this.init = '',
  });

  factory BookInfoRule.fromJson(Map<String, Object?> json) {
    return BookInfoRule(
      name: _string(json, 'name'),
      author: _string(json, 'author'),
      kind: _string(json, 'kind'),
      wordCount: _string(json, 'wordCount'),
      lastChapter: _string(json, 'lastChapter'),
      intro: _string(json, 'intro'),
      coverUrl: _string(json, 'coverUrl'),
      tocUrl: _string(json, 'tocUrl'),
      init: _string(json, 'init'),
    );
  }

  final String name;
  final String author;
  final String kind;
  final String wordCount;
  final String lastChapter;
  final String intro;
  final String coverUrl;
  final String tocUrl;
  final String init;
}

/// 目录字段规则。
class TocRule {
  const TocRule({
    this.chapterList = '',
    this.chapterName = '',
    this.chapterUrl = '',
    this.updateTime = '',
    this.nextTocUrl = '',
    this.isVolume = '',
  });

  factory TocRule.fromJson(Map<String, Object?> json) {
    return TocRule(
      chapterList: _string(json, 'chapterList'),
      chapterName: _string(json, 'chapterName'),
      chapterUrl: _string(json, 'chapterUrl'),
      updateTime: _string(json, 'updateTime'),
      nextTocUrl: _string(json, 'nextTocUrl'),
      isVolume: _string(json, 'isVolume'),
    );
  }

  final String chapterList;
  final String chapterName;
  final String chapterUrl;
  final String updateTime;
  final String nextTocUrl;
  final String isVolume;
}

/// 正文字段规则。
class ContentRule {
  const ContentRule({
    this.content = '',
    this.nextContentUrl = '',
    this.replaceRegex = '',
    this.sourceRegex = '',
  });

  factory ContentRule.fromJson(Map<String, Object?> json) {
    return ContentRule(
      content: _string(json, 'content'),
      nextContentUrl: _string(json, 'nextContentUrl'),
      replaceRegex: _string(json, 'replaceRegex'),
      sourceRegex: _string(json, 'sourceRegex'),
    );
  }

  final String content;
  final String nextContentUrl;
  final String replaceRegex;
  final String sourceRegex;
}

/// 单个 Legado/阅读书源。
///
/// [raw] 保留导入时的完整对象，未识别字段在重新保存时不会丢失。
class BookSource {
  const BookSource({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.searchUrl,
    this.searchOptions = const <String, Object?>{},
    required this.search,
    required this.bookInfo,
    required this.toc,
    required this.content,
    this.group = '',
    this.enabled = true,
    this.enabledExplore = false,
    this.type = 0,
    this.comment = '',
    this.header = '',
    this.loginUrl = '',
    this.loginUi = '',
    this.loginCheckJs = '',
    this.concurrentRate = '',
    this.respondTime = 60000,
    this.exploreUrl = '',
    this.jsLib = '',
    this.raw = const <String, Object?>{},
  });

  /// 从 Legado JSON 对象构造。
  factory BookSource.fromJson(Map<String, Object?> json) {
    final name = _firstString(json, const <String>[
      'bookSourceName',
      'sourceName',
      'name',
      'title',
    ]).ifBlank('未命名书源');
    final sourceUrl = _firstString(json, const <String>[
      'bookSourceUrl',
      'sourceUrl',
      'url',
    ]);
    final rawSearchUrl = _firstString(json, const <String>[
      'searchUrl',
      'searchURL',
      'search',
    ]);
    final explicitId = _firstString(json, const <String>[
      'reamicroSourceId',
      'bookSourceId',
      'id',
    ]);
    final type = _int(json['bookSourceType'] ?? json['type']);
    final search = BookListRule.fromJson(_ruleMap(json['ruleSearch']));
    final searchRequest = splitBookSourceUrlOptions(rawSearchUrl);
    final bookInfo = BookInfoRule.fromJson(_ruleMap(json['ruleBookInfo']));
    final toc = TocRule.fromJson(_ruleMap(json['ruleToc']));
    final content = ContentRule.fromJson(_ruleMap(json['ruleContent']));
    return BookSource(
      id: explicitId.isNotBlank
          ? explicitId
          : stableBookSourceId(sourceUrl.ifBlank(name)),
      name: name,
      sourceUrl: sourceUrl,
      group: _firstString(json, const <String>['bookSourceGroup', 'group']),
      enabled: _bool(json['enabled'], fallback: true),
      enabledExplore: _bool(json['enabledExplore']),
      type: type,
      comment: _firstString(json, const <String>[
        'bookSourceComment',
        'comment',
      ]),
      header: _rawJsonString(json['header'] ?? json['headers']),
      loginUrl: _firstString(json, const <String>['loginUrl', 'loginPage']),
      loginUi: _rawJsonString(json['loginUi'] ?? json['loginUI']),
      loginCheckJs: _firstString(json, const <String>[
        'loginCheckJs',
        'loginCheckJS',
      ]),
      concurrentRate: _firstString(json, const <String>[
        'concurrentRate',
        'rateLimit',
      ]),
      respondTime: _positiveInt(
        json['respondTime'] ?? json['timeout'],
        fallback: 60000,
      ),
      searchUrl: searchRequest.url,
      searchOptions: searchRequest.options,
      exploreUrl: _firstString(json, const <String>[
        'exploreUrl',
        'exploreURL',
        'discoverUrl',
      ]),
      jsLib: _rawJsonString(json['jsLib']),
      search: search,
      bookInfo: bookInfo,
      toc: toc,
      content: content,
      raw: Map<String, Object?>.unmodifiable(json),
    );
  }

  /// 稳定标识。
  final String id;

  /// 显示名称。
  final String name;

  /// 站点根地址。
  final String sourceUrl;

  /// 分组。
  final String group;

  /// 是否启用搜索。
  final bool enabled;

  /// 是否启用发现页；当前保留字段，后续再接入。
  final bool enabledExplore;

  /// Legado 书源类型；0 为文本。
  final int type;

  /// 备注。
  final String comment;

  /// 请求头 JSON。
  final String header;

  /// 登录地址与配置；当前只保存，不执行网页登录脚本。
  final String loginUrl;
  final String loginUi;
  final String loginCheckJs;

  /// 请求频率，格式为 `次数/毫秒` 或 `毫秒`。
  final String concurrentRate;

  /// 超时时间（毫秒）。
  final int respondTime;

  /// 搜索地址模板。
  final String searchUrl;

  /// 搜索地址后的 Legado 请求参数，例如 headers、method、body。
  final Map<String, Object?> searchOptions;

  /// 发现页地址；当前只保存。
  final String exploreUrl;

  /// 公共 JS 库；当前只保存。
  final String jsLib;

  /// 搜索、详情、目录与正文规则。
  final BookListRule search;
  final BookInfoRule bookInfo;
  final TocRule toc;
  final ContentRule content;

  /// 导入时的完整 JSON。
  final Map<String, Object?> raw;

  /// 是否具备最小可用搜索链路。
  bool get canSearch =>
      enabled &&
      searchUrl.isNotBlank &&
      sourceUrl.isNotBlank &&
      search.bookList.isNotBlank;

  /// 站点源地址，用于解析相对链接。
  String get baseUrl {
    final text = sourceUrl.trim();
    final match = RegExp(
      r'https?://[^\s#]+',
      caseSensitive: false,
    ).firstMatch(text);
    final candidate = match?.group(0) ?? text;
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return sourceUrl.trim();
    }
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  /// 创建启用状态或元信息变更后的副本。
  BookSource copyWith({
    String? id,
    String? name,
    String? sourceUrl,
    String? group,
    bool? enabled,
    bool? enabledExplore,
    int? type,
    String? comment,
    String? header,
    String? loginUrl,
    String? loginUi,
    String? loginCheckJs,
    String? concurrentRate,
    int? respondTime,
    String? searchUrl,
    Map<String, Object?>? searchOptions,
    String? exploreUrl,
    String? jsLib,
    BookListRule? search,
    BookInfoRule? bookInfo,
    TocRule? toc,
    ContentRule? content,
    Map<String, Object?>? raw,
  }) {
    return BookSource(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      group: group ?? this.group,
      enabled: enabled ?? this.enabled,
      enabledExplore: enabledExplore ?? this.enabledExplore,
      type: type ?? this.type,
      comment: comment ?? this.comment,
      header: header ?? this.header,
      loginUrl: loginUrl ?? this.loginUrl,
      loginUi: loginUi ?? this.loginUi,
      loginCheckJs: loginCheckJs ?? this.loginCheckJs,
      concurrentRate: concurrentRate ?? this.concurrentRate,
      respondTime: respondTime ?? this.respondTime,
      searchUrl: searchUrl ?? this.searchUrl,
      searchOptions: searchOptions ?? this.searchOptions,
      exploreUrl: exploreUrl ?? this.exploreUrl,
      jsLib: jsLib ?? this.jsLib,
      search: search ?? this.search,
      bookInfo: bookInfo ?? this.bookInfo,
      toc: toc ?? this.toc,
      content: content ?? this.content,
      raw: raw ?? this.raw,
    );
  }

  /// 转为持久化 JSON；启用状态写回原字段。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...raw,
      'bookSourceName': name,
      'bookSourceUrl': sourceUrl,
      'bookSourceGroup': group,
      'bookSourceType': type,
      'enabled': enabled,
      'enabledExplore': enabledExplore,
      'searchUrl': searchUrl,
      'exploreUrl': exploreUrl,
      'bookSourceId': id,
    };
  }
}

/// 书架书籍与在线书源的关联，用于后续更新章节。
class OnlineBookLink {
  const OnlineBookLink({
    required this.sourceId,
    required this.bookUrl,
    required this.name,
    required this.author,
    this.updatedAt,
  });

  factory OnlineBookLink.fromJson(Map<String, Object?> json) {
    return OnlineBookLink(
      sourceId: _string(json, 'sourceId'),
      bookUrl: _string(json, 'bookUrl'),
      name: _string(json, 'name'),
      author: _string(json, 'author'),
      updatedAt: DateTime.tryParse(_string(json, 'updatedAt')),
    );
  }

  final String sourceId;
  final String bookUrl;
  final String name;
  final String author;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'bookUrl': bookUrl,
    'name': name,
    'author': author,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };

  OnlineBookLink copyWith({DateTime? updatedAt}) => OnlineBookLink(
    sourceId: sourceId,
    bookUrl: bookUrl,
    name: name,
    author: author,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 在线书源错误；[message] 可直接展示给用户。
class BookSourceException implements Exception {
  const BookSourceException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  /// 网络超时、连接失败、限流或服务端 5xx 可安全重试。
  bool get isTransient {
    if (code == 'ONLINE_HTTP_TIMEOUT' ||
        code == 'ONLINE_HTTP_NETWORK' ||
        code == 'ONLINE_HTTP_CLIENT') {
      return true;
    }
    final status = statusCode;
    return status == 429 ||
        status == 500 ||
        status == 502 ||
        status == 503 ||
        status == 504;
  }

  @override
  String toString() => message;
}

/// 书源稳定标识：URL 或名称的 SHA-256 前 16 位。
String stableBookSourceId(String value) {
  final digest = sha256.convert(utf8.encode(value.trim().toLowerCase()));
  return 'online_${digest.toString().substring(0, 16)}';
}

/// 读取书源对象；字符串形式的内嵌 JSON 也接受。
Map<String, Object?> bookSourceRuleMap(Object? value) => _ruleMap(value);

String bookSourceJsonString(Object? value) => _rawJsonString(value);

Map<String, Object?> _ruleMap(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  if (value is String && value.trim().startsWith('{')) {
    final decoded = _tryDecodeObject(value);
    if (decoded != null) return decoded;
  }
  return const <String, Object?>{};
}

Map<String, Object?>? _tryDecodeObject(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    return null;
  }
  return null;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return '';
  return '$value'.trim();
}

String _firstString(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _string(json, key);
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

String _rawJsonString(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is Map || value is List) return jsonEncode(value);
  return '$value'.trim();
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = '$value'.trim().toLowerCase();
  if (text.isEmpty || text == 'null') return fallback;
  return text == 'true' || text == '1' || text == 'yes';
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value'.trim()) ?? 0;
}

int _positiveInt(Object? value, {required int fallback}) {
  final parsed = _int(value);
  return parsed > 0 ? parsed : fallback;
}

/// 拆分 Legado URL 后的 `,{...}` 请求参数，兼容逗号后的空格。
({String url, Map<String, Object?> options}) splitBookSourceUrlOptions(
  String raw,
) {
  final text = raw.trim();
  for (final separator in const <String>[',{', ', {']) {
    final index = text.indexOf(separator);
    if (index <= 0) continue;
    final candidate = text.substring(index + 1).trim();
    if (!candidate.startsWith('{') || !candidate.endsWith('}')) continue;
    return (
      url: text.substring(0, index).trim(),
      options: _tryDecodeObject(candidate) ?? const <String, Object?>{},
    );
  }
  return (url: text, options: const <String, Object?>{});
}

extension _BlankString on String {
  bool get isNotBlank => trim().isNotEmpty;

  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
