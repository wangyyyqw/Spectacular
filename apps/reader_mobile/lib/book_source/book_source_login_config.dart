import 'dart:convert';

import 'book_source_models.dart';
import 'book_source_script.dart';

/// 书源声明的一个登录输入项，名称保持原值以供脚本读取。
class BookSourceLoginField {
  const BookSourceLoginField(
    this.name,
    this.type,
    this.defaultValue, {
    this.title = '',
    this.action = '',
    this.options = const [],
    this.basisPercent = 1,
    this.wrapBefore = false,
  });

  final String name;
  final String type;
  final String defaultValue;
  final String title;
  final String action;
  final List<String> options;
  final double basisPercent;
  final bool wrapBefore;
  String get label => title.isEmpty ? name : title;
  bool get input => type != 'button';
  bool get secret =>
      type == 'password' ||
      RegExp(r'密码|密钥|秘钥|token|key|secret', caseSensitive: false).hasMatch(name);
}

/// 保留动态登录表单的按钮、选择项和布局声明。
List<BookSourceLoginField> bookSourceLoginRows(
  BookSource source, {
  QuickJsBookSourceScriptSession? script,
}) {
  QuickJsBookSourceScriptSession? owned;
  try {
    var text = source.loginUi.trim();
    if (text.startsWith('@js:') || text.startsWith('<js>')) {
      final session =
          script ??
          (owned = QuickJsBookSourceScriptSession(
            jsLib: source.jsLib,
            sourceKey: source.sourceUrl,
          ));
      text = session.evaluate(
        '${bookSourceLoginScript(source)}\n${unwrapBookSourceScript(text)}',
        result: '',
        variables: {
          'baseUrl': source.baseUrl,
          '_resultJson': jsonEncode(session.loginInfo),
        },
        resolveString: (_) => '',
        resolveList: (_) => const [],
      );
    }
    final raw = jsonDecode(text);
    final items = raw is List
        ? raw
        : raw is Map
        ? raw['fields'] ?? raw['items'] ?? [raw]
        : const <Object?>[];
    if (items is! List) return const [];
    final fields = <BookSourceLoginField>[];
    final names = <String>{};
    for (final item in items.whereType<Map<Object?, Object?>>()) {
      final name =
          '${item['name'] ?? item['label'] ?? item['title'] ?? item['key'] ?? ''}'
              .trim();
      final type = '${item['type'] ?? item['inputType'] ?? ''}'.toLowerCase();
      if (name.isEmpty ||
          !const {
            'text',
            'password',
            'email',
            'number',
            'tel',
            'phone',
            'button',
            'select',
            'toggle',
          }.contains(type) ||
          !names.add(name)) {
        continue;
      }
      final options = (item['chars'] as List? ?? const [])
          .where((value) => value != null)
          .map((value) => '$value')
          .toList();
      final style = item['style'] is Map
          ? item['style'] as Map
          : const <String, Object?>{};
      var title = '${item['viewName'] ?? ''}';
      if (title.startsWith("'") && title.endsWith("'")) {
        title = title.substring(1, title.length - 1);
      } else if (title.isNotEmpty && script != null) {
        title = script.evaluate(
          '${bookSourceLoginScript(source)}\n$title',
          result: '',
          variables: {'_resultJson': jsonEncode(script.loginInfo)},
          resolveString: (_) => '',
          resolveList: (_) => [],
        );
      }
      fields.add(
        BookSourceLoginField(
          name,
          type,
          '${item['default'] ?? item['value'] ?? (options.isEmpty ? '' : options.first)}',
          title: title,
          action: '${item['action'] ?? ''}',
          options: options,
          basisPercent:
              double.tryParse('${style['layout_flexBasisPercent'] ?? 1}')
                  ?.clamp(0.1, 1)
                  .toDouble() ??
              1,
          wrapBefore: style['layout_wrapBefore'] == true,
        ),
      );
    }
    return fields;
  } on FormatException {
    return const [];
  } finally {
    owned?.dispose();
  }
}

/// 输入值按书源原名保存，按钮不作为凭据。
List<BookSourceLoginField> bookSourceLoginFields(BookSource source) =>
    bookSourceLoginRows(source).where((row) => row.input).toList();

String unwrapBookSourceScript(String raw) {
  var code = raw.trim();
  if (code.startsWith('@js:')) code = code.substring(4);
  if (code.startsWith('<js>')) {
    code = code.substring(4).replaceFirst(RegExp(r'</js>\s*$'), '');
  }
  return code;
}

String bookSourceLoginScript(BookSource source) =>
    source.loginUrl.trim().startsWith('http')
    ? ''
    : unwrapBookSourceScript(source.loginUrl);

/// 只从脚本声明识别账号密码接口，不按书名或域名补写登录端点。
String bookSourceAccountEndpoint(BookSource source) {
  if (source.loginUrl.trim().startsWith('http')) return '';
  return RegExp(r'''['"]([^'"]*reader-auth/login[^'"]*)['"]''')
          .firstMatch(source.loginUrl)
          ?.group(1) ??
      '';
}
