import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'book_source_models.dart';

/// 图片 data URL 也可能带动作选项，不能使用正文 data URL 的拆分规则。
({String url, Map<String, Object?> options}) onlineReviewImageRequest(
  String src,
) {
  for (final separator in RegExp(r',\s*(?=\{)').allMatches(src)) {
    try {
      final value = jsonDecode(src.substring(separator.end));
      if (value is Map<String, dynamic>) {
        return (url: src.substring(0, separator.start), options: value);
      }
    } on FormatException {
      // 无选项的 data 图片或含逗号地址仍沿用原值。
    }
  }
  return splitBookSourceUrlOptions(src);
}

/// 段评动作随正文保存来源图片和脚本，不依赖当前页码或易变的列表序号。
class OnlineReviewAction {
  const OnlineReviewAction({required this.src, required this.script});

  final String src;
  final String script;

  String get href =>
      'reader-review:${Uri.encodeComponent(jsonEncode({'src': src, 'script': script}))}';

  static OnlineReviewAction? fromHref(String href) {
    if (!href.startsWith('reader-review:')) return null;
    try {
      final value = jsonDecode(Uri.decodeComponent(href.substring(14)));
      if (value is! Map ||
          value['src'] is! String ||
          value['script'] is! String) {
        return null;
      }
      return OnlineReviewAction(
        src: value['src'] as String,
        script: value['script'] as String,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Legado 图片选项中的动作只在在线阅读点击时执行。
/// 原始缓存和下载 EPUB 不写入本地动作协议。
String prepareOnlineReviewHtml(String html) {
  if (!html.toLowerCase().contains('<img')) return html;
  final fragment = html_parser.parseFragment(html);
  var changed = false;
  for (final image in fragment.querySelectorAll('img')) {
    final src = image.attributes['src'] ?? '';
    final request = onlineReviewImageRequest(src);
    final script =
        [
              request.options['pclick'],
              request.options['click'],
              image.attributes['data-legado-pclick'],
              image.attributes['data-legado-click'],
              image.attributes['click'],
            ]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (script.isEmpty) continue;
    changed = true;
    final bubble = RegExp(
      r'^dp:(\d+)',
      caseSensitive: false,
    ).firstMatch(request.url);
    final count = bubble?.group(1) ?? image.attributes['alt'] ?? '';
    final badge = Element.tag('a')
      ..attributes['href'] = OnlineReviewAction(src: src, script: script).href
      ..attributes['data-reader-action'] = 'true'
      ..attributes['style'] =
          'font-size:0.75em;text-indent:0;color:inherit;'
          'text-decoration:none;'
      ..text = count.isEmpty ? '〔段评〕' : '〔$count〕';
    image.replaceWith(badge);
  }
  return changed ? fragment.outerHtml : html;
}

/// 书源 showBrowser 的展示参数，复用源请求头和登录 Cookie。
class OnlineReviewPage {
  const OnlineReviewPage({
    required this.url,
    this.html = '',
    this.preloadJs = '',
    this.config = '',
    this.headers = const {},
  });

  final String url;
  final String html;
  final String preloadJs;
  final String config;
  final Map<String, String> headers;
}
