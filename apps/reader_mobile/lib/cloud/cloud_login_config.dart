import 'dart:convert';

import 'cloud_http.dart';
import 'cloud_models.dart';

extension CloudLoginConfig on CloudDrive {
  List<String> get cookieOrigins => switch (this) {
    CloudDrive.baidu => ['https://pan.baidu.com', 'https://passport.baidu.com'],
    CloudDrive.quark => ['https://pan.quark.cn', 'https://uop.quark.cn'],
    CloudDrive.aliyun => [
      'https://www.alipan.com',
      'https://auth.aliyundrive.com',
    ],
    CloudDrive.pan123 => ['https://yun.123pan.cn', 'https://user.123pan.cn'],
    CloudDrive.tianyi => [
      'https://cloud.189.cn',
      'https://m.cloud.189.cn',
      'https://open.e.189.cn',
    ],
    CloudDrive.pikpak => ['https://mypikpak.com', 'https://user.mypikpak.com'],
    CloudDrive.lanzou => ['https://pc.woozooo.com', 'https://up.woozooo.com'],
  };

  Set<String> get storageHosts => switch (this) {
    CloudDrive.aliyun => {'www.alipan.com', 'www.aliyundrive.com'},
    CloudDrive.pan123 => {'yun.123pan.cn', 'www.123pan.com'},
    CloudDrive.pikpak => {'mypikpak.com'},
    CloudDrive.tianyi => {'cloud.189.cn', 'm.cloud.189.cn', 'h5.cloud.189.cn'},
    _ => {},
  };

