import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/storage/online_page_cache.dart';
import 'package:reader_mobile/ye_she/ye_she_api_client.dart';

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(YeSheApiClient.clearCache);

  test('服务中断时只回退同账号的读请求，登录失效或竞价不回放', () async {
    var token = '甲';
    var status = 200;
    final api = YeSheApiClient(
      tokenProvider: () => token,
      pageCache: OnlinePageCache(null),
      retryDelay: Duration.zero,
      client: MockClient(
        (_) async => _json({
          'code': 0,
          'data': {'coin': 8},
        }, status: status),
      ),
    );
    addTearDown(api.close);
    expect((await api.fetchCommunityStatus())['coin'], 8);
    await api.bidAuction(id: 1, amount: 2);
    YeSheApiClient.clearCache();
    status = 503;
    expect((await api.fetchCommunityStatus())['coin'], 8);
    await expectLater(
      api.bidAuction(id: 1, amount: 2),
      throwsA(isA<YeSheException>()),
    );
    token = '乙';
    await expectLater(
      api.fetchCommunityStatus(),
      throwsA(isA<YeSheException>()),
    );
    token = '甲';
    status = 401;
    await expectLater(
      api.fetchCommunityStatus(),
      throwsA(
        isA<YeSheException>().having(
          (error) => error.unauthorized,
          '登录失效',
          true,
        ),
      ),
    );
  });

  test('野社请求使用 Bearer 令牌、平台头和 JSON 请求体', () async {
    late http.Request request;
    final api = YeSheApiClient(
      tokenProvider: () => 'secret-token',
      baseUrl: 'https://example.test/',
      client: MockClient((value) async {
        request = value;
        return _json(<String, Object?>{
          'code': 0,
          'message': 'OK',
          'data': <String, Object?>{
            'id': 8,
            'objectName': '青瓷笔洗',
            'highestBid': '120',
          },
        });
      }),
    );
    addTearDown(api.close);

    final data = await api.bidAuction(id: 8, amount: 120);

    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://example.test/rest/community/bid-auction',
    );
    expect(request.headers['Authorization'], 'Bearer secret-token');
    expect(request.headers['platform'], 'android');
    expect(request.headers['Content-Type'], 'application/json; charset=utf-8');
    expect(jsonDecode(request.body), <String, Object?>{'id': 8, 'amount': 120});
    expect(data['objectName'], '青瓷笔洗');
  });

  test('未登录时不发起请求', () async {
    var requests = 0;
    final api = YeSheApiClient(
      tokenProvider: () => '',
      client: MockClient((_) async {
        requests += 1;
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }),
    );
    addTearDown(api.close);

    await expectLater(
      api.fetchCommunityStatus(),
      throwsA(
        isA<YeSheException>()
            .having((error) => error.unauthorized, 'unauthorized', isTrue)
            .having((error) => error.message, 'message', '请先登录阅微账号'),
      ),
    );
    expect(requests, 0);
  });

  test('业务错误与 HTTP 401 转换为野社异常', () async {
    final business = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      client: MockClient(
        (_) async => _json(<String, Object?>{'code': 4101, 'message': '铜钱不足'}),
      ),
    );
    addTearDown(business.close);
    await expectLater(
      business.makeWish(1),
      throwsA(
        isA<YeSheException>()
            .having((error) => error.message, 'message', '铜钱不足')
            .having((error) => error.unauthorized, 'unauthorized', isFalse),
      ),
    );

    final unauthorized = YeSheApiClient(
      tokenProvider: () => 'expired',
      baseUrl: 'https://example.test/',
      client: MockClient(
        (_) async => _json(<String, Object?>{'code': 401}, status: 401),
      ),
    );
    addTearDown(unauthorized.close);
    await expectLater(
      unauthorized.fetchCommunityTitle(),
      throwsA(
        isA<YeSheException>().having(
          (error) => error.unauthorized,
          'unauthorized',
          isTrue,
        ),
      ),
    );
  });

  test('数组信封转换为 items 并保留服务端消息', () async {
    final api = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      client: MockClient(
        (_) async => _json(<String, Object?>{
          'code': 0,
          'message': 'OK',
          'data': <Object?>[
            <String, Object?>{'id': 1, 'content': '今日传闻'},
          ],
        }),
      ),
    );
    addTearDown(api.close);

    final data = await api.fetchRumors();

    expect(data['message'], 'OK');
    expect(data['items'], hasLength(1));
  });

  test('商会拍卖使用独立接口与 auctionId 请求体', () async {
    final requests = <http.Request>[];
    final api = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'success': true,
            'message': '出价成功',
            'coin': '300',
          },
        });
      }),
    );
    addTearDown(api.close);

    await api.fetchGuildAuction();
    await api.bidGuildAuction(auctionId: 9, amount: 125);
    await api.abandonCommunityTitle();

    expect(
      requests[0].url.toString(),
      'https://example.test/rest/community/get-guild-auction',
    );
    expect(
      requests[1].url.toString(),
      'https://example.test/rest/community/bid-guild-auction',
    );
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'auctionId': 9,
      'amount': 125,
    });
    expect(
      requests[2].url.toString(),
      'https://example.test/rest/community/abandon-community-title',
    );
  });

  test('玉机阁兑换复用百杂铺购买接口', () async {
    late http.Request request;
    final api = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      client: MockClient((value) async {
        request = value;
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }),
    );
    addTearDown(api.close);

    await api.buyVoucherShop(propId: 17, quantity: 2);

    expect(
      request.url.toString(),
      'https://example.test/rest/community/buy-daily-shop',
    );
    expect(jsonDecode(request.body), <String, Object?>{
      'propId': 17,
      'quantity': 2,
    });
  });

  test('阅微排行榜使用 rest/rank 路由', () async {
    final requests = <String>[];
    final api = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request.url.path);
        return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
      }),
    );
    addTearDown(api.close);

    await api.fetchReadDurationRank();
    await api.fetchWealthRank();
    await api.fetchAuctionRank();
    await api.fetchCollectionValueRank();
    await api.fetchCommunityTitleRank();

    expect(requests, <String>[
      '/rest/rank/get-read-duration-rank',
      '/rest/rank/get-wealth-rank',
      '/rest/rank/get-auction-rank',
      '/rest/rank/get-collection-value-rank',
      '/rest/rank/get-community-title-rank',
    ]);
  });

  test('重复读请求在短时间内复用缓存，写操作会清空缓存', () async {
    var requests = 0;
    final api = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      retryDelay: Duration.zero,
      client: MockClient((request) async {
        requests += 1;
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{'requests': requests},
        });
      }),
    );
    addTearDown(api.close);

    await api.fetchCommunityStatus();
    final cached = await api.fetchCommunityStatus();
    expect(requests, 1);
    expect(cached['requests'], 1);

    await api.makeWish(1);
    await api.fetchCommunityStatus();
    expect(requests, 3);
  });

  test('读请求遇到服务端临时错误会重试一次', () async {
    var requests = 0;
    final api = YeSheApiClient(
      tokenProvider: () => 'token',
      baseUrl: 'https://example.test/',
      retryDelay: Duration.zero,
      client: MockClient((request) async {
        requests += 1;
        if (requests == 1) {
          return _json(<String, Object?>{'message': 'busy'}, status: 503);
        }
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{'ok': true},
        });
      }),
    );
    addTearDown(api.close);

    final data = await api.fetchCommunityStatus();

    expect(requests, 2);
    expect(data['ok'], isTrue);
  });
}
