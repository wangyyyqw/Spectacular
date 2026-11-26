import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:reader_mobile/cloud/cloud_http.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/cloud/providers/aliyun_device.dart';
import 'package:reader_mobile/cloud/providers/aliyun_provider.dart';
import 'package:reader_mobile/cloud/providers/pan123_provider.dart';

http.Response _json(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );

CloudAccount _ali({bool signed = true}) => CloudAccount(CloudDrive.aliyun, {
  'accessToken': 'access-old',
  'refreshToken': 'refresh-old',
  'userId': 'user-one',
  'resourceDriveId': 'resource-one',
  if (signed) ...{
    'signature': 'verified-device',
    'sessionExpiresAt': '${DateTime.now().millisecondsSinceEpoch + 3600000}',
  },
});

const _aliFile = CloudEntry(
  id: 'file-one',
  name: '原书.epub',
  size: 12,
  extra: {'driveId': 'resource-one'},
);

void main() {
  test('阿里设备签名能由公开密钥验证且采用低 S 值', () {
    final account = _ali(signed: false);
    account.fields.addAll({
      'deviceId': 'device-one',
      'devicePrivateKey': '1'.padLeft(64, '0'),
    });
    final result = AliyunDevice.sign(account);
    final curve = pc.ECDomainParameters('secp256k1');
    final publicBytes = Uint8List.fromList([
      for (var i = 0; i < result.publicKey.length; i += 2)
        int.parse(result.publicKey.substring(i, i + 2), radix: 16),
    ]);
    final r = BigInt.parse(result.signature.substring(0, 64), radix: 16);
    final s = BigInt.parse(result.signature.substring(64, 128), radix: 16);
    final verifier = pc.ECDSASigner()
      ..init(
        false,
        pc.PublicKeyParameter(
          pc.ECPublicKey(curve.curve.decodePoint(publicBytes), curve),
        ),
      );
    final digest = Uint8List.fromList(
      sha256
          .convert(utf8.encode('${AliyunDevice.appId}:device-one:user-one:0'))
          .bytes,
    );
    expect(verifier.verifySignature(digest, pc.ECSignature(r, s)), isTrue);
    expect(s <= curve.n ~/ BigInt.two, isTrue);
    expect(
      int.parse(result.signature.substring(128), radix: 16),
      inInclusiveRange(0, 3),
    );
  });

  test('阿里登录验证读取资源库并保留目录分页', () async {
    final account = _ali(signed: false);
    var created = 0, listed = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], 'Bearer access-old');
        final body = cloudMap(jsonDecode(request.body));
        switch (request.url.path) {
          case '/v2/user/get':
            return _json({
              'user_id': 'user-one',
              'nick_name': '读者',
              'resource_drive_id': 'resource-one',
              'default_drive_id': 'backup',
            });
          case '/users/v1/users/device/create_session':
            created++;
            expect(body['pubKey'], matches(RegExp(r'^04[0-9a-f]{128}$')));
            expect(
              request.headers['x-signature'],
              matches(RegExp(r'^[0-9a-f]{130}$')),
            );
            return _json({'result': true});
          case '/adrive/v3/file/list':
            listed++;
            expect(body['drive_id'], 'resource-one');
            expect(body['marker'], listed == 1 ? '' : 'second');
            return _json({
              'items': [
                {
                  'file_id': 'file-one',
                  'name': '原书.epub',
                  'size': 12,
                  'type': 'file',
                },
              ],
              'next_marker': listed == 1 ? 'second' : '',
            });
          default:
            fail('出现预期外请求');
        }
      }),
    );
    final provider = AliyunCloudProvider(transport);
    expect(await provider.validate(account), '读者');
    final page = await provider.list(account, 'root', cursor: 'second');
    expect(page.entries.single.isBook, isTrue);
    expect(page.entries.single.extra['driveId'], 'resource-one');
    expect(page.nextPage, isNull);
    expect(created, 1);
    transport.close();
  });

  test('阿里地址失效只刷新一次 Token 并返回原文件地址', () async {
    final account = _ali();
    var reads = 0, refreshes = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.host == 'auth.aliyundrive.com') {
          refreshes++;
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(
            cloudMap(jsonDecode(request.body))['refresh_token'],
            'refresh-old',
          );
          return _json({
            'access_token': 'access-new',
            'refresh_token': 'refresh-new',
            'expires_in': 7200,
            'user_id': 'user-one',
          });
        }
        reads++;
        expect(request.url.path, '/v2/file/get_download_url');
        expect(cloudMap(jsonDecode(request.body))['file_id'], 'file-one');
        if (reads == 1) return http.Response.bytes(utf8.encode('会话过期'), 401);
        expect(request.headers['authorization'], 'Bearer access-new');
        return _json({
          'file_id': 'file-one',
          'size': 12,
          'download_url': 'https://download.example/book.epub',
        });
      }),
    );
    final result = await AliyunCloudProvider(transport)
        .resolve(account, _aliFile);
    expect(result.url.path, '/book.epub');
    expect(result.headers.containsKey('Authorization'), isFalse);
    expect(result.headers['Referer'], 'https://www.aliyundrive.com/');
    expect(account.field('refreshToken'), 'refresh-new');
    expect(refreshes, 1);
    expect(reads, 2);
    transport.close();
  });

  test('阿里不把文件详情中的预览地址作为 EPUB 下载', () async {
    final transport = CloudHttp(
      client: MockClient((request) async {
        return _json(
          request.url.path.endsWith('get_download_url')
              ? {}
              : {
                  'file_id': 'file-one',
                  'size': 12,
                  'url': 'https://preview.example/page.png',
                },
        );
      }),
    );
    await expectLater(
      AliyunCloudProvider(transport).resolve(_ali(), _aliFile),
      throwsA(isA<CloudException>()),
    );
    transport.close();
  });

  test('阿里设备签名失效时只重建会话并重试当前目录', () async {
    var lists = 0, devices = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.path.endsWith('create_session')) {
          devices++;
          return _json({'result': true});
        }
        lists++;
        if (lists == 1) {
          return _json({'code': 'DeviceSessionSignatureInvalid'}, 403);
        }
        return _json({'items': <Object?>[], 'next_marker': ''});
      }),
    );
    final page = await AliyunCloudProvider(transport).list(_ali(), 'root');
    expect(page.entries, isEmpty);
    expect(lists, 2);
    expect(devices, 1);
    transport.close();
  });

  test('阿里持续拒绝 Token 时停止刷新并提示重新登录', () async {
    var refreshes = 0, reads = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        if (request.url.host == 'auth.aliyundrive.com') {
          refreshes++;
          return _json({'access_token': 'new-access', 'user_id': 'user-one'});
        }
        reads++;
        return _json({'code': 'AccessTokenInvalid'}, 401);
      }),
    );
    await expectLater(
      AliyunCloudProvider(transport).resolve(_ali(), _aliFile),
      throwsA(
        isA<CloudException>().having((e) => e.loginRequired, '需登录', isTrue),
      ),
    );
    expect(refreshes, 1);
    expect(reads, 2);
    transport.close();
  });

  test('阿里刷新拒绝其他账号凭据且不覆盖原 Token', () async {
    final account = _ali()..fields['expiresAt'] = '1';
    final transport = CloudHttp(
      client: MockClient(
        (request) async =>
            _json({'access_token': 'other-access', 'user_id': 'other-user'}),
      ),
    );
    await expectLater(
      AliyunCloudProvider(transport).resolve(account, _aliFile),
      throwsA(
        isA<CloudException>().having((e) => e.loginRequired, '需登录', isTrue),
      ),
    );
    expect(account.field('accessToken'), 'access-old');
    transport.close();
  });

  test('123 校验后读取分页且将真实文件参数用于取链', () async {
    final account = CloudAccount(CloudDrive.pan123, {
      'accessToken': 'web-token',
    });
    var lists = 0;
    final transport = CloudHttp(
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        if (request.url.host == 'download.example') {
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response.bytes(utf8.encode('PK原书内容'), 206);
        }
        expect(request.headers['authorization'], 'Bearer web-token');
        expect(
          request.headers['auth-value'],
          matches(RegExp(r'^\d+-\d+-[0-9a-f]+$')),
        );
        switch (request.url.path) {
          case '/b/api/user/info':
            return _json({
              'code': 0,
              'data': {'UID': 7, 'Nickname': '书友'},
            });
          case '/b/api/file/list/new':
            lists++;
            expect(
              request.url.queryParameters['next'],
              lists == 1 ? '0' : 'next-cursor',
            );
            return _json({
              'code': 0,
              'data': {
                'Next': lists == 1 ? 'next-cursor' : '-1',
                'InfoList': [
                  {
                    'FileId': 123,
                    'FileName': '原书.epub',
                    'Size': 12,
                    'Type': 0,
                    'Etag': 'content-hash',
                    'S3KeyFlag': 'storage-node',
                  },
                ],
              },
            });
          case '/api/file/download_info':
            final body = cloudMap(jsonDecode(request.body));
            expect(body['fileId'], 123);
            expect(body['etag'], 'content-hash');
            expect(body['s3keyFlag'], 'storage-node');
            final target = base64Encode(
              utf8.encode('https://download.example/book.epub'),
            );
            return _json({
              'code': 0,
              'data': {
                'DownloadUrl': Uri.https('download.123pan.cn', '/download-v2', {
                  'params': target,
                }).toString(),
              },
            });
          default:
            fail('出现预期外请求');
        }
      }),
    );
    final provider = Pan123CloudProvider(transport);
    expect(await provider.validate(account), '书友');
    final page = await provider.list(account, '0', cursor: 'next-cursor');
    expect(page.nextPage, isNull);
    final result = await provider.resolve(account, page.entries.single);
    expect(result.url.host, 'download.example');
    expect(result.size, 12);
    expect(result.headers.keys, isNot(contains('Authorization')));
    transport.close();
  });

  test('123 业务失效码要求重新登录且不回显服务端凭据', () async {
    final account = CloudAccount(CloudDrive.pan123, {
      'accessToken': 'private-token',
    });
    final transport = CloudHttp(
      client: MockClient(
        (request) async => _json({'code': 20101, 'message': 'private-token'}),
      ),
    );
    await expectLater(
      Pan123CloudProvider(transport).list(account, '0'),
      throwsA(
        isA<CloudException>()
            .having((e) => e.loginRequired, '需登录', isTrue)
            .having(
              (e) => e.message,
              '提示已脱敏',
              isNot(contains('private-token')),
            ),
      ),
    );
    transport.close();
  });

  test('123 显式空游标可以翻页但重复空游标会停止', () async {
    final transport = CloudHttp(
      client: MockClient(
        (request) async => _json({
          'code': 0,
          'data': {
            'Next': '',
            'InfoList': [
              {'FileId': 1, 'FileName': '原书.epub', 'Type': 0},
            ],
          },
        }),
      ),
    );
    final account = CloudAccount(CloudDrive.pan123, {'accessToken': 'access'});
    final provider = Pan123CloudProvider(transport);
    expect((await provider.list(account, '0')).nextPage, '');
    await expectLater(
      provider.list(account, '0', cursor: ''),
      throwsA(
        isA<CloudException>().having(
          (e) => e.message,
          '分页错误',
          contains('分页重复'),
        ),
      ),
    );
    transport.close();
  });

  test('123 JSON 跳转探测不会把账号授权发送给下载节点', () async {
    final transport = CloudHttp(
      client: MockClient((request) async {
        switch (request.url.host) {
          case 'yun.123pan.cn':
            return _json({
              'code': 0,
              'data': {'DownloadUrl': 'https://redirect.example/prepare'},
            });
          case 'redirect.example':
            expect(request.headers.containsKey('authorization'), isFalse);
            return _json({
              'code': 0,
              'data': {'redirect_url': 'https://cdn.example/final.txt'},
            });
          case 'cdn.example':
            expect(request.headers.containsKey('authorization'), isFalse);
            return http.Response.bytes(
              utf8.encode('{正文以花括号开头'),
              206,
              headers: {'content-type': 'text/plain'},
            );
          default:
            fail('出现预期外请求');
        }
      }),
    );
    final result = await Pan123CloudProvider(transport).resolve(
      CloudAccount(CloudDrive.pan123, {'accessToken': 'web-token'}),
      const CloudEntry(id: '9', name: '正文.txt', size: 20),
    );
    expect(result.url.host, 'cdn.example');
    transport.close();
  });
}
