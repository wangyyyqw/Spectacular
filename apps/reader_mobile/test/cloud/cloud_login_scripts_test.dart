import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/cloud/cloud_login_config.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';

Future<Map<String, dynamic>> _execute(CloudDrive drive, String scenario) async {
  final directory = await Directory.systemTemp.createTemp(
    'cloud-login-script-',
  );
  try {
    final fixture = File('${directory.path}/fixture.cjs');
    final input = File('${directory.path}/input.json');
    await fixture.writeAsString(_fixture);
    await input.writeAsString(
      jsonEncode({
        'drive': drive.name,
        'host': drive.storageHosts.first,
        'scenario': scenario,
        'prepare': drive.prepareStorageScript('首次登录会话'),
        'next': drive.prepareStorageScript('下一次登录会话'),
        'read': drive.storageScript,
      }),
    );
    final result = await Process.run('node', [
      fixture.path,
      input.path,
    ], stdoutEncoding: utf8);
    expect(result.exitCode, 0, reason: '正式登录脚本执行失败：${result.stderr}');
    return Map<String, dynamic>.from(
      jsonDecode(result.stdout as String) as Map,
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

void main() {
  for (final drive in [
    CloudDrive.aliyun,
    CloudDrive.pan123,
    CloudDrive.pikpak,
  ]) {
    test('${drive.label}首次清旧凭据、同会话刷新保留新登录、新会话重新清理', () async {
      final actual = await _execute(drive, 'lifecycle');
      expect(actual['first'], 'cleared');
      expect(actual['oldLocal'], isNull);
      expect(actual['oldSession'], isNull);
      expect(actual['unrelated'], '保留网页显示偏好');
      expect(actual['sameSession'], 'ready');
      expect(actual['localAfterReload'], actual['fresh']);
      expect(actual['sessionAfterReload'], actual['fresh']);
      expect(actual['readAfterReload'], isNotEmpty);
      expect(actual['newSession'], 'cleared');
      expect(actual['localAfterNewSession'], isNull);
      expect(actual['sessionAfterNewSession'], isNull);
      expect(actual['readAfterNewSession'], '');
    });

    test('${drive.label}非可信域、HTTP、非默认端口及子框架既不读取也不清理', () async {
      final actual = await _execute(drive, 'untrusted');
      for (final result in actual.values.cast<Map<String, dynamic>>()) {
        expect(result['read'], '');
        expect(result['prepare'], 'blocked');
        expect(result['credential'], result['before']);
      }
    });
  }

  test('PikPak 只读取 current_sub 对应账号并提取设备编号', () async {
    final actual = await _execute(CloudDrive.pikpak, 'identity');
    expect(actual['mismatched'], '');
    final captured = Map<String, dynamic>.from(
      jsonDecode(actual['matched'] as String) as Map,
    );
    expect(captured['sub'], 'current-reader');
    expect(captured['access_token'], 'current-session');
    expect(captured['device_id'], 'device01234567890123456789012345');
    expect(actual['wrongClient'], '');
    final fallback = Map<String, dynamic>.from(
      jsonDecode(actual['alternateDevice'] as String) as Map,
    );
    expect(fallback['device_id'], 'alternative-device');
  });

  test('PikPak 超出 JavaScript 安全整数的账号编号仍按原字符串匹配', () async {
    final actual = await _execute(CloudDrive.pikpak, 'largeIdentity');
    expect(
      actual['captured'],
      isNotEmpty,
      reason: 'current_sub 是账号标识，不能通过 JSON.parse 转换成有精度损失的数字',
    );
    final captured = Map<String, dynamic>.from(
      jsonDecode(actual['captured'] as String) as Map,
    );
    expect(captured['sub'], '9223372036854775806');
  });
}

// Node 只执行生产代码导出的脚本；存储桩保留 Web Storage 的枚举和字符串语义。
const _fixture = r'''
const fs = require('node:fs');
const vm = require('node:vm');
const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const client = 'YUMx5nI8ZU8Ap8pm';
const storage = () => {
  const value = Object.create(null);
  Object.defineProperties(value, {
    getItem: {value: key => Object.hasOwn(value, key) ? value[key] : null},
    setItem: {value: (key, text) => { value[key] = String(text); }},
    removeItem: {value: key => { delete value[key]; }},
  });
  return value;
};
const localStorage = storage(), sessionStorage = storage();
const context = {
  localStorage, sessionStorage,
  location: {protocol: 'https:', hostname: input.host, port: ''},
};
context.window = context;
context.top = context;
vm.createContext(context);
const run = source => vm.runInContext(source, context, {timeout: 1000});
const key = input.drive === 'aliyun' ? 'token' : input.drive === 'pan123'
  ? 'authorToken' : 'credentials_' + client;
const credentials = (owner, access) => JSON.stringify({
  sub: owner, access_token: access, refresh_token: 'fixture-refresh', client_id: client,
});
const fresh = input.drive === 'pikpak' ? credentials('new-reader', 'fresh-session')
  : input.drive === 'aliyun' ? JSON.stringify({access_token: 'fresh-session', refresh_token: 'fixture-refresh'})
  : '123-new-token-for-test';
let output;
if (input.scenario === 'lifecycle') {
  localStorage.setItem(key, '旧登录');
  sessionStorage.setItem(key, '旧登录');
  localStorage.setItem('displayTheme', '保留网页显示偏好');
  const first = run(input.prepare);
  const oldLocal = localStorage.getItem(key), oldSession = sessionStorage.getItem(key);
  localStorage.setItem(key, fresh);
  sessionStorage.setItem(key, fresh);
  const sameSession = run(input.prepare);
  const localAfterReload = localStorage.getItem(key), sessionAfterReload = sessionStorage.getItem(key);
  const readAfterReload = run(input.read);
  const newSession = run(input.next);
  output = {first, oldLocal, oldSession, sameSession, localAfterReload, sessionAfterReload,
    readAfterReload, newSession, fresh,
    unrelated: localStorage.getItem('displayTheme'),
    localAfterNewSession: localStorage.getItem(key), sessionAfterNewSession: sessionStorage.getItem(key),
    readAfterNewSession: run(input.read)};
} else if (input.scenario === 'untrusted') {
  localStorage.setItem(key, fresh);
  output = {};
  const cases = {
    foreign: {hostname: 'example.invalid'},
    lookalike: {hostname: input.host + '.example.invalid'},
    plaintext: {protocol: 'http:'},
    port: {port: '8443'},
    child: {child: true},
  };
  for (const [name, changes] of Object.entries(cases)) {
    context.location = {protocol: 'https:', hostname: input.host, port: '', ...changes};
    context.top = changes.child ? {} : context;
    output[name] = {read: run(input.read), prepare: run(input.prepare),
      credential: localStorage.getItem(key), before: fresh};
  }
} else if (input.scenario === 'identity') {
  localStorage.setItem('current_sub', JSON.stringify('current-reader'));
  localStorage.setItem(key, credentials('previous-reader', 'previous-session'));
  const mismatched = run(input.read);
  localStorage.setItem(key + '@current-reader', credentials('current-reader', 'current-session'));
  localStorage.setItem('deviceid', JSON.stringify('web.device012345678901234567890123456789'));
  const matched = run(input.read);
  localStorage.setItem(key + '@current-reader', JSON.stringify({sub: 'current-reader',
    access_token: 'different-client-session', client_id: 'other-client'}));
  const wrongClient = run(input.read);
  localStorage.setItem(key + '@current-reader', credentials('current-reader', 'current-session'));
  localStorage.removeItem('deviceid');
  localStorage.setItem('_deviceid', JSON.stringify('web.alternative-device'));
  output = {mismatched, matched, wrongClient, alternateDevice: run(input.read)};
} else if (input.scenario === 'largeIdentity') {
  const owner = '9223372036854775806';
  localStorage.setItem('current_sub', owner);
  localStorage.setItem(key + '@' + owner, credentials(owner, 'large-id-session'));
  output = {captured: run(input.read)};
} else {
  throw new Error('未知测试场景');
}
process.stdout.write(JSON.stringify(output));
''';
