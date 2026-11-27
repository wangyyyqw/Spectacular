import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:html/parser.dart' as html;

import 'local_dictionary_store.dart';

bool isLocalDictionaryUrl(Uri uri, Uri base) =>
    uri.scheme == base.scheme &&
    uri.host == base.host &&
    uri.port == base.port &&
    uri.path.startsWith(base.path);

Uri? dictionaryResourceUri(Uri base, String reference, {String parent = ''}) {
  final value = reference
      .trim()
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/+'), '');
  // 不能把协议相对地址误认为词库资源。
  if (reference.trim().startsWith('//')) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final resolved = base.resolve(parent).resolveUri(uri);
  if (!isLocalDictionaryUrl(resolved, base) ||
      resolved.pathSegments.any(
        (part) => part == '..' || part.contains('\\'),
      )) {
    return null;
  }
  return resolved;
}

String rewriteDictionaryCss(String css, Uri base, {String parent = ''}) {
  final imports = css.replaceAllMapped(
    RegExp(r'''@import\s+["']([^"']+)["']''', caseSensitive: false),
    (match) =>
        '@import url("${dictionaryResourceUri(base, match[1]!, parent: parent) ?? ''}")',
  );
  return imports.replaceAllMapped(
    RegExp(
      r'''url\(\s*(["']?)(.*?)\1\s*\)''',
      caseSensitive: false,
      dotAll: true,
    ),
    (match) {
      final value = match[2]!.trim();
      if (value.startsWith('data:')) return match[0]!;
      final uri = Uri.tryParse(value);
      final resolved = uri != null && isLocalDictionaryUrl(uri, base)
          ? uri
          : dictionaryResourceUri(base, value, parent: parent);
      return 'url("${resolved ?? ''}")';
    },
  );
}

String buildLocalDictionaryHtml(String source, Uri base, {bool dark = false}) {
  final document = html.parse(source);
  for (final element in document.querySelectorAll(
    'script,iframe,frame,frameset,object,embed,form,base,meta',
  )) {
    element.remove();
  }
  for (final element in document.querySelectorAll('*')) {
    element.attributes.removeWhere(
      (key, _) =>
          key.toString().toLowerCase().startsWith('on') ||
          key == 'srcdoc' ||
          key == 'srcset',
    );
    for (final attribute in ['src', 'href', 'poster', 'xlink:href']) {
      final value = element.attributes[attribute];
      if (value == null || value.startsWith('#')) continue;
      if (attribute == 'href' &&
          RegExp(r'^(entry|sound)://', caseSensitive: false).hasMatch(value)) {
        continue;
      }
      if (attribute == 'src' && value.startsWith('data:')) continue;
      final uri = dictionaryResourceUri(base, value);
      if (uri == null) {
        element.attributes.remove(attribute);
      } else {
        element.attributes[attribute] = uri.toString();
      }
    }
    final style = element.attributes['style'];
    if (style != null) {
      element.attributes['style'] = rewriteDictionaryCss(style, base);
    }
    if (element.localName == 'style') {
      element.text = rewriteDictionaryCss(element.text, base);
    }
  }
  document.head!.append(
    html.parseFragment('''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root {color-scheme:${dark ? 'dark' : 'light'};}
body, body * {box-sizing:border-box;font-family:sans-serif !important;
font-size:16px !important;line-height:1.6 !important;}
body {margin:0;padding:16px 16px 20px;overflow-x:hidden;overflow-y:auto;
overflow-wrap:anywhere;color:${dark ? '#e8e6e0' : '#25231f'};background:transparent;}
img,video,audio {max-width:100%;height:auto;} table {max-width:100%;}
pre {white-space:pre-wrap;overflow-wrap:anywhere;}
a {color:${dark ? '#8ab4f8' : '#2155aa'};}
</style>'''),
  );
  return '<!doctype html>${document.documentElement!.outerHtml}';
}

/// 仅绑定回环地址，以随机路径隔离会话；词库网页不能访问网络或本机文件。
class LocalDictionaryServer {
  LocalDictionaryServer._(this._server, this.session, this.baseUri);
  final HttpServer _server;
  final LocalDictionarySession session;
  final Uri baseUri;
  late final String _html;
  Future<void> _requests = Future<void>.value();
  bool _closed = false;

  Uri get pageUri => baseUri.resolve('index.html');

  static Future<LocalDictionaryServer> start(
    LocalDictionarySession session,
    String definition, {
    bool dark = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = base64Url.encode(
      List<int>.generate(24, (_) => Random.secure().nextInt(256)),
    );
    final base = Uri.parse('http://127.0.0.1:${server.port}/$token/');
    final result = LocalDictionaryServer._(server, session, base);
    result._html = buildLocalDictionaryHtml(definition, base, dark: dark);
    server.listen((request) {
      // 分卷初始化和关闭与资源请求串行，避免重复打开 MDD 或关闭中继续读文件。
      result._requests = result._requests.then((_) => result._serve(request));
    });
    return result;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set(
        'Content-Security-Policy',
        "default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
            "font-src 'self' data:; media-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      );
      final uri = baseUri.resolveUri(request.uri);
      if (_closed ||
          !isLocalDictionaryUrl(uri, baseUri) ||
          !['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final path = uri.pathSegments.skip(1).join('/');
      if (path == 'index.html') {
        response.headers.contentType = ContentType.html;
        if (request.method != 'HEAD') response.write(_html);
        return;
      }
      final data = await session.resource(path);
      if (data == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final ext = path.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'css' => 'text/css',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'svg' => 'image/svg+xml',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        'mp4' || 'm4a' => 'audio/mp4',
        'woff' => 'font/woff',
        'woff2' => 'font/woff2',
        'ttf' => 'font/ttf',
        'otf' => 'font/otf',
        _ => 'application/octet-stream',
      };
      response.headers.set('Content-Type', mime);
      if (request.method != 'HEAD') {
        response.add(
          ext == 'css'
              ? utf8.encode(
                  rewriteDictionaryCss(
                    utf8.decode(data, allowMalformed: true),
                    baseUri,
                    parent: path,
                  ),
                )
              : data,
        );
      }
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      try {
        await response.close();
      } on HttpException {
        // 关闭抽屉或取消加载后，浏览器可能已经断开当前资源请求。
      } on SocketException {
        // 会话关闭不影响后续清理和词库文件释放。
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    await _server.close(force: true);
    await _requests;
  }
}
