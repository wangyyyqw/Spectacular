import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// 清理在线词典返回的 HTML：保留排版和图片，不执行脚本、不提供本机文件访问。
String buildRuleDictionaryHtml(
  String source,
  Uri baseUri, {
  bool dark = false,
}) {
  final document = html.parse(source);
  for (final element in document.querySelectorAll(
    'script,iframe,frame,frameset,object,embed,form,base,meta',
  )) {
    element.remove();
  }
  for (final element in document.querySelectorAll('*')) {
    element.attributes.removeWhere((key, _) {
      final name = key.toString().toLowerCase();
      return name.startsWith('on') || name == 'srcdoc' || name == 'srcset';
    });
    for (final attribute in ['src', 'href', 'poster', 'xlink:href']) {
      final value = element.attributes[attribute];
      if (value == null) continue;
      final normalized = value.trim().toLowerCase();
      if (normalized.startsWith('javascript:') ||
          normalized.startsWith('file:') ||
          normalized.startsWith('content:')) {
        element.attributes.remove(attribute);
      }
    }
  }
  final head = document.head!;
  head.children.insert(
    0,
    dom.Element.tag('base')..attributes['href'] = baseUri.toString(),
  );
  head.children.add(dom.Element.tag('meta')..attributes['charset'] = 'utf-8');
  head.children.add(
    dom.Element.tag('meta')
      ..attributes['name'] = 'viewport'
      ..attributes['content'] = 'width=device-width,initial-scale=1',
  );
  head.children.add(
    dom.Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] =
          "default-src 'none'; img-src http: https: data:; "
          "style-src 'unsafe-inline' http: https:; font-src http: https: data:; "
          "media-src http: https: data:; base-uri 'self'; form-action 'none'; "
          "frame-ancestors 'none'",
  );
  head.children.add(
    dom.Element.tag('style')
      ..text =
          '''
body { margin: 12px; font: 16px/1.65 sans-serif; overflow-wrap: anywhere;
  color: ${dark ? '#e8e6e0' : '#25231f'}; background: ${dark ? '#20201e' : '#faf9f6'}; }
img, video, audio, table { max-width: 100%; }
img { height: auto; }
pre { white-space: pre-wrap; }
a { color: ${dark ? '#8ab4f8' : '#2155aa'}; }
''',
  );
  return '<!doctype html>${document.documentElement!.outerHtml}';
}
