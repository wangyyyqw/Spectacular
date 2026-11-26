import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/cloud/cloud_http.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/cloud/providers/lanzou_provider.dart';
import 'package:reader_mobile/cloud/providers/pikpak_provider.dart';
import 'package:reader_mobile/cloud/providers/tianyi_provider.dart';

http.Response response(
  Object value, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

CloudAccount pikpakAccount() => CloudAccount(CloudDrive.pikpak, {
  'accessToken': '测试旧令牌',
  'refreshToken': '测试刷新令牌',
  'userId': 'user-8',
  'deviceId': 'device-8',
  'clientId': 'YUMx5nI8ZU8Ap8pm',
  'captchaToken': '测试验证令牌',
});

void main() {
  test('天翼验证身份、分目录分页并仅向官方 API 传递登录 Cookie', () async {
    final account = CloudAccount(CloudDrive.tianyi, {
      'cookie': 'COOKIE_LOGIN_USER=session-a',
      'browserId': 'browser-a',
    });
    final provider = TianyiCloudProvider(
      CloudHttp(
        client: MockClient((request) async {
          expect(request.headers['cookie'], contains('COOKIE_LOGIN_USER='));
          expect(request.headers['browser-id'], 'browser-a');
          expect(request.headers['sign-type'], '1');
          if (request.url.path.endsWith('getUserInfoForPortal.action')) {
            return response(
              {
                'userId': '8',
                'userExtResp': {'nickName': '读者'},
              },
              headers: {
                'set-cookie': 'COOKIE_LOGIN_USER=session-b; Path=/; Secure',
              },
            );
          }
          if (request.url.path.endsWith('getFileDownloadUrl.action')) {
            expect(request.url.queryParameters['fileId'], '12');
            return response({
              'fileDownloadUrl':
                  'https://download.cloud.189.cn/book?x=1&amp;y=2',
            });
          }
          expect(request.url.queryParameters['folderId'], '-11');
          expect(request.url.queryParameters['pageSize'], '60');
          final page = request.url.queryParameters['pageNum'];
          return response({
            'fileListAO': {
              'count': 61,
              'folderList': <Object?>[],
              'fileList': List.generate(
                page == '1' ? 60 : 1,
                (index) => {
                  'id': '${page == '1' ? index : 60}',
                  'name': '书$index.epub',
                  'size': 32,
                },
              ),
            },
          });
        }),
      ),
    );
    expect(await provider.validate(account), '读者');
    expect(account.cookie, contains('session-b'));
    final first = await provider.list(account, provider.rootId);
    expect(first.entries.length, 60);
    expect(first.nextPage, '2');
    expect(
      (await provider.list(
        account,
        provider.rootId,
        cursor: first.nextPage,
      )).nextPage,
      isNull,
    );
    final download = await provider.resolve(
      account,
      const CloudEntry(id: '12', name: '书.epub', size: 32),
    );
    expect(download.url.queryParameters['y'], '2');
    expect(
      download.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('cookie')),
    );
  });

  test('天翼登录失效不暴露响应内容，空的未完成分页不能伪装成成功', () async {
    var expired = true;
    final provider = TianyiCloudProvider(
      CloudHttp(
        client: MockClient(
          (_) async => expired
              ? response({
                  'res_code': 'InvalidSessionKey',
                  'message': '绝不能显示的凭据',
                })
              : response({
                  'fileListAO': {
                    'count': 90,
                    'fileList': <Object?>[],
                    'folderList': <Object?>[],
                  },
                }),
        ),
      ),
    );
    final account = CloudAccount(CloudDrive.tianyi, {
      'cookie': 'LOGIN_USER=test',
    });
    await expectLater(
      provider.validate(account),
      throwsA(
        isA<CloudException>()
            .having((error) => error.loginRequired, '需要重新登录', isTrue)
            .having(
              (error) => error.message,
              '不泄露凭据',
              isNot(contains('绝不能显示')),
            ),
      ),
    );
    expired = false;
    await expectLater(
      provider.list(account, provider.rootId),
      throwsA(isA<CloudException>()),
    );
  });

  test('PikPak 网页令牌失效后刷新一次并保持设备与网页客户端身份', () async {
    final account = pikpakAccount();
    var calls = 0, refreshes = 0;
    final provider = PikPakCloudProvider(
      CloudHttp(
        client: MockClient((request) async {
          expect(request.headers['x-client-id'], 'YUMx5nI8ZU8Ap8pm');
          expect(request.headers['x-device-id'], 'device-8');
          if (request.url.path == '/v1/auth/token') {
            refreshes++;
            expect(jsonDecode(request.body), {
              'client_id': 'YUMx5nI8ZU8Ap8pm',
              'grant_type': 'refresh_token',
              'refresh_token': '测试刷新令牌',
            });
            return response({
              'access_token': 'fresh-token',
              'refresh_token': 'fresh-refresh',
              'expires_in': 3600,
            });
          }
          if (calls++ == 0) {
            return response({'error': 'unauthenticated'}, status: 401);
          }
          expect(request.headers['authorization'], 'Bearer fresh-token');
          return response({'sub': 'user-8', 'name': 'PikPak 读者'});
        }),
      ),
    );
    expect(await provider.validate(account), 'PikPak 读者');
    expect(refreshes, 1);
    expect(account.field('refreshToken'), 'fresh-refresh');
  });

  test('PikPak 按游标翻页并选择原文件链接，下载不带账户授权', () async {
    final account = pikpakAccount();
    final provider = PikPakCloudProvider(
      CloudHttp(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/book-1')) {
            return response({
              'size': '200',
              'web_content_link': 'https://cdn.example/fallback',
              'links': {
                'application/octet-stream': {
                  'url': 'https://cdn.example/original.epub',
                },
              },
            });
          }
          expect(request.url.queryParameters['parent_id'], 'folder-1');
          expect(jsonDecode(request.url.queryParameters['filters']!), {
            'trashed': {'eq': false},
          });
          final last = request.url.queryParameters['page_token'] == 'cursor-2';
          return response({
            'files': last
                ? <Object?>[]
                : [
                    {
                      'id': 'book-1',
                      'name': '阅读.epub',
                      'size': '200',
                      'kind': 'drive#file',
                    },
                  ],
            'next_page_token': last ? '' : 'cursor-2',
          });
        }),
      ),
    );
    final first = await provider.list(account, 'folder-1');
    expect(first.nextPage, 'cursor-2');
    expect(
      (await provider.list(
        account,
        'folder-1',
        cursor: first.nextPage,
      )).nextPage,
      isNull,
    );
    final download = await provider.resolve(account, first.entries.single);
    expect(download.url.path, '/original.epub');
    expect(
      download.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('PikPak 人工安全验证不自动循环刷新或输出原始响应', () async {
    var calls = 0;
    final provider = PikPakCloudProvider(
      CloudHttp(
        client: MockClient((_) async {
          calls++;
          return response({
            'error': 'captcha_required',
            'error_description': '不能输出的令牌',
          }, status: 403);
        }),
      ),
    );
    await expectLater(
      provider.list(pikpakAccount(), ''),
      throwsA(
        isA<CloudException>()
            .having((error) => error.loginRequired, '要求网页验证', isTrue)
            .having(
              (error) => error.message,
              '只返回固定提示',
              isNot(contains('不能输出')),
            ),
      ),
    );
    expect(calls, 1);
  });

  test('蓝奏读取既有链接后解析原文件，任务限定为读取且账号 Cookie 不进入下载域', () async {
    final tasks = <String>[];
    final account = CloudAccount(CloudDrive.lanzou, {
      'cookie': 'ylogin=42; phpdisk_info=private',
    });
    final provider = LanzouCloudProvider(
      CloudHttp(
        client: MockClient((request) async {
          if (request.url.host == 'pc.woozooo.com') {
            expect(request.headers['cookie'], contains('phpdisk_info=private'));
            if (request.url.path == '/mydisk.php') {
              return http.Response(
                '<script>var uid="42"; var vei="abc";</script>',
                200,
              );
            }
            final form = Uri.splitQueryString(request.body);
            tasks.add(form['task']!);
            expect({'5', '47', '22'}, contains(form['task']));
            if (form['task'] == '22') {
              return response({
                'zt': 1,
                'info': {
                  'f_id': 'iBook42',
                  'is_newd': 'https://reader.lanzouj.com',
                  'pwd': '',
                },
              });
            }
            if (form['task'] == '47') {
              return response({
                'zt': 1,
                'text': [
                  {'fol_id': '9', 'name': '文件夹'},
                ],
              });
            }
            if (form['pg'] == '2') {
              return response({'zt': 2, 'text': <Object?>[]});
            }
            return response({
              'zt': 1,
              'text': [
                {'id': '19', 'name_all': '书.epub', 'size': '2 K'},
              ],
            });
          }
          expect(request.headers['cookie'] ?? '', isNot(contains('private')));
          if (request.url.path == '/iBook42') {
            return http.Response('<iframe src="/frame42"></iframe>', 200);
          }
          if (request.url.path == '/frame42') {
            return http.Response('''
<script>var stamp = 'signed'; var key = 'public-key';
\$.ajax({url: '/ajaxm.php?file=19', data: {action: 'downprocess', sign: stamp, websignkey: key}});</script>
''', 200);
          }
          if (request.url.path == '/ajaxm.php') {
            expect(Uri.splitQueryString(request.body)['sign'], 'signed');
            return response({
              'zt': 1,
              'dom': 'https://download.example',
              'url': 'public-file',
            });
          }
          if (request.url.path == '/file/public-file') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://cdn.example/book.epub'},
            );
          }
          expect(request.method, 'HEAD');
          return http.Response(
            '',
            200,
            headers: {
              'content-type': 'application/epub+zip',
              'content-length': '2048',
            },
          );
        }),
      ),
    );
    expect(await provider.validate(account), '蓝奏云');
    final first = await provider.list(account, '-1');
    expect(first.entries.first.isFolder, isTrue);
    expect(first.entries.last.size, 2048);
    expect(first.nextPage, '2');
    expect((await provider.list(account, '-1', cursor: '2')).entries, isEmpty);
    final download = await provider.resolve(account, first.entries.last);
    expect(download.url.toString(), 'https://cdn.example/book.epub');
    expect(download.size, 2048);
    expect(tasks.where((task) => task == '22').length, 1);
    expect(download.headers['Cookie'] ?? '', isNot(contains('private')));
  });

  test('蓝奏登录失效不显示服务器原文', () async {
    final provider = LanzouCloudProvider(
      CloudHttp(
        client: MockClient((request) async {
          if (request.url.path == '/mydisk.php') return http.Response('', 200);
          return response({'zt': 9, 'info': '秘密 Cookie'});
        }),
      ),
    );
    final account = CloudAccount(CloudDrive.lanzou, {
      'cookie': 'ylogin=9; phpdisk_info=test',
    });
    await expectLater(
      provider.validate(account),
      throwsA(
        isA<CloudException>()
            .having((error) => error.loginRequired, '登录失效', isTrue)
            .having((error) => error.message, '不显示原文', isNot(contains('秘密'))),
      ),
    );
  });
}
