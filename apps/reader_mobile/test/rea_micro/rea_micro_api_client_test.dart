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

  test('上报阅读位置提交 CFI、章节名与进度', () async {
    late http.Request request;
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((value) async {
        request = value;
        return _json(<String, Object?>{'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    await api.updateReadProgress(
      'secret-token',
      cloudBookId: 42,
      cfi: 'epubcfi(/6/4!/4/2/1)',
      chapterName: '第二章',
      progress: 0.375,
    );

    expect(request.url.path, '/rest/reader/update-read-progress');
    expect(request.headers['Authorization'], 'Bearer secret-token');
    expect(jsonDecode(request.body), <String, Object?>{
      'bookId': 42,
      'cfi': 'epubcfi(/6/4!/4/2/1)',
      'chapterName': '第二章',
      'progress': 0.375,
    });
  });

  test('读取云端阅读位置并解析秒级时间戳', () async {
    late http.Request request;
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((value) async {
        request = value;
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'bookId': 42,
            'cfi': 'epubcfi(/6/4!/4/2/1)',
            'chapterName': '第二章',
            'progress': 37.5,
            'readFinishTime': 1763380800,
          },
        });
      }),
    );
    addTearDown(api.close);

    final progress = await api.fetchReadProgress(
      'secret-token',
      cloudBookId: '42',
    );

    expect(request.url.path, '/rest/reader/get-read-progress');
    expect(jsonDecode(request.body), <String, Object?>{'bookId': '42'});
    expect(progress?.cfi, 'epubcfi(/6/4!/4/2/1)');
    expect(progress?.chapterName, '第二章');
    expect(progress?.progress, 0.375);
    expect(progress?.readFinishTime, 1763380800000);
  });

  test('书评与里程碑使用阅微评分接口并解析嵌套响应', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('get-review-by-book-id-v2')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'review': <String, Object?>{
                'id': 21,
                'rating': 4,
                'comment': '旧书评',
                'status': 2,
                'bookName': '云端书',
              },
            },
          });
        }
        if (request.url.path.endsWith('get-milestone-list-v2')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'milestones': <Object?>[
                <String, Object?>{
                  'id': 7,
                  'rating': 5,
                  'cloudBookId': 11,
                  'name': '云端书',
                  'ratingTime': 1794909600,
                  'totalReadTime': 7200,
                },
              ],
            },
          });
        }
        return _json(<String, Object?>{'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    final review = await api.fetchBookReview('token', cloudBookId: 11);
    final milestones = await api.fetchMilestones('token');
    await api.rateReview(
      'token',
      cloudBookId: 11,
      rating: 4,
      comment: '新的书评',
      publish: true,
    );
    await api.deleteMilestone('token', milestoneId: 7);

    expect(review?.comment, '旧书评');
    expect(milestones.single.name, '云端书');
    expect(milestones.single.totalReadTimeSeconds, 7200);
    expect(jsonDecode(requests[0].body), <String, Object?>{'cloudBookId': 11});
    expect(jsonDecode(requests[2].body), <String, Object?>{
      'cloudBookId': 11,
      'rating': 4,
      'comment': '新的书评',
      'status': 2,
    });
    expect(jsonDecode(requests[3].body), <String, Object?>{'milestoneId': 7});
  });

  test('读取云端 S3 配置、配额与积分流水', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('get-s3-sync-cloud-config')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'enabled': true,
              'encryptedConfig': 'ciphertext',
            },
          });
        }
        if (path.endsWith('get-storage-quota')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'capacityBytes': '1073741824',
              'capacityGib': '1',
              'credit': '9',
              'usedBytes': '268435456',
            },
          });
        }
        if (path.endsWith('credit-ledger')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'action': 'READ',
                  'amount': 2,
                  'balanceAfter': 9,
                  'objectKey': 'book.epub',
                  'operation': '阅读奖励',
                  'createTime': 1794909600,
                },
              ],
              'hasMore': true,
            },
          });
        }
        return _json(<String, Object?>{'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    final cloud = await api.fetchS3CloudConfig('token');
    final quota = await api.fetchStorageQuota('token');
    final ledger = await api.fetchCreditLedger('token', page: 2, pageSize: 5);
    await api.updateS3CloudConfig(
      'token',
      enabled: true,
      encryptedConfig: 'new-ciphertext',
    );

    expect(cloud.enabled, isTrue);
    expect(cloud.encryptedConfig, 'ciphertext');
    expect(quota.capacityGib, 1);
    expect(quota.usedBytes, 268435456);
    expect(quota.credit, 9);
    expect(ledger.hasMore, isTrue);
    expect(ledger.items.single.operation, '阅读奖励');
    expect(ledger.items.single.createTime, 1794909600000);
    expect(jsonDecode(requests[2].body), <String, Object?>{
      'page': 2,
      'pageSize': 5,
    });
    expect(jsonDecode(requests[3].body), <String, Object?>{
      'enabled': true,
      'encryptedConfig': 'new-ciphertext',
    });
  });

  test('读取完整阅读概览、周期统计与书籍记录', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('get-overview-read-duration')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'years': <Object?>[2025, 2026],
              'readDays': 42,
              'totalDuration': 7200,
              'bookCount': 8,
              'finishedBookCount': 3,
              'registerTimestamp': 1763380800,
              'topBooks': <Object?>[
                <String, Object?>{
                  'name': '常用书',
                  'duration': 1800,
                  'bookId': '8',
                  'readDays': 6,
                },
              ],
              'listeningDuration': 1200,
              'readingDuration': 6000,
            },
          });
        }
        if (path.endsWith('get-week-read-duration') ||
            path.endsWith('get-month-read-duration')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'days': <Object?>[
                <String, Object?>{
                  'day': 17,
                  'duration': 1800,
                  'readingDuration': 1500,
                  'listeningDuration': 300,
                },
              ],
              'readDays': 1,
              'totalDuration': 1800,
              'bookCount': 1,
              'finishedBookCount': 0,
              'continuousReadDays': 1,
              'avgDailyDuration': 1800,
            },
          });
        }
        if (path.endsWith('get-year-read-duration')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'months': <Object?>[
                <String, Object?>{
                  'month': 11,
                  'duration': 3600,
                  'readingDuration': 3000,
                  'listeningDuration': 600,
                },
              ],
              'readDays': 2,
              'totalDuration': 3600,
              'bookCount': 2,
              'finishedBookCount': 1,
              'continuousReadDays': 2,
              'avgDailyDuration': 1800,
            },
          });
        }
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'bookId': 8,
                'cloudBookId': 21,
                'name': '云端书',
                'author': '作者',
                'cover': 'https://example.test/cover.jpg',
                'progress': 0.3,
                'totalReadTime': 600,
                'readDays': 2,
                'finishReadTime': 0,
                'listeningDuration': 0,
                'readingDuration': 600,
              },
            ],
          },
        });
      }),
    );
    addTearDown(api.close);

    final overview = await api.fetchOverview('token');
    final week = await api.fetchWeekStats(
      'token',
      date: DateTime(2026, 11, 18),
    );
    final month = await api.fetchMonthStats('token', year: 2026, month: 11);
    final year = await api.fetchYearStats('token', year: 2026);
    final records = await api.fetchBookRecords('token');

    expect(overview.totalDurationSeconds, 7200);
    expect(overview.topBooks.single.name, '常用书');
    expect(week.days.single.day, 17);
    expect(month.days.single.durationSeconds, 1800);
    expect(year.months.single.month, 11);
    expect(records.single.cloudBookId, 21);
    expect(records.single.totalReadTimeSeconds, 600);

    final bodies = <String, Object?>{
      for (final request in requests)
        request.url.path.split('/').last: jsonDecode(request.body),
    };
    expect(bodies['get-week-read-duration'], <String, Object?>{
      'date': '2026-11-18',
    });
    expect(bodies['get-month-read-duration'], <String, Object?>{
      'year': 2026,
      'month': 11,
    });
    expect(bodies['get-year-read-duration'], <String, Object?>{'year': 2026});
    expect(bodies['get-read-record-list-by-all'], <String, Object?>{
      'pageNum': 1,
      'pageSize': 200,
    });
  });
}
