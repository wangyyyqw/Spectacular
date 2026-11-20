import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_source_models.dart';

/// 在线书源登录 Cookie 的本地存储。
///
/// Cookie 按域名共享，只写入应用私有目录，不写日志。HTTP 请求器在请求时
/// 自动携带匹配域名，书源脚本可通过 `java.getCookie(domain, name)` 读取。
class BookSourceCookieStore {
  BookSourceCookieStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  final Map<String, Map<String, String>> _cookies =
      <String, Map<String, String>>{};
  final Set<String> _loginDomains = <String>{};
  final Map<String, Map<String, String>> _loginInfo = {};
  final Map<String, String> _loginHeaders = {};
  final Map<String, String> _variables = {};

  Map<String, String> loginInfo(BookSource source) =>
      Map.of(_loginInfo[source.id] ?? const {});

  String loginHeader(BookSource source) => _loginHeaders[source.id] ?? '';
  String sourceVariable(BookSource source) => _variables[source.id] ?? '';

  Future<void> saveSourceLogin(
    BookSource source, {
    Map<String, String>? info,
    String? header,
    String? variable,
  }) async {
    await load();
    if (info != null) _loginInfo[source.id] = Map.of(info);
    if (header != null) _loginHeaders[source.id] = header;
    if (variable != null) _variables[source.id] = variable;
    await _persist();
  }

  Future<void>? _loading;
  Future<void> _writeQueue = Future<void>.value();
  bool _loaded = false;

  bool get loaded => _loaded;

  /// 读取 Cookie 文件；损坏或不可读时按空 Cookie 处理，不阻断书源请求。
  Future<void> load({bool refresh = false}) {
    if (_loaded && !refresh) return Future<void>.value();
    final pending = _loading;
    if (pending != null && !refresh) return pending;
    final future = _readFromDisk();
    _loading = future;
    return future.whenComplete(() {
      if (identical(_loading, future)) _loading = null;
    });
  }

  /// 返回请求地址可携带的 Cookie。
  Future<Map<String, String>> cookiesFor(BookSource source, Uri uri) async {
    await load();
    return _cookiesForHost(uri.host);
  }

  /// 读取指定域名下的 Cookie 值。
  String cookieValue(String domain, String name) {
    if (!_loaded) return '';
    final target = normalizeCookieDomain(domain);
    if (target.isEmpty || name.isEmpty) return '';
    final exact = _cookies[target]?[name];
    if (exact != null) return exact;
    for (final entry in _cookies.entries) {
      if (cookieDomainMatches(target, entry.key)) {
        final value = entry.value[name];
        if (value != null) return value;
      }
    }
    return '';
  }

  /// 读取指定域名的 Cookie 请求头。
  String cookieHeader(String domain) {
    if (!_loaded) return '';
    final target = normalizeCookieDomain(domain);
    if (target.isEmpty) return '';
    return _cookiesForHost(target).entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  /// 保存网页登录返回的 Cookie。
  Future<void> saveLoginCookies(
    String domain,
    Map<String, String> cookies,
  ) async {
    await load();
    final target = normalizeCookieDomain(domain);
    if (target.isEmpty) return;
    final jar = _cookies.putIfAbsent(target, () => <String, String>{});
    for (final entry in cookies.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (name.isEmpty) continue;
      if (value.isEmpty) {
        jar.remove(name);
      } else {
        jar[name] = value;
      }
    }
    if (jar.isEmpty) {
      _cookies.remove(target);
      _loginDomains.remove(target);
    } else {
      _loginDomains.add(target);
    }
    await _persist();
  }

  /// 记录响应中的 `Set-Cookie`，供后续请求和脚本复用。
  Future<void> absorbSetCookie(
    BookSource source,
    Uri uri,
    String? rawHeader,
  ) async {
    final raw = rawHeader?.trim() ?? '';
    if (raw.isEmpty) return;
    await load();
    var changed = false;
    for (final part in raw.split(RegExp(r',(?=\s*[^;,=]+=)'))) {
      final segments = part.split(';');
      if (segments.isEmpty) continue;
      final pair = segments.first.trim();
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty) continue;

      final requestedDomain = normalizeCookieDomain(
        _cookieAttribute(segments, 'domain'),
      );
      final host = normalizeCookieDomain(uri.host);
      final domain =
          requestedDomain.isNotEmpty &&
              cookieDomainMatches(host, requestedDomain)
          ? requestedDomain
          : host;
      if (domain.isEmpty) continue;

      final expires = _cookieAttribute(segments, 'expires').toLowerCase();
      final maxAge = _cookieAttribute(segments, 'max-age');
      final expired =
          (maxAge.isNotEmpty && (int.tryParse(maxAge) ?? 0) <= 0) ||
          expires == 'thu, 01 jan 1970 00:00:00 gmt';
      final jar = _cookies.putIfAbsent(domain, () => <String, String>{});
      if (value.isEmpty || expired) {
        changed = jar.remove(name) != null || changed;
        if (jar.isEmpty) {
          _cookies.remove(domain);
          changed = _loginDomains.remove(domain) || changed;
        }
      } else if (jar[name] != value) {
        jar[name] = value;
        changed = true;
      }
    }
    if (changed) await _persist();
  }

