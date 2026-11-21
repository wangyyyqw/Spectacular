import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'book_source_models.dart';

/// Legado 的图片 src 会直接拼接 JSON，先保护内层引号再交给 HTML 解析器。
String normalizeOnlineImageOptions(String html) {
  final starts = RegExp(
    r'''<img\b[^>]*?\bsrc\s*=\s*(["'])''',
    caseSensitive: false,
  );
  final output = StringBuffer();
  var copied = 0;
  for (final match in starts.allMatches(html)) {
    if (match.start < copied) continue;
    final quote = match.group(1)!;
    final firstQuote = html.indexOf(quote, match.end);
    final suffix = RegExp(r',\s*(?=\{)').firstMatch(html.substring(match.end));
    if (firstQuote < 0 ||
        suffix == null ||
        match.end + suffix.start >= firstQuote) {
      continue;
    }
    final start = match.end + suffix.end;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < html.length; index++) {
      final char = html[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') inString = true;
      if (char == '{') depth++;
      if (char != '}') continue;
      if (--depth != 0) continue;
      final end = index + 1;
      if (end >= html.length || html[end] != quote) break;
      final raw = html.substring(match.end, end);
      if (onlineReviewImageRequest(raw).options.isEmpty) break;
      final escapedValue = raw
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
      output.write(html.substring(copied, match.end));
      output.write(escapedValue);
      copied = end;
      break;
    }
  }
  output.write(html.substring(copied));
  return output.toString();
}

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
  final fragment = html_parser.parseFragment(normalizeOnlineImageOptions(html));
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
    var count = bubble?.group(1) ?? '';
    if (count.isEmpty && request.url.startsWith('data:image/svg+xml;base64,')) {
      try {
        final svg = utf8.decode(base64Decode(request.url.split(',').last));
        count =
            RegExp(r'<text\b[^>]*>\s*(\d+)\s*</text>')
                .firstMatch(svg)
                ?.group(1) ??
            '';
      } on FormatException {
        // 无法提取数字时仍提供段评入口。
      }
    }
    if (count.isEmpty) count = image.attributes['alt'] ?? '';
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

/// 只适配已声明 sort 参数及加载状态的段评页，切换后从接口重新分页。
String prepareOnlineReviewPage(String html) {
  const query = '"&sort=1&api_key="';
  const state = 'var offset="0",pageSize=';
  const start = 'more.onclick=load;';
  if (!html.contains(query) ||
      !html.contains(state) ||
      !html.contains(start) ||
      !html.contains('async function load()')) {
    return html;
  }
  final controls = '''
var sorting=document.createElement("div");
sorting.setAttribute("aria-label","段评排序");
sorting.setAttribute("role","group");
sorting.innerHTML='<button type="button" data-sort="1" aria-pressed="true">热度</button><button type="button" data-sort="0" aria-pressed="false">最新</button>';
sorting.style.cssText="display:flex;gap:2px;margin-left:auto;padding:3px;border-radius:20px;background:rgba(128,128,128,.09);flex-shrink:0";
var buttons=sorting.querySelectorAll("button");
function styleSorting(){for(var i=0;i<buttons.length;i++){
 var active=Number(buttons[i].dataset.sort)===reviewSort;
 buttons[i].setAttribute("aria-pressed",String(active));
 buttons[i].style.cssText="min-height:30px;min-width:48px;padding:0 10px;border:0;border-radius:17px;font-size:13px;font-weight:"+(active?"600":"500")+";color:inherit;opacity:"+(active?"1":".6")+";background:"+(active?"var(--bg,#fff)":"transparent")+";box-shadow:"+(active?"0 1px 3px rgba(0,0,0,.05)":"none");
}}
function placeSorting(){var bar=document.querySelector(".fq-tab-bar");
 if(bar){bar.style.alignItems="center";bar.style.gap="16px";bar.appendChild(sorting);return true;}
 return false;
}
if(!placeSorting()){var watchSorting=new MutationObserver(function(){if(placeSorting())watchSorting.disconnect();});
watchSorting.observe(document.body,{childList:true,subtree:true});}
styleSorting();
sorting.onclick=function(event){
 var button=event.target.closest("button[data-sort]");
 if(!button||loading||Number(button.dataset.sort)===reviewSort)return;
 reviewSort=Number(button.dataset.sort);offset="0";ended=false;loaded=0;total=0;
 styleSorting();
 list.innerHTML="";setCount();load();
};
''';
  return html
      .replaceFirst(query, '"&sort="+reviewSort+"&api_key="')
      .replaceFirst(state, 'var reviewSort=1;var offset="0",pageSize=')
      .replaceFirst(start, '$controls$start');
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
