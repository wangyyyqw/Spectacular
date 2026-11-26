import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/cloud/cloud_http.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/cloud/providers/baidu_provider.dart';
import 'package:reader_mobile/cloud/providers/quark_provider.dart';

http.Response _json(Map<String, Object?> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

CloudAccount _baidu() =>
    CloudAccount(CloudDrive.baidu, {'cookie': 'BDUSS=test'});
CloudAccount _quark() =>
    CloudAccount(CloudDrive.quark, {'cookie': '__pus=account; __puus=old'});
Matcher get _loginRequired => isA<CloudException>().having(
  (error) => error.loginRequired,
  '需要重新登录',
  true,
);

void main() {
  test('百度必须成功读取个人目录才能完成登录验证', () async {
    final transport = CloudHttp(
      client: MockClient((request) async {
        expect(request.url.host, 'pan.baidu.com');
        expect(request.url.path, '/api/list');
        expect(request.url.queryParameters['dir'], '/');
        expect(request.headers['Cookie'], 'BDUSS=test');
        expect(request.followRedirects, isFalse);
        return _json({'errno': -6, 'list': <Object?>[]});
      }),
    );
    addTearDown(transport.close);
    await expectLater(
      BaiduCloudProvider(transport).validate(_baidu()),
      throwsA(_loginRequired),
    );
  });

  test('百度目录保留文件 ID，子目录按路径打开并读取下一页', () async {
    final requests = <Uri>[];
    final transport = CloudHttp(
      client: MockClient((request) async {
        requests.add(request.url);
        return _json({
          'errno': 0,
          'has_more': request.url.queryParameters['page'] == '1' ? 1 : 0,
          'list': [
            {'fs_id': 12, 'server_filename': '书籍', 'path': '/书籍', 'isdir': 1},
            {
              'fs_id': 13,
              'server_filename': '阅读.epub',
              'path': '/书籍/阅读.epub',
              'isdir': 0,
              'size': 32,
            },
          ],
        });
      }),
    );
    addTearDown(transport.close);
    final provider = BaiduCloudProvider(transport);
    final first = await provider.list(_baidu(), '/');
    expect(first.entries.first.id, '/书籍');
    expect(first.entries.last.id, '13');
    expect(first.entries.last.isBook, isTrue);
    final second = await provider.list(_baidu(), '/书籍', cursor: first.nextPage);
    expect(requests.last.queryParameters['dir'], '/书籍');
    expect(requests.last.queryParameters['page'], '2');
    expect(second.nextPage, isNull);
  });

  test('百度用官网授权参数签名，只请求选中的原文件下载地址', () async {
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.path == '/api/gettemplatevariable') {
          return _json({
            'errno': 0,
            'result': {
              'sign1': 'Plaintext',
              'sign3': 'Key',
              'timestamp': 123456,
              'bdstoken': 'session-token',
            },
          });
        }
        expect(request.url.path, '/api/download');
        expect(request.url.queryParameters['sign'], 'u/MW6NlArwrT');
        expect(request.url.queryParameters['timestamp'], '123456');
        expect(request.url.queryParameters['bdstoken'], 'session-token');
        expect(jsonDecode(request.url.queryParameters['fidlist']!), [13]);
        expect(request.url.queryParameters['type'], 'dlink');
        return _json({
          'errno': 0,
          'dlink': [
            {
              'fs_id': 13,
              'dlink': 'https://d.pcs.baidu.com/file/book?ticket=one',
            },
          ],
        });
      }),
    );
    addTearDown(transport.close);
    final result = await BaiduCloudProvider(
      transport,
    ).resolve(_baidu(), const CloudEntry(id: '13', name: '阅读.epub', size: 32));
    expect(result.url.host, 'd.pcs.baidu.com');
    expect(result.size, 32);
    expect(result.headers['User-Agent'], 'netdisk');
    expect(result.headers['Cookie'], 'BDUSS=test');
  });

  for (final badResult in [
    {'fs_id': 99, 'dlink': 'https://d.pcs.baidu.com/other'},
    {'fs_id': 13, 'dlink': 'https://pan.baidu.com.example.org/file'},
  ]) {
    test('百度拒绝不匹配文件或伪装下载域名：${badResult['fs_id']}', () async {
      final transport = CloudHttp(
        client: MockClient((request) async {
          return request.url.path == '/api/gettemplatevariable'
              ? _json({
                  'errno': 0,
                  'result': {
                    'sign1': 'Plaintext',
                    'sign3': 'Key',
                    'timestamp': 1,
                  },
                })
              : _json({
                  'errno': 0,
                  'dlink': [badResult],
                });
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        BaiduCloudProvider(transport)
            .resolve(_baidu(), const CloudEntry(id: '13', name: '阅读.epub')),
        throwsA(isA<CloudException>()),
      );
    });
  }

  test('夸克目录按页读取，目录和 EPUB、TXT 类型正确', () async {
    final requests = <Uri>[];
    final transport = CloudHttp(
      client: MockClient((request) async {
        requests.add(request.url);
        expect(request.headers['Cookie'], contains('__pus=account'));
        expect(request.followRedirects, isFalse);
        return _json({
          'status': 200,
          'code': 0,
          'data': {
            'list': request.url.queryParameters['_page'] == '1'
                ? List.generate(
                    100,
                    (index) => {
                      'fid': '$index',
                      'file_name': index == 0 ? '书籍' : '书$index.epub',
                      'dir': index == 0,
                      'size': index,
                    },
                  )
                : [
                    {'fid': 'last', 'file_name': '最后一本.txt', 'size': 7},
                  ],
          },
        });
      }),
    );
    addTearDown(transport.close);
    final provider = QuarkCloudProvider(transport);
    final first = await provider.list(_quark(), '0');
    expect(first.entries.first.isFolder, isTrue);
    expect(first.entries.last.isBook, isTrue);
    final second = await provider.list(_quark(), '0', cursor: first.nextPage);
    expect(requests.last.queryParameters['_page'], '2');
    expect(second.entries.single.isBook, isTrue);
    expect(second.nextPage, isNull);
  });

  test('夸克认证失败刷新 Cookie 一次后验证目录并保留新凭据', () async {
    var renewals = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/config')) {
          renewals++;
          expect(request.headers['Cookie'], '__pus=account');
          return http.Response(
            jsonEncode({'status': 200, 'code': 0, 'data': <String, Object?>{}}),
            200,
            headers: {'set-cookie': '__puus=new; Path=/; Secure'},
          );
        }
        if (request.headers['Cookie']!.contains('__puus=old')) {
          return _json({'status': 401, 'code': 31001});
        }
        return _json({
          'status': 200,
          'code': 0,
          'data': {'list': <Object?>[]},
        });
      }),
    );
    addTearDown(transport.close);
    final account = _quark();
    expect(await QuarkCloudProvider(transport).validate(account), '夸克网盘');
    expect(account.cookie, contains('__puus=new'));
    expect(renewals, 1);
  });

  test('夸克同账号并行失效请求共用一次 Cookie 刷新', () async {
    final refresh = Completer<http.Response>();
    var renewals = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/config')) {
          renewals++;
          return refresh.future;
        }
        return request.headers['Cookie']!.contains('__puus=new')
            ? _json({
                'status': 200,
                'code': 0,
                'data': {'list': <Object?>[]},
              })
            : _json({'status': 401, 'code': 31001});
      }),
    );
    addTearDown(transport.close);
    final provider = QuarkCloudProvider(transport), account = _quark();
    final requests = [provider.list(account, '0'), provider.list(account, '1')];
    await Future<void>.delayed(Duration.zero);
    expect(renewals, 1);
    refresh.complete(
      http.Response(
        jsonEncode({'status': 200, 'code': 0, 'data': <String, Object?>{}}),
        200,
        headers: {'set-cookie': '__puus=new; Path=/; Secure'},
      ),
    );
    expect(await Future.wait(requests), hasLength(2));
  });

  test('夸克真实登录失效不会无限刷新或误报验证成功', () async {
    var renewals = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/config')) renewals++;
        return _json({'status': 401, 'code': 31001});
      }),
    );
    addTearDown(transport.close);
    await expectLater(
      QuarkCloudProvider(transport).validate(_quark()),
      throwsA(_loginRequired),
    );
    expect(renewals, 1);
  });

  test('夸克下载原文件带必要请求头，拒绝文件大小变化', () async {
    final transport = CloudHttp(
      client: MockClient((request) async {
        expect(request.url.path, '/1/clouddrive/file/download');
        expect(jsonDecode(request.body), {
          'fids': ['book'],
        });
        return _json({
          'status': 200,
          'code': 0,
          'data': [
            {
              'fid': 'book',
              'size': 20,
              'download_url': 'https://dl.quark.cn/book',
            },
          ],
        });
      }),
    );
    addTearDown(transport.close);
    final provider = QuarkCloudProvider(transport);
    final result = await provider.resolve(
      _quark(),
      const CloudEntry(id: 'book', name: '书.epub', size: 20),
    );
    expect(result.headers['Cookie'], contains('__pus=account'));
    expect(result.headers['Referer'], 'https://pan.quark.cn/');
    await expectLater(
      provider.resolve(
        _quark(),
        const CloudEntry(id: 'book', name: '书.epub', size: 21),
      ),
      throwsA(isA<CloudException>()),
    );
  });

  test('目录与非书籍文件不会触发百度或夸克取链', () async {
    final transport = CloudHttp(
      client: MockClient((_) async {
        fail('不应发出请求');
      }),
    );
    addTearDown(transport.close);
    for (final provider in [
      BaiduCloudProvider(transport),
      QuarkCloudProvider(transport),
    ]) {
      await expectLater(
        provider.resolve(
          provider.drive == CloudDrive.baidu ? _baidu() : _quark(),
          const CloudEntry(id: '1', name: '目录', isFolder: true),
        ),
        throwsA(isA<CloudException>()),
      );
    }
  });
}
