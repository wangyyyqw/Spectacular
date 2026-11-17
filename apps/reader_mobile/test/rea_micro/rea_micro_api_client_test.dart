import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('登录提交邮箱验证码并解析令牌', () async {
    late http.Request request;
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((value) async {
        request = value;
        return _json(<String, Object?>{
          'code': 0,
          'message': 'ok',
          'data': <String, Object?>{'token': 'token-value'},
        });
      }),
    );
    addTearDown(api.close);

    final token = await api.loginWithEmail(
      email: 'reader@example.com',
      code: '123456',
    );

    expect(token, 'token-value');
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://example.test/rest/user/login-or-register',
    );
    expect(request.headers['platform'], 'android');
    expect(request.headers['Authorization'], isNull);
    expect(jsonDecode(request.body), <String, Object?>{
      'type': 'email',
      'email': 'reader@example.com',
      'code': '123456',
    });
  });

  test('读取账号与图表时携带 Bearer 令牌并解析响应', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('get-user-info')) {
          return _json(<String, Object?>{
            'code': 200,
            'message': 'ok',
            'data': <String, Object?>{
              'id': 7,
              'nickName': '阅微读者',
              'email': 'reader@example.com',
              'level': 3,
              'totalReadTime': 3600,
              'readFinishedBookNum': 2,
              'gem': 9,
            },
          });
        }
        return _json(<String, Object?>{
          'code': 0,
          'message': 'ok',
          'data': <String, Object?>{
            'charts': <Object?>[
              <String, Object?>{
                'day': '2026-11-17',
                'duration': 1800,
                'readingDuration': 1500,
                'listeningDuration': 300,
              },
            ],
          },
        });
      }),
    );
    addTearDown(api.close);

    final user = await api.fetchUser('secret-token');
    final chart = await api.fetchReadTimeChart('secret-token');

    expect(user.nickName, '阅微读者');
    expect(user.totalReadTimeSeconds, 3600);
    expect(user.readFinishedBookNum, 2);
    expect(chart.single.day, '2026-11-17');
    expect(chart.single.durationSeconds, 1800);
    for (final request in requests) {
      expect(request.headers['Authorization'], 'Bearer secret-token');
    }
    expect(jsonDecode(requests.last.body), <String, Object?>{
      'limit': 30,
      'isFillZero': true,
    });
  });

  test('业务错误与 HTTP 401 映射为可读异常', () async {
    final business = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient(
        (_) async => _json(<String, Object?>{'code': 4001, 'message': '验证码错误'}),
      ),
    );
    addTearDown(business.close);
    await expectLater(
      business.loginWithEmail(email: 'a@b.com', code: '1'),
      throwsA(
        isA<ReaMicroException>()
            .having((error) => error.message, 'message', '验证码错误')
            .having((error) => error.unauthorized, 'unauthorized', isFalse),
      ),
    );

    final unauthorized = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient(
        (_) async => _json(<String, Object?>{'code': 401}, status: 401),
      ),
    );
    addTearDown(unauthorized.close);
    await expectLater(
      unauthorized.fetchUser('expired'),
      throwsA(
        isA<ReaMicroException>().having(
          (error) => error.unauthorized,
          'unauthorized',
          isTrue,
        ),
      ),
    );
  });

  test('云端书籍搜索兼容对象、数组与列表信封', () async {
    Future<ReaMicroCloudBook?> search(Object data) async {
      final api = ReaMicroApiClient(
        baseUrl: 'https://example.test/',
        client: MockClient(
          (_) async => _json(<String, Object?>{
            'code': 0,
            'message': 'ok',
            'data': data,
          }),
        ),
      );
      addTearDown(api.close);
      return api.searchCloudBook('token', name: '书名', author: '作者');
    }

    final book = <String, Object?>{
      'cloudBookId': 42,
      'name': '云端书名',
      'author': '作者',
      'bookPublishers': <Object?>[
        '出版社',
        <String, Object?>{'name': '出版方'},
      ],
    };
    for (final data in <Object>[
      book,
      <Object?>[book],
      <String, Object?>{
        'list': <Object?>[book],
      },
      <String, Object?>{
        'books': <Object?>[book],
      },
    ]) {
      final result = await search(data);
      expect(result?.cloudBookId, 42);
      expect(result?.name, '云端书名');
      expect(result?.publishers, <String>['出版社', '出版方']);
    }
  });
}
