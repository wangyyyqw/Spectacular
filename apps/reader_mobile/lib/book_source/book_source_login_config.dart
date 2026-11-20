import 'dart:convert';

import 'book_source_models.dart';

/// 书源声明的一个登录输入项，名称保持原值以供脚本读取。
class BookSourceLoginField {
  const BookSourceLoginField(this.name, this.type, this.defaultValue);

  final String name;
  final String type;
  final String defaultValue;
  bool get secret =>
      type == 'password' ||
      RegExp(r'密码|密钥|秘钥|token|key|secret', caseSensitive: false).hasMatch(name);
}

/// 参考源项目的 loginUi 输入约定，按钮和说明不作为凭据保存。
List<BookSourceLoginField> bookSourceLoginFields(BookSource source) {
  try {
    final raw = jsonDecode(source.loginUi);
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
          }.contains(type) ||
          !names.add(name)) {
        continue;
      }
      fields.add(
        BookSourceLoginField(
          name,
          type,
          '${item['default'] ?? item['value'] ?? ''}',
        ),
      );
    }
    return fields;
  } on FormatException {
    return const [];
  }
}

/// 只从脚本声明识别账号密码接口，不按书名或域名补写登录端点。
String bookSourceAccountEndpoint(BookSource source) {
  if (source.loginUrl.trim().startsWith('http')) return '';
  return RegExp(r'''['"]([^'"]*reader-auth/login[^'"]*)['"]''')
          .firstMatch(source.loginUrl)
          ?.group(1) ??
      '';
}
