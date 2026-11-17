import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';

class _TestLibrary extends LibraryStore {
  _TestLibrary() : super.memory();

  final List<ReadingSession> sessions = <ReadingSession>[];
  late final _TestSessionStore sessionStore = _TestSessionStore(sessions);

  @override
  ReadingSessionStore? readingSessionStore() => sessionStore;
}

class _TestSessionStore implements ReadingSessionStore {
  _TestSessionStore(this.items);

  final List<ReadingSession> items;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {
    items.add(
      ReadingSession(
        bookId: bookId,
        startedAt: startedAt,
        endedAt: endedAt,
        duration: endedAt.difference(startedAt),
        pageTurns: pageTurns,
        charactersRead: charactersRead,
      ),
    );
  }

  @override
  Future<List<ReadingSession>> list() async => List<ReadingSession>.of(items);
}

class _FakeApi implements ReaMicroApi {
  _FakeApi({this.unauthorized = false});

  bool unauthorized;
  final List<List<ReaMicroReadTimeEntry>> uploads =
      <List<ReaMicroReadTimeEntry>>[];
  int userCalls = 0;

  @override
  Future<ReaMicroUser> fetchUser(String token) async {
    userCalls += 1;
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return const ReaMicroUser(
      id: 1,
      nickName: '测试用户',
      totalReadTimeSeconds: 600,
    );
  }

  @override
  Future<List<ReaMicroChartPoint>> fetchReadTimeChart(
    String token, {
    int limit = 30,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return const <ReaMicroChartPoint>[];
  }

  @override
  Future<String> loginWithEmail({
    required String email,
    required String code,
  }) async => 'fake-token';

  @override
  Future<ReaMicroCloudBook?> searchCloudBook(
    String token, {
    required String name,
    String author = '',
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return ReaMicroCloudBook(cloudBookId: 99, name: name, author: author);
  }

  @override
  Future<void> sendEmailCode(String email) async {}

  @override
  Future<void> updateReadTimeByDate(
    String token,
    List<ReaMicroReadTimeEntry> entries,
  ) async {
    uploads.add(List<ReaMicroReadTimeEntry>.of(entries));
  }

  @override
  void close() {}
}

ReadingSession _session(DateTime start, DateTime end) => ReadingSession(
  bookId: 'book-a',
  startedAt: start,
  endedAt: end,
  duration: end.difference(start),
);

Future<ReaMicroController> _createController(
  _TestLibrary library,
  _FakeApi api, {
  bool signedIn = true,
}) async {
  if (signedIn) {
    await ReaMicroStore(library).saveToken('token');
  }
  final controller = ReaMicroController(library: library, api: api);
  await controller.initialize();
  return controller;
}

void main() {
  test('北京时间跨午夜会话按自然日拆分', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );

    // UTC 15:30 / 16:30 对应北京时间 23:30 / 次日 00:30。
    library.sessions.add(
      _session(
        DateTime.utc(2026, 11, 16, 15, 30),
        DateTime.utc(2026, 11, 16, 16, 30),
      ),
    );

    final result = await controller.syncReadingSessions();

    expect(result.success, isTrue);
    expect(result.requests, 2);
    expect(result.durationSeconds, 3600);
    expect(api.uploads.length, 2);
    final byDate = <String, int>{
      for (final upload in api.uploads)
        for (final entry in upload) entry.date: entry.durationSeconds,
    };
    expect(byDate, <String, int>{'2026-11-16': 1800, '2026-11-17': 1800});
  });

  test('同一本书同一天聚合，重复同步不重复上报', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    library.sessions
      ..add(
        _session(
          DateTime.utc(2026, 11, 17, 1),
          DateTime.utc(2026, 11, 17, 1, 10),
        ),
      )
      ..add(
        _session(
          DateTime.utc(2026, 11, 17, 2),
          DateTime.utc(2026, 11, 17, 2, 5),
        ),
      );

    final first = await controller.syncReadingSessions();
    expect(first.requests, 1);
    expect(api.uploads.single.single.durationSeconds, 900);
    expect(api.uploads.single.single.date, '2026-11-17');

    final second = await controller.syncReadingSessions();
    expect(second.success, isTrue);
    expect(second.requests, 0);
    expect(api.uploads, hasLength(1));
  });

  test('重新创建控制器后水位阻止旧会话重复上报', () async {
    final library = _TestLibrary();
    final firstApi = _FakeApi();
    final first = await _createController(library, firstApi);
    await first.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    library.sessions.add(
      _session(
        DateTime.utc(2026, 11, 17, 1),
        DateTime.utc(2026, 11, 17, 1, 30),
      ),
    );
    expect((await first.syncReadingSessions()).requests, 1);
    first.dispose();

    final secondApi = _FakeApi();
    final second = await _createController(library, secondApi);
    addTearDown(second.dispose);
    final result = await second.syncReadingSessions();

    expect(result.requests, 0);
    expect(secondApi.uploads, isEmpty);
  });

  test('新增会话只上报增量', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    library.sessions.add(
      _session(
        DateTime.utc(2026, 11, 17, 1),
        DateTime.utc(2026, 11, 17, 1, 10),
      ),
    );
    await controller.syncReadingSessions();

    library.sessions.add(
      _session(DateTime.utc(2026, 11, 17, 2), DateTime.utc(2026, 11, 17, 2, 7)),
    );
    final result = await controller.syncReadingSessions();

    expect(result.requests, 1);
    expect(result.durationSeconds, 420);
    expect(api.uploads.last.single.durationSeconds, 420);
  });

  test('401 清除登录令牌', () async {
    final library = _TestLibrary();
    final api = _FakeApi(unauthorized: true);
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    expect(controller.signedIn, isFalse);
    expect(controller.user, isNull);
    expect(await ReaMicroStore(library).loadToken(), isNull);
    expect(controller.error, contains('登录已失效'));
  });

  test('关联与解除关联写入本地设置', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书', author: '作者'),
    );

    expect(controller.links['book-a']?.cloudBookId, 11);
    expect((await ReaMicroStore(library).loadLinks())['book-a']?.name, '云端书');

    await controller.unlinkBook('book-a');

    expect(controller.links, isEmpty);
    expect(await ReaMicroStore(library).loadLinks(), isEmpty);
  });

  test('云端搜索触发 401 时清除登录令牌', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    api.unauthorized = true;

    await expectLater(
      controller.searchCloudBook(name: '云端书'),
      throwsA(isA<ReaMicroException>()),
    );

    expect(controller.signedIn, isFalse);
    expect(await ReaMicroStore(library).loadToken(), isNull);
  });
}
