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
  test('阅微书库搜索保留书目与出版版本的封面简介及字数', () async {
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient(
        (_) async => _json({
          'code': 0,
          'data': [
            {
              'cloudBookId': 42,
              'name': '示例书籍',
              'author': '示例作者',
              'cover': 'https://example.test/book.jpg',
              'intro': '书目简介',
              'wordCount': 123456,
              'status': '连载',
              'bookPublishers': [
                {
                  'bookPublisherId': 88,
                  'publisher': '示例平台',
                  'cover': 'https://example.test/version.jpg',
                  'intro': '版本简介',
                  'wordCount': '32.1万',
                  'status': '完结',
                },
              ],
            },
          ],
        }),
      ),
    );
    addTearDown(api.close);
    final book = (await api.searchCloudBooks('test', name: '示例书籍')).single;
    expect(book.cover, 'https://example.test/book.jpg');
    expect(book.words, '123456字');
    final candidate = ReaMicroPublicReadingCandidate(
      book: book,
      publisher: book.publishers.single,
    );
    expect(candidate.cover, 'https://example.test/version.jpg');
    expect(candidate.intro, '版本简介');
    expect(candidate.words, '32.1万');
    expect(candidate.status, '完结');
  });
  test('原生平台规则目录和 JS 下载使用正确接口，完整字段传入出版创建', () async {
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        if (request.url.path.endsWith('query-third-party')) {
          expect(request.method, 'POST');
          return _json({
            'code': 0,
            'data': {
              'files': ['ciweimao_1', 'douban_4'],
            },
          });
        }
        if (request.url.path.endsWith('download-third-party')) {
          expect(request.method, 'GET');
          expect(request.url.queryParameters, {'name': 'ciweimao_1'});
          return http.Response('function search(key){}', 200);
        }
        final body = jsonDecode(request.body) as Map;
        expect(body['original'], '原名');
        expect(body['translator'], '译者');
        expect(body['bookAlias'], '别名');
        return _json({
          'code': 0,
          'data': {'cloudBookId': 42, 'bookPublisherId': 88},
        });
      }),
    );
    addTearDown(api.close);
    expect(await api.fetchThirdPartyRuleNames('token'), [
      'ciweimao_1',
      'douban_4',
    ]);
    expect(
      await api.downloadThirdPartyRule('token', 'ciweimao_1'),
      contains('function search'),
    );
    await api.createCloudBook(
      'token',
      name: '书',
      author: '作者',
      original: '原名',
      translator: '译者',
      bookAlias: '别名',
    );
  });

  test('书籍记录按服务实际二十条分页读取后续页，保留最近顺序', () async {
    final pages = <int>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['pageSize'], 20);
        final page = body['pageNum'] as int;
        pages.add(page);
        return _json({
          'code': 0,
          'data': {
            'list': List.generate(
              page == 1 ? 20 : 3,
              (index) => {'bookId': (page - 1) * 20 + index + 1},
            ),
          },
        });
      }),
    );
    addTearDown(api.close);
    final records = await api.fetchBookRecords('token');
    expect(pages, [1, 2]);
    expect(
      records.map((book) => book.bookId),
      List.generate(23, (index) => index + 1),
    );
  });

  test('书籍分页未读完时拒绝返回不完整清单', () async {
    var pages = 0;
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        pages++;
        return _json({
          'code': 0,
          'data': {
            'list': List.generate(
              20,
              (index) => {'bookId': pages * 20 + index},
            ),
          },
        });
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchBookRecords('token'),
      throwsA(isA<ReaMicroException>()),
    );
    expect(pages, 250);
  });

  test('会话记账沿用正式接口并排除会被服务器拒绝的旧式增量', () async {
    final paths = <String>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        paths.add(request.url.path);
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['sessionAccounting'], isTrue);
        expect(body.containsKey('list'), isFalse);
        return _json({
          'code': 0,
          'data': {'sessionAccountingSupported': true},
        });
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.updateReadTimeByDate(
        'token',
        const [
          ReaMicroReadTimeEntry(
            cloudBookId: 7001,
            date: '2026-11-20',
            durationSeconds: 1,
          ),
        ],
        sessionLogs: const [
          ReaMicroReadSessionLog(
            id: 'stable-session',
            cloudBookId: 7001,
            startedAt: 1,
            endedAt: 1001,
            durationSeconds: 1,
            recordDay: '2026-11-20',
          ),
        ],
        sessionAccounting: true,
      ),
      completes,
    );
    expect(paths, ['/rest/reader/update-read-time-by-date']);
  });

  test('会话记账未获服务器确认时失败并保留待重试语义', () async {
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        expect(request.url.path, '/rest/reader/update-read-time-by-date');
        return _json({
          'code': 0,
          'data': {'sessionAccountingSupported': false},
        });
      }),
    );
    addTearDown(api.close);

    await expectLater(
      api.updateReadTimeByDate(
        'token',
        const <ReaMicroReadTimeEntry>[
          ReaMicroReadTimeEntry(
            cloudBookId: 7001,
            date: '2026-11-20',
            durationSeconds: 60,
          ),
        ],
        sessionLogs: const <ReaMicroReadSessionLog>[
          ReaMicroReadSessionLog(
            id: 'stable-session',
            cloudBookId: 7001,
            startedAt: 1763596800000,
            endedAt: 1763596860000,
            durationSeconds: 60,
            recordDay: '2026-11-20',
          ),
        ],
        sessionAccounting: true,
      ),
      throwsA(isA<ReaMicroException>()),
    );
  });

  test('不启用会话记账的按日时长兼容阅微原有布尔响应', () async {
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body.containsKey('sessionAccounting'), isFalse);
        expect(body.containsKey('sessionLogs'), isFalse);
        expect(body['list'], hasLength(1));
        return _json({'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    await expectLater(
      api.updateReadTimeByDate('token', const <ReaMicroReadTimeEntry>[
        ReaMicroReadTimeEntry(
          cloudBookId: 0,
          date: '2026-11-20',
          durationSeconds: 60,
        ),
      ]),
      completes,
    );
  });

  test('标注分页达到上限仍未读完时拒绝返回不完整清单', () async {
    var pages = 0;
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        pages += 1;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['pageNum'], pages);
        return _json({
          'code': 0,
          'data': {
            'list': [
              {'id': pages, 'startCfi': 'epubcfi(/6/4!/4/2/1)'},
            ],
          },
        });
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchMarks('token', pageSize: 1),
      throwsA(isA<ReaMicroException>()),
    );
    expect(pages, 50);
  });

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
    Future<List<ReaMicroCloudBook>> search(Object data) async {
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
      return api.searchCloudBooks('token', name: '书名', author: '作者');
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
      final results = await search(data);
      expect(results, hasLength(1));
      expect(results.single.cloudBookId, 42);
      expect(results.single.name, '云端书名');
      expect(results.single.publisherNames, <String>['出版社', '出版方']);
    }
  });

  test('云端书籍登记、补全与关联使用阅微 2.3.4 接口字段', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('get-cloud-info')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'cloudBookId': 42,
              'name': '云端书名',
              'author': '云端作者',
              'subtitle': '副标题',
              'original': '原作名',
              'bookPublishers': <Object?>[
                <String, Object?>{'bookPublisherId': 88, 'publisher': '出版社'},
              ],
            },
          });
        }
        if (path.endsWith('get-cloud-info-by-i-d')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{'cloudBookId': 42, 'name': '按出版方查询'},
          });
        }
        if (path.endsWith('post-user-book')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'id': 7001,
              'cloudBookID': 42,
              'bookPublisherId': 88,
              'publisher': '出版社',
            },
          });
        }
        if (path.endsWith('post-cloud-book')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{'cloudBookId': 43, 'bookPublisherId': 89},
          });
        }
        return _json(<String, Object?>{'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    final info = await api.fetchCloudBookInfo('token', bookId: 42);
    final byPublisher = await api.fetchCloudBookInfo(
      'token',
      bookId: 88,
      byPublisherId: true,
    );
    final registered = await api.registerUserBook(
      'token',
      name: '本地书名',
      author: '本地作者',
      md5: 'abc123',
    );
    final created = await api.createCloudBook(
      'token',
      name: '新书',
      author: '作者',
      intro: '简介',
      publisher: '起点中文网',
      wordCount: '10万',
      status: '完结',
      cover: 'https://example.com/cover.png',
    );
    await api.relateCloudBook(
      'token',
      userBookId: registered.userBookId,
      publisherId: registered.publisherId,
    );

    expect(info?.cloudBookId, 42);
    expect(info?.name, '云端书名');
    expect(info?.author, '云端作者');
    expect(info?.subtitle, '副标题');
    expect(info?.original, '原作名');
    expect(info?.linkablePublisher?.publisherId, 88);
    expect(info?.publisherNames, <String>['出版社']);
    expect(byPublisher?.name, '按出版方查询');
    expect(registered.userBookId, 7001);
    expect(registered.cloudBookId, 42);
    expect(registered.publisherId, 88);
    expect(registered.publisher, '出版社');
    expect(created.cloudBookId, 43);
    expect(created.publisherId, 89);
    expect(jsonDecode(requests[0].body), <String, Object?>{'bookId': 42});
    expect(jsonDecode(requests[1].body), <String, Object?>{'bookId': 88});
    expect(jsonDecode(requests[2].body), <String, Object?>{
      'name': '本地书名',
      'author': '本地作者',
      'md5': 'abc123',
      'cover': '',
      'coverMd5': '',
    });
    expect(jsonDecode(requests[3].body), containsPair('name', '新书'));
    expect(jsonDecode(requests[3].body), containsPair('intro', '简介'));
    expect(jsonDecode(requests[3].body), containsPair('publisher', '起点中文网'));
    expect(jsonDecode(requests[3].body), containsPair('wordCount', '10万'));
    expect(jsonDecode(requests[3].body), containsPair('status', '完结'));
    expect(
      jsonDecode(requests[3].body),
      containsPair('cover', 'https://example.com/cover.png'),
    );
    expect(jsonDecode(requests[4].body), <String, Object?>{
      'userBookId': 7001,
      'bookPublisherId': 88,
    });
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

  test('首次进度不存在时继续上传本地位置，其他业务错误保持失败', () async {
    var missing = true;
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('get-read-progress')) {
          return _json({
            'code': 2,
            'message': missing ? 'record not found' : 'book permission denied',
          });
        }
        return _json({'code': 0});
      }),
    );
    addTearDown(api.close);
    expect(await api.fetchReadProgress('test', cloudBookId: '47560'), isNull);
    await api.updateReadProgress(
      'test',
      cloudBookId: 47560,
      cfi: 'epubcfi(/6/4!/4/2/1)',
      chapterName: '第二章',
      progress: .25,
    );
    expect(requests.last.url.path, '/rest/reader/update-read-progress');
    final uploaded = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(uploaded['bookId'], 47560);
    missing = false;
    await expectLater(
      api.fetchReadProgress('test', cloudBookId: '47560'),
      throwsA(isA<ReaMicroException>()),
    );
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
        if (path.endsWith('expand-storage-quota')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'capacityBytes': '2147483648',
              'capacityGib': '2',
              'credit': '0',
              'usedBytes': '268435456',
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
    final expanded = await api.expandStorageQuota('token', credit: 60);

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
    expect(expanded.capacityGib, 2);
    expect(jsonDecode(requests[4].body), <String, Object?>{'credit': 60});
  });

  test('阅微内置对象存储签发上传下载地址并读取对象状态', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('head-object')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'exists': true,
              'contentLength': 12,
              'etag': '"etag-1"',
            },
          });
        }
        if (path.endsWith('get-upload-url') ||
            path.endsWith('get-download-url')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'url': 'https://storage.test/signed-object',
            },
          });
        }
        return _json(<String, Object?>{'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    final head = await api.fetchMoteHead('token', objectKey: 'sync/book.epub');
    final upload = await api.fetchMoteUploadUrl(
      'token',
      objectKey: 'sync/book.epub',
      contentLength: 12,
      ifMatch: '"old"',
      ifNoneMatch: true,
    );
    await api.confirmMoteUpload(
      'token',
      objectKey: 'sync/book.epub',
      contentLength: 12,
    );
    final download = await api.fetchMoteDownloadUrl(
      'token',
      objectKey: 'sync/book.epub',
    );
    await api.deleteMoteObject('token', objectKey: 'sync/book.epub');

    expect(head.exists, isTrue);
    expect(head.contentLength, 12);
    expect(head.etag, '"etag-1"');
    expect(upload.url, 'https://storage.test/signed-object');
    expect(download.url, 'https://storage.test/signed-object');
    expect(jsonDecode(requests[0].body), <String, Object?>{
      'objectKey': 'sync/book.epub',
    });
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'objectKey': 'sync/book.epub',
      'ifMatch': '"old"',
      'ifNoneMatch': true,
      'contentLength': 12,
    });
    expect(jsonDecode(requests[2].body), <String, Object?>{
      'objectKey': 'sync/book.epub',
      'contentLength': 12,
    });
    expect(jsonDecode(requests[4].body), <String, Object?>{
      'objectKey': 'sync/book.epub',
    });
    for (final request in requests) {
      expect(request.headers['Authorization'], 'Bearer token');
    }
  });

  test('读取阅微离线朗读引擎与官方音色目录', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        return _json(<String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'engines': <Object?>[
              <String, Object?>{
                'platform': 'android',
                'abi': 'arm64-v8a',
                'version': '1.13.8',
                'downloadUrl': 'https://example.test/engine.zip',
                'sha256': 'abc',
                'size': 123,
              },
            ],
            'voices': <Object?>[
              <String, Object?>{
                'id': 'vits-piper-zh_CN-chaowen-medium',
                'downloadUrl': 'https://example.test/voice.tar.bz2',
              },
            ],
          },
        });
      }),
    );
    addTearDown(api.close);

    final catalog = await api.fetchTtsVoices('token');

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, endsWith('rest/tts/voices'));
    expect(requests.single.headers['Authorization'], 'Bearer token');
    expect(catalog.engines.single.abi, 'arm64-v8a');
    expect(catalog.engines.single.size, 123);
    expect(catalog.voices.single.id, 'vits-piper-zh_CN-chaowen-medium');
    expect(
      catalog.voices.single.displayName,
      'vits-piper-zh_CN-chaowen-medium',
    );
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
              'years': <Object?>[
                <String, Object?>{'year': 2025, 'duration': '10'},
                <String, Object?>{'year': 2026, 'duration': '20'},
              ],
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
    expect(overview.years, <int>[2025, 2026]);
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
      'pageSize': 20,
    });
  });

  test('读取周期记录、标注书籍并提交书评互动', () async {
    final requests = <http.Request>[];
    final api = ReaMicroApiClient(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('get-mark-book-list')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'bookId': '8',
                  'cloudBookId': '21',
                  'bookName': '有标注的书',
                  'bookAuthor': '作者',
                  'bookCover': 'https://example.test/cover.jpg',
                  'thoughtCount': 2,
                  'underlineCount': 3,
                },
              ],
            },
          });
        }
        if (path.endsWith('check-review-action')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'actionTypes': <Object?>[0],
            },
          });
        }
        if (path.endsWith('get-review-actors')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'items': <Object?>[
                <String, Object?>{
                  'userId': '2',
                  'userName': '点赞用户',
                  'actedAt': '1763380800000',
                  'actionType': 0,
                },
              ],
              'total': '1',
            },
          });
        }
        if (path.endsWith('get-review-flow-v2')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'reviews': <Object?>[
                <String, Object?>{
                  'id': '9',
                  'rating': 9,
                  'comment': '很好看',
                  'bookName': '有标注的书',
                  'userName': '书评用户',
                },
              ],
            },
          });
        }
        if (path.contains('get-read-record-list-by-')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'bookId': '8',
                  'cloudBookId': '21',
                  'name': '有标注的书',
                  'author': '作者',
                  'progress': 51.66,
                  'totalReadTime': '600',
                  'readDays': 2,
                  'readingDuration': '600',
                  'listeningDuration': '0',
                },
              ],
            },
          });
        }
        if (path.endsWith('update-read-time-by-date')) {
          return _json(<String, Object?>{
            'code': 0,
            'data': <String, Object?>{'sessionAccountingSupported': true},
          });
        }
        return _json(<String, Object?>{'code': 0, 'data': true});
      }),
    );
    addTearDown(api.close);

    final week = await api.fetchBookRecordsByWeek(
      'token',
      date: DateTime(2026, 11, 18),
    );
    final month = await api.fetchBookRecordsByMonth(
      'token',
      year: 2026,
      month: 11,
    );
    final year = await api.fetchBookRecordsByYear('token', year: 2026);
    final markBooks = await api.fetchMarkBooks('token');
    final action = await api.checkReviewAction('token', reviewId: 9);
    final actors = await api.fetchReviewActors('token', reviewId: 9);
    final flow = await api.fetchReviewFlow('token', cloudBookId: 21);
    await api.actReview('token', reviewId: 9);
    await api.unactReview('token', reviewId: 9);
    await api.hideBookRecord('token', bookId: 8);
    await api.updateReadTimeByDate(
      'token',
      const <ReaMicroReadTimeEntry>[
        ReaMicroReadTimeEntry(
          cloudBookId: 21,
          date: '2026-11-18',
          durationSeconds: 60,
        ),
      ],
      sessionLogs: const <ReaMicroReadSessionLog>[
        ReaMicroReadSessionLog(
          id: 'session-1',
          cloudBookId: 21,
          startedAt: 1763380800000,
          endedAt: 1763380860000,
          durationSeconds: 60,
          recordDay: '2026-11-18',
        ),
      ],
      sessionAccounting: true,
    );

    expect(week.single.progress, closeTo(0.5166, 0.0001));
    expect(month.single.totalReadTimeSeconds, 600);
    expect(year.single.cloudBookId, 21);
    expect(markBooks.single.markCount, 5);
    expect(action.liked, isTrue);
    expect(actors.total, 1);
    expect(actors.items.single.userName, '点赞用户');
    expect(flow.single.rating, 9);
    expect(flow.single.comment, '很好看');

    final bodies = <String, Object?>{
      for (final request in requests)
        request.url.path.split('/').last: jsonDecode(request.body),
    };
    expect(bodies['get-read-record-list-by-week'], <String, Object?>{
      'date': '2026-11-18',
      'pageNum': 1,
      'pageSize': 20,
    });
    expect(bodies['get-read-record-list-by-month'], <String, Object?>{
      'year': 2026,
      'month': 11,
      'pageNum': 1,
      'pageSize': 20,
    });
    expect(bodies['get-read-record-list-by-year'], <String, Object?>{
      'year': 2026,
      'pageNum': 1,
      'pageSize': 20,
    });
    expect(bodies['act-review'], <String, Object?>{
      'reviewId': 9,
      'actionType': 0,
    });
    expect(bodies['unact-review'], <String, Object?>{
      'reviewId': 9,
      'actionType': 0,
    });
    expect(bodies['hide-read-record'], <String, Object?>{'bookId': 8});
    final update = bodies['update-read-time-by-date']! as Map<String, Object?>;
    expect(update['sessionAccounting'], isTrue);
    expect(update.containsKey('list'), isFalse);
    expect((update['sessionLogs']! as List<Object?>).single, <String, Object?>{
      'id': 'session-1',
      'bookId': 21,
      'startedAt': 1763380800000,
      'endedAt': 1763380860000,
      'duration': 60,
      'listening': false,
      'recordDay': '2026-11-18',
    });
  });
}