  bool canReadStorage(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      storageHosts.contains(uri.host);

  String get storageScript {
    final key = switch (this) {
      CloudDrive.aliyun => 'token',
      CloudDrive.pan123 => 'authorToken',
      _ => '',
    };
    return '''(() => {
      if (window.top !== window || location.protocol !== 'https:' ||
          !${jsonEncode(storageHosts.toList())}.includes(location.hostname) ||
          (location.port && location.port !== '443')) return '';
      ${this == CloudDrive.pikpak
        ? _pikpakRead
        : this == CloudDrive.tianyi
        ? "return JSON.stringify({browserId: window.__spectacularBrowserId || ''});"
        : this == CloudDrive.aliyun
        ? "return sessionStorage.getItem('$key') || localStorage.getItem('$key') || '';"
        : "return localStorage.getItem('$key') || sessionStorage.getItem('$key') || '';"}
    })()''';
  }

  String get bootstrapScript =>
      this == CloudDrive.tianyi ? _tianyiBrowserId : '';

  String prepareStorageScript(String session) =>
      '''(() => {
    if (window.top !== window || location.protocol !== 'https:' ||
        !${jsonEncode(storageHosts.toList())}.includes(location.hostname) ||
        (location.port && location.port !== '443')) return 'blocked';
    const marker = 'spectacular_login_session';
    if (sessionStorage.getItem(marker) === ${jsonEncode(session)}) return 'ready';
    for (const store of [localStorage, sessionStorage]) {
      for (const key of Object.keys(store)) {
        if (${this == CloudDrive.pikpak
          ? "key.startsWith('credentials') || key.startsWith('captcha_') || key === 'current_sub' || key === 'token'"
          : this == CloudDrive.aliyun
          ? "key === 'token'"
          : this == CloudDrive.pan123
          ? "key === 'authorToken' || key === 'accessToken' || key === 'userPwd'"
          : 'false'}) store.removeItem(key);
      }
    }
    sessionStorage.setItem(marker, ${jsonEncode(session)});
    return 'cleared';
  })()''';
}

// 只读取官网当前账号的凭据，不扫描无关网页或其他应用的存储。
const _pikpakRead = r'''
  const client = 'YUMx5nI8ZU8Ap8pm';
  const decode = (value) => {
    for (let i = 0; i < 4 && typeof value === 'string'; i++) {
      try { value = JSON.parse(value); } catch (_) { return null; }
    }
    return value && typeof value === 'object' ? value : null;
  };
  for (const store of [localStorage, sessionStorage]) {
    let sub = store.getItem('current_sub') || '';
    if (sub.startsWith('"')) { try { sub = JSON.parse(sub); } catch (_) {} }
    const key = 'credentials_' + client;
    for (const name of [key + '@' + sub, key, 'credentials@' + sub, 'credentials']) {
      const raw = decode(store.getItem(name));
      const value = raw?.credentials || raw?.token || raw;
      if (!value?.access_token && !value?.refresh_token) continue;
      if (sub && String(value.sub || value.user_id || '') !== String(sub)) continue;
      if (value.client_id && value.client_id !== client) continue;
      const captcha = decode(store.getItem('captcha_' + client));
      return JSON.stringify({
        access_token: value.access_token || '', refresh_token: value.refresh_token || '',
        sub: value.sub || value.user_id || '', client_id: client,
        device_id: value.device_id || (store.getItem('deviceid') || store.getItem('_deviceid') || '').replace(/^"|"$/g, '').split('.').pop().slice(0, 32),
        expires_at: value.expires_at || '',
        captcha_token: Date.parse(captcha?.expires_at || '') > Date.now() ? (captcha?.captcha_token || captcha?.token || '') : ''
      });
    }
  }
  return '';
''';

const _tianyiBrowserId = r'''(() => {
  if (window.top !== window || location.protocol !== 'https:' ||
      !['cloud.189.cn','m.cloud.189.cn','h5.cloud.189.cn'].includes(location.hostname)) return;
  const observe = (name, value) => {
    if (String(name).toLowerCase() === 'browser-id' && /^[A-Za-z0-9_-]{8,256}$/.test(value))
      window.__spectacularBrowserId = value;
  };
  const original = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    observe(name, value); return original.apply(this, arguments);
  };
  const fetch = window.fetch;
  window.fetch = function(input, init) {
    try { new Headers(init?.headers || input?.headers).forEach((v,k) => observe(k,v)); } catch (_) {}
    return fetch.apply(this, arguments);
  };
})()''';

CloudAccount? cloudLoginCandidate(
  CloudDrive drive,
  String cookie,
  Object? storage,
) {
  if (!{
    CloudDrive.aliyun,
    CloudDrive.pan123,
    CloudDrive.pikpak,
  }.contains(drive)) {
    final pairs = cloudCookies(cookie);
    final ready = switch (drive) {
      CloudDrive.baidu => pairs.containsKey('BDUSS'),
      CloudDrive.quark => pairs.containsKey('__pus'),
      CloudDrive.tianyi =>
        pairs.containsKey('COOKIE_LOGIN_USER') ||
            pairs.containsKey('LOGIN_USER'),
      CloudDrive.lanzou =>
        pairs.containsKey('ylogin') && pairs.containsKey('phpdisk_info'),
      _ => false,
    };
    return ready
        ? CloudAccount(drive, {
            'cookie': cookie,
            if (drive == CloudDrive.tianyi)
              'browserId': cloudText(_storageValue(storage)?['browserId']),
          })
        : null;
  }
  if (drive == CloudDrive.pan123) {
    var value = storage;
    if (value is String && value.startsWith('"')) value = jsonDecode(value);
    if (value is! String ||
        value.length < 16 ||
        value.contains(RegExp(r'\s'))) {
      return null;
    }
    return CloudAccount(drive, {'accessToken': value});
  }
  final data = _storageValue(storage);
  if (data == null) return null;
  final fields = <String, String>{};
  for (final entry in const {
    'accessToken': 'access_token',
    'refreshToken': 'refresh_token',
    'userId': 'user_id',
    'deviceId': 'device_id',
    'clientId': 'client_id',
    'captchaToken': 'captcha_token',
    'expiresAt': 'expire_time',
    'defaultDriveId': 'default_drive_id',
    'resourceDriveId': 'resource_drive_id',
  }.entries) {
    fields[entry.key] = cloudText(data[entry.value]);
  }
  if (drive == CloudDrive.pikpak) {
    fields['userId'] = cloudText(data['sub']);
    fields['expiresAt'] = cloudText(data['expires_at']);
  }
  if (fields['accessToken']!.isEmpty && fields['refreshToken']!.isEmpty) {
    return null;
  }
  return CloudAccount(drive, fields);
}

Map<String, dynamic>? _storageValue(Object? value) {
  try {
    for (var depth = 0; depth < 3 && value is String; depth++) {
      value = jsonDecode(value);
    }
    return value is Map ? Map<String, dynamic>.from(value) : null;
  } on FormatException {
    return null;
  }
}