  /// 是否存在与书源域名匹配的有效 Cookie。
  Future<bool> hasCookiesFor(BookSource source) async {
    await load();
    for (final host in _sourceHosts(source)) {
      if (_cookiesForHost(host).isNotEmpty) return true;
    }
    return false;
  }

  /// 是否完成过网页登录并保存了该来源域名的 Cookie。
  Future<bool> hasLoginFor(BookSource source) async {
    await load();
    if ((_loginInfo[source.id]?.isNotEmpty ?? false) ||
        (_loginHeaders[source.id]?.isNotEmpty ?? false)) {
      return true;
    }
    for (final host in _sourceHosts(source)) {
      for (final domain in _loginDomains) {
        if (cookieDomainMatches(host, domain) ||
            cookieDomainMatches(domain, host)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 清除某个书源域名下的登录 Cookie。
  Future<void> clearForSource(BookSource source) async {
    await load();
    _loginInfo.remove(source.id);
    _loginHeaders.remove(source.id);
    _variables.remove(source.id);
    final hosts = _sourceHosts(source);
    _cookies.removeWhere((domain, _) {
      for (final host in hosts) {
        if (cookieDomainMatches(host, domain) ||
            cookieDomainMatches(domain, host)) {
          return true;
        }
      }
      return false;
    });
    _loginDomains.removeWhere((domain) {
      for (final host in hosts) {
        if (cookieDomainMatches(host, domain) ||
            cookieDomainMatches(domain, host)) {
          return true;
        }
      }
      return false;
    });
    await _persist();
  }

  Map<String, String> _cookiesForHost(String host) {
    final normalized = normalizeCookieDomain(host);
    if (normalized.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in _cookies.entries) {
      if (cookieDomainMatches(normalized, entry.key)) {
        result.addAll(entry.value);
      }
    }
    return Map<String, String>.unmodifiable(result);
  }

  List<String> _sourceHosts(BookSource source) {
    final hosts = <String>{};
    for (final value in <String>[source.sourceUrl, source.loginUrl]) {
      final uri = Uri.tryParse(value.trim());
      if (uri != null && uri.host.isNotEmpty) {
        hosts.add(normalizeCookieDomain(uri.host));
      }
    }
    hosts.remove('');
    return hosts.toList();
  }

  String _cookieAttribute(List<String> segments, String name) {
    final prefix = '${name.toLowerCase()}=';
    for (final segment in segments.skip(1)) {
      final text = segment.trim();
      if (text.toLowerCase().startsWith(prefix)) {
        return text.substring(prefix.length).trim();
      }
    }
    return '';
  }

  Future<void> _readFromDisk() async {
    _loaded = false;
    _cookies.clear();
    _loginDomains.clear();
    _loginInfo.clear();
    _loginHeaders.clear();
    _variables.clear();
    try {
      final file = await _cookieFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final info = decoded['loginInfo'];
          if (info is Map) {
            for (final entry in info.entries) {
              if (entry.value is Map) {
                _loginInfo['${entry.key}'] = {
                  for (final item in (entry.value as Map).entries)
                    '${item.key}': '${item.value}',
                };
              }
            }
          }
          for (final entry in (decoded['loginHeaders'] as Map? ?? {}).entries) {
            _loginHeaders['${entry.key}'] = '${entry.value}';
          }
          for (final entry in (decoded['variables'] as Map? ?? {}).entries) {
            _variables['${entry.key}'] = '${entry.value}';
          }
        }
        final rawCookies = decoded is Map ? decoded['cookies'] : null;
        if (rawCookies is Map) {
          for (final domainEntry in rawCookies.entries) {
            final domain = normalizeCookieDomain('${domainEntry.key}');
            if (domain.isEmpty || domainEntry.value is! Map) continue;
            final jar = _cookies.putIfAbsent(domain, () => <String, String>{});
            for (final cookieEntry in (domainEntry.value as Map).entries) {
              final name = '${cookieEntry.key}'.trim();
              final value = '${cookieEntry.value}'.trim();
              if (name.isNotEmpty && value.isNotEmpty) jar[name] = value;
            }
            if (jar.isEmpty) _cookies.remove(domain);
          }
        }
        final rawLoginDomains = decoded is Map ? decoded['loginDomains'] : null;
        if (rawLoginDomains is List) {
          for (final value in rawLoginDomains) {
            final domain = normalizeCookieDomain('$value');
            if (domain.isNotEmpty && _cookies.containsKey(domain)) {
              _loginDomains.add(domain);
            }
          }
        }
      }
    } on FormatException {
      _cookies.clear();
      _loginDomains.clear();
      _loginInfo.clear();
      _loginHeaders.clear();
      _variables.clear();
    } on FileSystemException {
      _cookies.clear();
      _loginDomains.clear();
      _loginInfo.clear();
      _loginHeaders.clear();
      _variables.clear();
    } on Object {
      // Cookie 是可选增强；平台目录不可用时按空 Cookie 继续。
      _cookies.clear();
      _loginDomains.clear();
      _loginInfo.clear();
      _loginHeaders.clear();
      _variables.clear();
    }
    _loaded = true;
  }

  Future<void> _persist() {
    if (!_loaded) return Future<void>.value();
    final snapshot = <String, Object?>{
      'version': 3,
      'loginInfo': {
        for (final entry in _loginInfo.entries) entry.key: Map.of(entry.value),
      },
      'loginHeaders': Map.of(_loginHeaders),
      'variables': Map.of(_variables),
      'cookies': <String, Object?>{
        for (final entry in _cookies.entries)
          entry.key: Map<String, String>.of(entry.value),
      },
      'loginDomains': _loginDomains.toList()..sort(),
    };
    _writeQueue = _writeQueue
        .catchError((Object _) {})
        .then((_) => _writeSnapshot(snapshot));
    return _writeQueue;
  }

  Future<void> _writeSnapshot(Map<String, Object?> data) async {
    final file = await _cookieFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    if (!await file.exists()) {
      await temp.rename(file.path);
      return;
    }
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
    try {
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  Future<File> _cookieFile() async {
    final root = await _directoryProvider();
    return File(p.join(root.path, 'book_sources', 'cookies.json'));
  }
}

/// 归一化 Cookie 域名：去掉协议、端口和开头的点。
String normalizeCookieDomain(String value) {
  var text = value.trim().toLowerCase();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.host.isNotEmpty) text = uri.host;
  while (text.startsWith('.')) {
    text = text.substring(1);
  }
  final colon = text.indexOf(':');
  if (colon >= 0) text = text.substring(0, colon);
  return text;
}

/// 判断 [domain] 是否可用于 [host]。
bool cookieDomainMatches(String host, String domain) {
  final normalizedHost = normalizeCookieDomain(host);
  final normalizedDomain = normalizeCookieDomain(domain);
  if (normalizedHost.isEmpty || normalizedDomain.isEmpty) return false;
  return normalizedHost == normalizedDomain ||
      normalizedHost.endsWith('.$normalizedDomain');
}
