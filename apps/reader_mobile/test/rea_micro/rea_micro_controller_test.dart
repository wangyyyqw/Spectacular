import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

class _TestLibrary extends LibraryStore {
  _TestLibrary() : super.memory();

  final List<ReadingSession> sessions = <ReadingSession>[];
  BookEntry? book;
  late final _TestSessionStore sessionStore = _TestSessionStore(sessions);

  @override
  ReadingSessionStore? readingSessionStore() => sessionStore;

  @override
  Future<BookEntry?> bookById(String id) async {
    final value = book;
    if (value != null && value.id == id) return value;
    return super.bookById(id);
  }

  @override
  Future<List<BookEntry>> list() async {
    final value = book;
    return value == null ? super.list() : <BookEntry>[value];
  }
}

class _DbTestLibrary extends LibraryStore {
  _DbTestLibrary(AppDatabase db, Directory dir)
    : super(database: db, directoryProvider: () async => dir);

  late final _TestSessionStore sessionStore = _TestSessionStore(
    <ReadingSession>[],
  );

  @override
  ReadingSessionStore? readingSessionStore() => sessionStore;
}

Future<_DbTestLibrary> _openDbLibrary() async {
  final dir = Directory.systemTemp.createTempSync('rea-marks');
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return _DbTestLibrary(db, dir);
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

class _MemoryProgressStore implements ReaderProgressStore {
  final Map<String, ReaderProgress> items = <String, ReaderProgress>{};

  @override
  Future<ReaderProgress?> load(String bookId) async => items[bookId];

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    items[bookId] = progress;
  }

  @override
  Future<void> clear(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async => Map.of(items);
}

class _FakeLan extends ReaMicroLanClient {
  _FakeLan(this.manifest, {this.archive, this.archives});

  final ReaMicroLanManifest manifest;
  final List<int>? archive;
  final List<List<int>>? archives;
  int downloadCalls = 0;

  @override
  Future<ReaMicroLanManifest> fetchManifest(ReaMicroLanSyncPeer peer) async {
    return manifest;
  }

  @override
  Future<Uint8List> downloadBookArchive(
    ReaMicroLanSyncPeer peer,
    ReaMicroLanBookProgress book,
  ) async {
    final queue = archives;
    if (queue != null && queue.isNotEmpty) {
      final index = downloadCalls < queue.length
          ? downloadCalls
          : queue.length - 1;
      downloadCalls += 1;
      return Uint8List.fromList(queue[index]);
    }
    downloadCalls += 1;
    return Uint8List.fromList(archive!);
  }
}

class _MemoryS3 implements ReaMicroS3Client {
  final Map<String, ReaMicroS3Object> objects = <String, ReaMicroS3Object>{};
  int puts = 0;

  @override
  Future<ReaMicroS3Object?> get(String key) async => objects[key];

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final existing = objects[key];
    if (ifNoneMatch == '*' && existing != null) {
      throw const ReaMicroS3ConflictException('对象已存在');
    }
    if (ifMatch != null && existing?.etag != ifMatch) {
      throw const ReaMicroS3ConflictException('ETag 不匹配');
    }
    puts += 1;
    final etag = '"$puts"';
    objects[key] = ReaMicroS3Object(bytes: bytes, etag: etag);
    return etag;
  }

  @override
  Future<void> delete(String key) async {
    objects.remove(key);
  }
}

class _FakeApi implements ReaMicroApi {
  _FakeApi({this.unauthorized = false});

  bool unauthorized;
  final List<List<ReaMicroReadTimeEntry>> uploads =
      <List<ReaMicroReadTimeEntry>>[];
  final List<List<ReaMicroReadSessionLog>> sessionLogUploads =
      <List<ReaMicroReadSessionLog>>[];
  final List<_ProgressUpload> progressUploads = <_ProgressUpload>[];
  ReaMicroReadProgress? remoteProgress;
  final List<Map<String, Object?>> userBookRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> cloudBookRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> relateRequests = <Map<String, Object?>>[];
  ReaMicroCloudBook? cloudBookInfo;
  int cloudBookInfoCalls = 0;
  int nextUserBookId = 7001;
  int nextCloudBookId = 8001;
  int nextPublisherId = 9001;
  int userCalls = 0;
  int recordCalls = 0;
  List<ReaMicroMark> marks = <ReaMicroMark>[];
  final List<ReaMicroMarkDraft> markUpserts = <ReaMicroMarkDraft>[];
  final List<int> markDeletes = <int>[];
  int nextMarkId = 500;
  ReaMicroBookReview? bookReview;
  List<ReaMicroMilestone> milestones = <ReaMicroMilestone>[];
  final List<_ReviewUpload> reviewUploads = <_ReviewUpload>[];
  final List<int> deletedMilestones = <int>[];
  ReaMicroOverview overview = const ReaMicroOverview(
    years: <int>[],
    readDays: 0,
    totalDurationSeconds: 0,
    bookCount: 0,
    finishedBookCount: 0,
    registerTimestamp: 0,
    topBooks: <ReaMicroTopBook>[],
    listeningDurationSeconds: 0,
    readingDurationSeconds: 0,
  );
  ReaMicroS3CloudConfigResponse s3CloudConfig =
      const ReaMicroS3CloudConfigResponse(enabled: false, encryptedConfig: '');
  ReaMicroStorageQuota storageQuota = const ReaMicroStorageQuota(
    capacityBytes: 1073741824,
    capacityGib: 1,
    credit: 0,
    usedBytes: 0,
  );
  ReaMicroCreditLedgerPage creditLedger = const ReaMicroCreditLedgerPage(
    items: <ReaMicroCreditLedgerItem>[],
    hasMore: false,
  );
  ReaMicroTtsCatalog ttsCatalog = const ReaMicroTtsCatalog(
    engines: <ReaMicroTtsEngine>[],
    voices: <ReaMicroTtsVoice>[],
  );
  final List<ReaMicroS3Config> cloudS3Uploads = <ReaMicroS3Config>[];
  final List<int> expandedCredits = <int>[];
  bool cloudS3Enabled = false;
  ReaMicroPeriodStats period = const ReaMicroPeriodStats(
    days: <ReaMicroDayDuration>[],
    months: <ReaMicroMonthDuration>[],
    readDays: 0,
    totalDurationSeconds: 0,
    bookCount: 0,
    finishedBookCount: 0,
    continuousReadDays: 0,
    averageDailyDurationSeconds: 0,
    topBooks: <ReaMicroTopBook>[],
    listeningDurationSeconds: 0,
    readingDurationSeconds: 0,
  );
  List<ReaMicroBookRecord> bookRecords = <ReaMicroBookRecord>[];
  List<ReaMicroMarkBook> markBooks = <ReaMicroMarkBook>[];
  List<ReaMicroBookRecord> periodRecords = <ReaMicroBookRecord>[];
  final List<int> hiddenBookIds = <int>[];
  Set<int> actionTypes = <int>{};
  List<ReaMicroReviewActor> reviewActors = <ReaMicroReviewActor>[];
  int reviewActorTotal = 0;
  List<ReaMicroBookReview> reviewFlow = <ReaMicroBookReview>[];
  final List<bool> reviewActions = <bool>[];

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
  Future<ReaMicroOverview> fetchOverview(String token) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return overview;
  }

  @override
  Future<ReaMicroPeriodStats> fetchWeekStats(
    String token, {
    DateTime? date,
  }) async => period;

  @override
  Future<ReaMicroPeriodStats> fetchMonthStats(
    String token, {
    int? year,
    int? month,
  }) async => period;

  @override
  Future<ReaMicroPeriodStats> fetchYearStats(String token, {int? year}) async =>
      period;

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecords(String token) async {
    recordCalls += 1;
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return bookRecords;
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
  Future<ReaMicroCloudBook?> fetchCloudBookInfo(
    String token, {
    required int bookId,
    bool byPublisherId = false,
  }) async {
    cloudBookInfoCalls += 1;
    return cloudBookInfo ??
        ReaMicroCloudBook(
          cloudBookId: byPublisherId ? 0 : bookId,
          name: '云端书籍',
        );
  }

  @override
  Future<ReaMicroUserBookRegistration> registerUserBook(
    String token, {
    required String name,
    required String author,
    required String md5,
    String cover = '',
    String coverMd5 = '',
  }) async {
    userBookRequests.add(<String, Object?>{
      'name': name,
      'author': author,
      'md5': md5,
      'cover': cover,
      'coverMd5': coverMd5,
    });
    return ReaMicroUserBookRegistration(userBookId: nextUserBookId++);
  }

  @override
  Future<ReaMicroCloudBookRegistration> createCloudBook(
    String token, {
    required String name,
    required String author,
    String subtitle = '',
    String intro = '',
    String publisher = '',
    String isbn = '',
    String publishDate = '',
    String price = '',
  }) async {
    cloudBookRequests.add(<String, Object?>{
      'name': name,
      'author': author,
      'intro': intro,
    });
    return ReaMicroCloudBookRegistration(
      cloudBookId: nextCloudBookId++,
      publisherId: nextPublisherId++,
    );
  }

  @override
  Future<void> relateCloudBook(
    String token, {
    required int userBookId,
    required int publisherId,
  }) async {
    relateRequests.add(<String, Object?>{
      'userBookId': userBookId,
      'bookPublisherId': publisherId,
    });
  }

  @override
  Future<void> sendEmailCode(String email) async {}

  @override
  Future<void> updateReadTimeByDate(
    String token,
    List<ReaMicroReadTimeEntry> entries, {
    List<ReaMicroReadSessionLog> sessionLogs = const <ReaMicroReadSessionLog>[],
    bool sessionAccounting = false,
  }) async {
    uploads.add(List<ReaMicroReadTimeEntry>.of(entries));
    sessionLogUploads.add(List<ReaMicroReadSessionLog>.of(sessionLogs));
  }

  @override
  Future<void> updateReadProgress(
    String token, {
    required int cloudBookId,
    required String cfi,
    required String chapterName,
    required double progress,
  }) async {
    progressUploads.add(
      _ProgressUpload(
        cloudBookId: cloudBookId,
        cfi: cfi,
        chapterName: chapterName,
        progress: progress,
      ),
    );
  }

  @override
  Future<ReaMicroReadProgress?> fetchReadProgress(
    String token, {
    required String cloudBookId,
  }) async => remoteProgress;

  @override
  Future<List<ReaMicroMark>> fetchMarks(
    String token, {
    String? bookId,
    int pageSize = 200,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    if (bookId == null || bookId.trim().isEmpty) {
      return List<ReaMicroMark>.of(marks);
    }
    return <ReaMicroMark>[
      for (final mark in marks)
        if (mark.bookId == bookId) mark,
    ];
  }

  @override
  Future<int?> upsertMark(String token, ReaMicroMarkDraft mark) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    markUpserts.add(mark);
    if (mark.cloudId > 0) return mark.cloudId;
    final id = nextMarkId++;
    marks.add(
      ReaMicroMark(
        id: id,
        bookId: mark.bookId,
        chapter: mark.chapter,
        kind: mark.kind,
        startCfi: mark.startCfi,
        endCfi: mark.endCfi,
        quote: mark.quote,
        note: mark.note,
        style: mark.style,
        color: mark.color,
        synced: 1,
        createdAt: mark.createdAt,
        updatedAt: mark.updatedAt,
      ),
    );
    return id;
  }

  @override
  Future<void> deleteMark(String token, {required int id}) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    markDeletes.add(id);
    marks.removeWhere((mark) => mark.id == id);
  }

  @override
  Future<ReaMicroBookReview?> fetchBookReview(
    String token, {
    int? bookId,
    int? cloudBookId,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return bookReview;
  }

  @override
  Future<void> rateReview(
    String token, {
    int? bookId,
    int? cloudBookId,
    required int rating,
    required String comment,
    required bool publish,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    reviewUploads.add(
      _ReviewUpload(
        cloudBookId: cloudBookId ?? 0,
        rating: rating,
        comment: comment,
        publish: publish,
      ),
    );
  }

  @override
  Future<List<ReaMicroMilestone>> fetchMilestones(
    String token, {
    int pageSize = 100,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return List<ReaMicroMilestone>.of(milestones);
  }

  @override
  Future<ReaMicroS3CloudConfigResponse> fetchS3CloudConfig(String token) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return s3CloudConfig;
  }

  @override
  Future<void> updateS3CloudConfig(
    String token, {
    required bool enabled,
    required String encryptedConfig,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    cloudS3Enabled = enabled;
    if (enabled) {
      final config = ReaMicroS3ConfigCrypto.decrypt(encryptedConfig, 1);
      if (config != null) cloudS3Uploads.add(config);
    }
  }

  @override
  Future<ReaMicroStorageQuota> fetchStorageQuota(String token) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return storageQuota;
  }

  @override
  Future<ReaMicroStorageQuota> expandStorageQuota(
    String token, {
    required int credit,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    expandedCredits.add(credit);
    storageQuota = ReaMicroStorageQuota(
      capacityBytes: storageQuota.capacityBytes + (credit ~/ 60) * 1073741824,
      capacityGib: storageQuota.capacityGib + credit ~/ 60,
      credit: storageQuota.credit - credit,
      usedBytes: storageQuota.usedBytes,
    );
    return storageQuota;
  }

  @override
  Future<ReaMicroCreditLedgerPage> fetchCreditLedger(
    String token, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return creditLedger;
  }

  @override
  Future<ReaMicroTtsCatalog> fetchTtsVoices(String token) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return ttsCatalog;
  }

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByWeek(
    String token, {
    DateTime? date,
  }) async => List<ReaMicroBookRecord>.of(periodRecords);

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByMonth(
    String token, {
    int? year,
    int? month,
  }) async => List<ReaMicroBookRecord>.of(periodRecords);

  @override
  Future<List<ReaMicroBookRecord>> fetchBookRecordsByYear(
    String token, {
    int? year,
  }) async => List<ReaMicroBookRecord>.of(periodRecords);

  @override
  Future<List<ReaMicroMarkBook>> fetchMarkBooks(String token) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return List<ReaMicroMarkBook>.of(markBooks);
  }

  @override
  Future<void> hideBookRecord(String token, {required int bookId}) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    hiddenBookIds.add(bookId);
  }

  @override
  Future<void> actReview(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    reviewActions.add(true);
    actionTypes = <int>{...actionTypes, actionType};
  }

  @override
  Future<void> unactReview(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    reviewActions.add(false);
    actionTypes = <int>{...actionTypes}..remove(actionType);
  }

  @override
  Future<ReaMicroReviewActionState> checkReviewAction(
    String token, {
    required int reviewId,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return ReaMicroReviewActionState(actionTypes: Set<int>.of(actionTypes));
  }

  @override
  Future<ReaMicroReviewActorPage> fetchReviewActors(
    String token, {
    required int reviewId,
    int actionType = ReaMicroReviewActionState.likeType,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return ReaMicroReviewActorPage(
      items: List<ReaMicroReviewActor>.of(reviewActors),
      total: reviewActorTotal,
    );
  }

  @override
  Future<List<ReaMicroBookReview>> fetchReviewFlow(
    String token, {
    int? cloudBookId,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    return List<ReaMicroBookReview>.of(reviewFlow);
  }

  @override
  Future<void> deleteMilestone(String token, {required int milestoneId}) async {
    if (unauthorized) {
      throw const ReaMicroException('登录已失效', unauthorized: true);
    }
    deletedMilestones.add(milestoneId);
    milestones.removeWhere((item) => item.id == milestoneId);
  }

  @override
  void close() {}
}

class _ReviewUpload {
  const _ReviewUpload({
    required this.cloudBookId,
    required this.rating,
    required this.comment,
    required this.publish,
  });

  final int cloudBookId;
  final int rating;
  final String comment;
  final bool publish;
}

class _ProgressUpload {
  const _ProgressUpload({
    required this.cloudBookId,
    required this.cfi,
    required this.chapterName,
    required this.progress,
  });

  final int cloudBookId;
  final String cfi;
  final String chapterName;
  final double progress;
}

ReadingSession _session(
  DateTime start,
  DateTime end, {
  String bookId = 'book-a',
}) => ReadingSession(
  bookId: bookId,
  startedAt: start,
  endedAt: end,
  duration: end.difference(start),
);

Future<ReaMicroController> _createController(
  LibraryStore library,
  _FakeApi api, {
  bool signedIn = true,
  ReaderProgressStore? progressStore,
  ReaMicroLanClient? lan,
  ReaMicroS3Client Function(ReaMicroS3Config config)? s3ClientFactory,
}) async {
  if (signedIn) {
    await ReaMicroStore(library).saveToken('token');
  }
  final controller = ReaMicroController(
    library: library,
    api: api,
    progressStore: progressStore,
    lan: lan,
    s3ClientFactory: s3ClientFactory,
  );
  await controller.initialize();
  return controller;
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

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

  test('阅读时长同时上报逐段会话日志', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    final start = DateTime.utc(2026, 11, 17, 2);
    library.sessions.add(
      _session(start, start.add(const Duration(minutes: 7))),
    );

    final result = await controller.syncReadingSessions();

    expect(result.success, isTrue);
    expect(api.uploads, hasLength(1));
    expect(api.uploads.single.single.durationSeconds, 420);
    final logs = api.sessionLogUploads.single;
    expect(logs, hasLength(1));
    expect(logs.single.cloudBookId, 11);
    expect(logs.single.startedAt, start.millisecondsSinceEpoch);
    expect(
      logs.single.endedAt,
      start.add(const Duration(minutes: 7)).millisecondsSinceEpoch,
    );
    expect(logs.single.durationSeconds, 420);
    expect(logs.single.recordDay, '2026-11-17');
    expect(logs.single.id, startsWith('spectacular-book-a|'));
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

  test('登记并关联提交 EPUB MD5 并复用搜索结果出版方', () async {
    final dir = Directory.systemTemp.createTempSync('rea-register');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final bytes = buildTestEpub(
      title: '本地登记书',
      identifier: 'urn:uuid:rea-register',
    );
    final file = File('${dir.path}/book.epub')..writeAsBytesSync(bytes);
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地登记书',
        author: '作者',
        filePath: file.path,
        addedAt: DateTime(2026, 11, 18),
        spineCount: 2,
        contentRevision: 'rev-register',
      );
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    const cloudBook = ReaMicroCloudBook(
      cloudBookId: 42,
      name: '云端登记书',
      author: '云端作者',
      publishers: <ReaMicroCloudPublisher>[
        ReaMicroCloudPublisher(publisherId: 88, publisher: '出版社'),
      ],
    );
    final link = await controller.registerAndLinkBook(
      'book-a',
      cloudBook: cloudBook,
    );

    expect(api.userBookRequests.single['md5'], md5.convert(bytes).toString());
    expect(api.userBookRequests.single['name'], '本地登记书');
    expect(api.cloudBookInfoCalls, 0);
    expect(api.cloudBookRequests, isEmpty);
    expect(api.relateRequests.single, <String, Object?>{
      'userBookId': 7001,
      'bookPublisherId': 88,
    });
    expect(link.cloudBookId, 42);
    expect(link.userBookId, 7001);
    expect(link.publisherId, 88);
    expect(controller.links['book-a']?.cloudBookId, 42);
  });

  test('已有云端书缺少出版方时先补全资料且不重复创建云端书', () async {
    final dir = Directory.systemTemp.createTempSync('rea-register-info');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File('${dir.path}/book.epub')
      ..writeAsBytesSync(
        buildTestEpub(title: '补全资料', identifier: 'urn:uuid:rea-register-info'),
      );
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '补全资料',
        author: '作者',
        filePath: file.path,
        addedAt: DateTime(2026, 11, 18),
        spineCount: 2,
        contentRevision: 'rev-info',
      );
    final api = _FakeApi()
      ..cloudBookInfo = const ReaMicroCloudBook(
        cloudBookId: 42,
        name: '补全资料',
        author: '作者',
        publishers: <ReaMicroCloudPublisher>[
          ReaMicroCloudPublisher(publisherId: 88, publisher: '出版社'),
        ],
      );
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    final link = await controller.registerAndLinkBook(
      'book-a',
      cloudBook: const ReaMicroCloudBook(
        cloudBookId: 42,
        name: '补全资料',
        author: '作者',
      ),
    );

    expect(api.cloudBookInfoCalls, 1);
    expect(api.cloudBookRequests, isEmpty);
    expect(api.relateRequests.single['bookPublisherId'], 88);
    expect(link.cloudBookId, 42);
    expect(link.publisherId, 88);
  });

  test('补全后仍无出版方时保留云端书标识而不生成重复条目', () async {
    final dir = Directory.systemTemp.createTempSync('rea-register-publisher');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File('${dir.path}/book.epub')
      ..writeAsBytesSync(
        buildTestEpub(
          title: '无出版方',
          identifier: 'urn:uuid:rea-register-publisher',
        ),
      );
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '无出版方',
        author: '作者',
        filePath: file.path,
        addedAt: DateTime(2026, 11, 18),
        spineCount: 2,
        contentRevision: 'rev-publisher',
      );
    final api = _FakeApi()
      ..cloudBookInfo = const ReaMicroCloudBook(cloudBookId: 42, name: '无出版方');
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    final link = await controller.registerAndLinkBook(
      'book-a',
      cloudBook: const ReaMicroCloudBook(cloudBookId: 42, name: '无出版方'),
    );

    expect(api.cloudBookInfoCalls, 1);
    expect(api.cloudBookRequests, isEmpty);
    expect(api.relateRequests, isEmpty);
    expect(link.cloudBookId, 42);
    expect(link.publisherId, 0);
  });

  test('缺少云端书标识时新建云端书并建立用户书关联', () async {
    final dir = Directory.systemTemp.createTempSync('rea-register-create');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File('${dir.path}/book.epub')
      ..writeAsBytesSync(
        buildTestEpub(title: '待新建', identifier: 'urn:uuid:rea-register-create'),
      );
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '待新建',
        author: '作者',
        filePath: file.path,
        addedAt: DateTime(2026, 11, 18),
        spineCount: 2,
        contentRevision: 'rev-create',
      );
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    final link = await controller.registerAndLinkBook('book-a');

    expect(api.cloudBookRequests.single, <String, Object?>{
      'name': '待新建',
      'author': '作者',
      'intro': '',
    });
    expect(api.relateRequests.single, <String, Object?>{
      'userBookId': 7001,
      'bookPublisherId': 9001,
    });
    expect(link.cloudBookId, 8001);
    expect(link.publisherId, 9001);
  });

  test('登记关联后阅读时长、进度和标注可自动同步', () async {
    final dir = Directory.systemTemp.createTempSync('rea-register-sync');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final bytes = buildTestEpub(
      title: '登记同步',
      identifier: 'urn:uuid:rea-register-sync',
    );
    final db = AppDatabase(NativeDatabase.memory());
    final library = _DbTestLibrary(db, dir);
    addTearDown(() async {
      await db.close();
    });
    final imported = await library.importBytes(bytes);
    final api = _FakeApi();
    final progressStore = MemoryReaderProgressStore();
    final controller = await _createController(
      library,
      api,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);

    final link = await controller.registerAndLinkBook(
      imported.id,
      cloudBook: const ReaMicroCloudBook(
        cloudBookId: 42,
        name: '登记同步',
        publishers: <ReaMicroCloudPublisher>[
          ReaMicroCloudPublisher(publisherId: 88, publisher: '出版社'),
        ],
      ),
    );
    library.sessionStore.items.add(
      _session(
        DateTime.utc(2026, 11, 18, 1),
        DateTime.utc(2026, 11, 18, 1, 12),
        bookId: imported.id,
      ),
    );
    await controller.trackedProgressStore!.save(
      imported.id,
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: 'epubcfi(/6/4!/4/2/1)',
        contentRevision: 'rev',
        readingPercent: 0.4,
        chapterTitle: '第二章',
      ),
    );
    await library.importBookAnnotation(
      imported.id,
      ReaderAnnotation(
        id: 'mark-a',
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/4!/4/2/2)',
        endCfi: 'epubcfi(/6/4!/4/2/6)',
        quote: '原文',
        color: 0xFFFFC542,
        style: ReaderAnnotationStyle.underline,
        createdAt: DateTime.utc(2026, 11, 18, 1),
        updatedAt: DateTime.utc(2026, 11, 18, 1, 12),
      ),
    );

    final result = await controller.syncAll();

    expect(result.success, isTrue);
    expect(api.uploads.last.single.durationSeconds, 720);
    expect(api.progressUploads.single.cloudBookId, link.cloudBookId);
    expect(api.progressUploads.single.cfi, 'epubcfi(/6/4!/4/2/1)');
    expect(api.markUpserts.single.bookId, '42');
    expect(api.markUpserts.single.quote, '原文');
  });

  test('阅读页保存位置后上报 CFI、章节与百分比', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi();
    final progressStore = MemoryReaderProgressStore();
    final controller = await _createController(
      library,
      api,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );

    await controller.trackedProgressStore!.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 3,
        cfi: 'epubcfi(/6/4!/4/2/1)',
        contentRevision: 'rev-1',
        readingPercent: 0.25,
        chapterTitle: '第二章',
      ),
    );
    final result = await controller.syncProgress(pullCloud: false);

    expect(result.success, isTrue);
    expect(result.requests, 1);
    final upload = api.progressUploads.single;
    expect(upload.cloudBookId, 11);
    expect(upload.cfi, 'epubcfi(/6/4!/4/2/1)');
    expect(upload.chapterName, '第二章');
    expect(upload.progress, 0.25);
  });

  test('登录后关联书籍会把已有本地位置加入上报队列', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi();
    final progressStore = MemoryReaderProgressStore();
    final controller = await _createController(
      library,
      api,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);

    await controller.trackedProgressStore!.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: 'epubcfi(/6/4!/4/2/1)',
        contentRevision: 'rev-1',
        readingPercent: 0.1,
        chapterTitle: '第一章',
      ),
    );
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    final result = await controller.syncProgress(pullCloud: false);

    expect(result.requests, 1);
    expect(api.progressUploads.single.cfi, 'epubcfi(/6/4!/4/2/1)');
  });

  test('云端较新位置写入本地进度存储', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi()
      ..remoteProgress = ReaMicroReadProgress(
        cloudBookId: '11',
        cfi: 'epubcfi(/6/8!/4/2/1)',
        chapterName: '第三章',
        progress: 0.6,
        readFinishTime: DateTime.now().millisecondsSinceEpoch + 60000,
      );
    final progressStore = MemoryReaderProgressStore();
    final controller = await _createController(
      library,
      api,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );

    final result = await controller.syncProgress();

    expect(result.success, isTrue);
    expect(result.requests, 1);
    final saved = await progressStore.load('book-a');
    expect(saved?.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(saved?.spineIndex, 3);
    expect(saved?.readingPercent, 0.6);
    expect(saved?.contentRevision, 'rev-1');
  });

  test('新登录先拉取云端较新位置，不用旧本地进度覆盖', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi()
      ..remoteProgress = ReaMicroReadProgress(
        cloudBookId: '11',
        cfi: 'epubcfi(/6/8!/4/2/1)',
        chapterName: '第三章',
        progress: 0.6,
        readFinishTime: DateTime.now().millisecondsSinceEpoch + 60000,
      );
    final progressStore = MemoryReaderProgressStore();
    await progressStore.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: 'epubcfi(/6/4!/4/2/1)',
        contentRevision: 'rev-1',
        readingPercent: 0.1,
        chapterTitle: '第一章',
      ),
    );
    await ReaMicroStore(library).saveLinks(<String, ReaMicroBookLink>{
      'book-a': ReaMicroBookLink(
        cloudBookId: 11,
        name: '云端书',
        linkedAt: DateTime(2026, 11, 17),
      ),
    });
    final controller = await _createController(
      library,
      api,
      signedIn: false,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.login(email: 'reader@example.com', code: '1234'),
      isTrue,
    );
    final result = await controller.syncProgress();

    expect(result.success, isTrue);
    final saved = await progressStore.load('book-a');
    expect(saved?.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(saved?.readingPercent, 0.6);
    expect(api.progressUploads, isEmpty);
  });

  test('新登录时云端没有位置则上报本地进度', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi();
    final progressStore = MemoryReaderProgressStore();
    await progressStore.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: 'epubcfi(/6/4!/4/2/1)',
        contentRevision: 'rev-1',
        readingPercent: 0.1,
        chapterTitle: '第一章',
      ),
    );
    await ReaMicroStore(library).saveLinks(<String, ReaMicroBookLink>{
      'book-a': ReaMicroBookLink(
        cloudBookId: 11,
        name: '云端书',
        linkedAt: DateTime(2026, 11, 17),
      ),
    });
    final controller = await _createController(
      library,
      api,
      signedIn: false,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.login(email: 'reader@example.com', code: '1234'),
      isTrue,
    );
    final result = await controller.syncProgress();

    expect(result.success, isTrue);
    expect(api.progressUploads.single.cfi, 'epubcfi(/6/4!/4/2/1)');
    final saved = await progressStore.load('book-a');
    expect(saved?.cfi, 'epubcfi(/6/4!/4/2/1)');
  });

  test('本地未上报位置不会被较旧的云端位置覆盖', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi()
      ..remoteProgress = ReaMicroReadProgress(
        cloudBookId: '11',
        cfi: 'epubcfi(/6/4!/4/2/1)',
        chapterName: '旧位置',
        progress: 0.1,
        readFinishTime: DateTime.now().millisecondsSinceEpoch - 60000,
      );
    final progressStore = MemoryReaderProgressStore();
    final controller = await _createController(
      library,
      api,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );

    await controller.trackedProgressStore!.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 4,
        pageIndex: 1,
        cfi: 'epubcfi(/6/10!/4/2/1)',
        contentRevision: 'rev-1',
        readingPercent: 0.45,
        chapterTitle: '第五章',
      ),
    );
    await controller.syncProgress();

    final saved = await progressStore.load('book-a');
    expect(saved?.cfi, 'epubcfi(/6/10!/4/2/1)');
    expect(api.progressUploads.single.cfi, 'epubcfi(/6/10!/4/2/1)');
  });

  test('多端较新的云端位置优先于尚未上报的本地位置', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi()
      ..remoteProgress = ReaMicroReadProgress(
        cloudBookId: '11',
        cfi: 'epubcfi(/6/8!/4/2/1)',
        chapterName: '第三章',
        progress: 0.6,
        readFinishTime: DateTime.now().millisecondsSinceEpoch + 60000,
      );
    final progressStore = MemoryReaderProgressStore();
    final controller = await _createController(
      library,
      api,
      progressStore: progressStore,
    );
    addTearDown(controller.dispose);
    await controller.linkBook(
      'book-a',
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );

    await controller.trackedProgressStore!.save(
      'book-a',
      const ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: 'epubcfi(/6/4!/4/2/1)',
        contentRevision: 'rev-1',
        readingPercent: 0.1,
        chapterTitle: '第一章',
      ),
    );
    final result = await controller.syncProgress();

    expect(result.success, isTrue);
    expect(result.requests, 1);
    expect(api.progressUploads, isEmpty);
    final saved = await progressStore.load('book-a');
    expect(saved?.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(saved?.readingPercent, 0.6);
  });

  test('开启唯一数据源后持久化并读取完整云端统计', () async {
    final library = _TestLibrary();
    final api = _FakeApi()
      ..overview = const ReaMicroOverview(
        years: <int>[2025, 2026],
        readDays: 42,
        totalDurationSeconds: 7200,
        bookCount: 8,
        finishedBookCount: 3,
        registerTimestamp: 0,
        topBooks: <ReaMicroTopBook>[],
        listeningDurationSeconds: 1200,
        readingDurationSeconds: 6000,
      );
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    await controller.setCloudAsPrimary(true);

    expect(controller.cloudAsPrimary, isTrue);
    expect(await ReaMicroStore(library).loadCloudPrimary(), isTrue);
    expect(controller.cloudStats?.overview.totalDurationSeconds, 7200);
    expect(controller.cloudStats?.overview.years, <int>[2025, 2026]);
  });

  test('S3 配置加密保存到阅微账号并可重新载入', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    const config = ReaMicroS3Config(
      endpoint: 'https://s3.example.com',
      bucket: 'bucket',
      region: 'us-east-1',
      accessKey: 'access',
      secretKey: 'secret',
      prefix: 'reamicro',
    );

    await controller.saveCloudS3Config(config, enabled: true);

    expect(api.cloudS3Enabled, isTrue);
    expect(api.cloudS3Uploads.single.toJson(), config.toJson());
    api.s3CloudConfig = ReaMicroS3CloudConfigResponse(
      enabled: true,
      encryptedConfig: ReaMicroS3ConfigCrypto.encrypt(config, 1),
    );
    final cloud = await controller.fetchCloudS3Config();

    expect(cloud.enabled, isTrue);
    expect(cloud.usable, isTrue);
    expect(cloud.config?.bucket, 'bucket');

    await controller.saveCloudS3Config(config, enabled: false);
    expect(api.cloudS3Enabled, isFalse);
  });

  test('对象存储扩容要求 60 积分整数倍并刷新配额', () async {
    final library = _TestLibrary();
    final api = _FakeApi()
      ..storageQuota = const ReaMicroStorageQuota(
        capacityBytes: 1073741824,
        capacityGib: 1,
        credit: 120,
        usedBytes: 0,
      );
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    await expectLater(
      controller.expandStorageQuota(credit: 30),
      throwsA(isA<ReaMicroException>()),
    );
    final quota = await controller.expandStorageQuota(credit: 60);

    expect(api.expandedCredits, <int>[60]);
    expect(quota.capacityGib, 2);
    expect(quota.credit, 60);
    expect(controller.s3Message, contains('2 GiB'));
  });

  test('读取阅微朗读音色目录需要登录', () async {
    final library = _TestLibrary();
    final api = _FakeApi()
      ..ttsCatalog = const ReaMicroTtsCatalog(
        engines: <ReaMicroTtsEngine>[],
        voices: <ReaMicroTtsVoice>[
          ReaMicroTtsVoice(
            id: 'vits-piper-zh_CN-xiao_ya-medium',
            downloadUrl: 'https://example.test/voice.tar.bz2',
            name: '小雅',
          ),
        ],
      );
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    final catalog = await controller.fetchTtsCatalog();

    expect(catalog.voices.single.name, '小雅');

    final anonymous = await _createController(
      _TestLibrary(),
      api,
      signedIn: false,
    );
    addTearDown(anonymous.dispose);
    await expectLater(
      anonymous.fetchTtsCatalog(),
      throwsA(isA<ReaMicroException>()),
    );
  });

  test('新设备登录后从阅微账号恢复 S3 同步配置', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    const config = ReaMicroS3Config(
      endpoint: 'https://s3.example.com',
      bucket: 'bucket',
      region: 'us-east-1',
      accessKey: 'access',
      secretKey: 'secret',
      prefix: 'reamicro',
    );
    api.s3CloudConfig = ReaMicroS3CloudConfigResponse(
      enabled: true,
      encryptedConfig: ReaMicroS3ConfigCrypto.encrypt(config, 1),
    );

    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    expect(controller.s3Configured, isTrue);
    expect(controller.s3Config?.endpoint, 'https://s3.example.com');
    expect(
      (await ReaMicroStore(library).loadS3Config())?.toJson(),
      config.toJson(),
    );
  });

  test('新设备登录后恢复阅微内置存储配置并参与自动同步', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    const config = ReaMicroS3Config(
      endpoint: '',
      bucket: '',
      region: '',
      accessKey: '',
      secretKey: '',
      prefix: 'reamicro',
      provider: 'MOTE',
    );
    api.s3CloudConfig = ReaMicroS3CloudConfigResponse(
      enabled: true,
      encryptedConfig: ReaMicroS3ConfigCrypto.encrypt(config, 1),
    );

    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    expect(controller.s3Configured, isTrue);
    expect(controller.s3Config?.isMote, isTrue);
    expect(
      (await ReaMicroStore(library).loadS3Config())?.toJson(),
      config.toJson(),
    );
  });

  test('阅微内置存储无需密钥即可参与唯一数据源自动同步', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    const config = ReaMicroS3Config(
      endpoint: '',
      bucket: '',
      region: '',
      accessKey: '',
      secretKey: '',
      prefix: 'reamicro',
      provider: 'MOTE',
    );
    final s3 = _MemoryS3();
    ReaMicroS3Config? usedConfig;
    await ReaMicroStore(library).saveS3Config(config);
    await ReaMicroStore(library).saveCloudPrimary(true);

    final controller = await _createController(
      library,
      api,
      s3ClientFactory: (config) {
        usedConfig = config;
        return s3;
      },
    );
    addTearDown(controller.dispose);

    expect(usedConfig?.isMote, isTrue);
    expect(s3.puts, greaterThan(0));
    expect(controller.s3LastSyncAt, isNotNull);
    expect(controller.s3Message, isNot(contains('请先配置')));
  });

  test('开启唯一数据源后自动执行 S3 同步', () async {
    final library = _TestLibrary();
    final api = _FakeApi();
    const config = ReaMicroS3Config(
      endpoint: 'https://s3.example.com',
      bucket: 'bucket',
      region: 'us-east-1',
      accessKey: 'access',
      secretKey: 'secret',
      prefix: 'reamicro',
    );
    final s3 = _MemoryS3();
    await ReaMicroStore(library).saveS3Config(config);
    await ReaMicroStore(library).saveCloudPrimary(true);

    final controller = await _createController(
      library,
      api,
      s3ClientFactory: (_) => s3,
    );
    addTearDown(controller.dispose);

    expect(controller.cloudAsPrimary, isTrue);
    expect(s3.puts, greaterThan(0));
    expect(controller.s3LastSyncAt, isNotNull);
    expect(controller.s3Message, contains('S3 同步完成'));

    final result = await controller.syncEverything();
    expect(result.message, contains('S3 同步完成'));
  });

  test('S3 同步保存本地 UUID 基线并在更换存储目录时清空', () async {
    final dir = await Directory.systemTemp.createTemp('rea-s3-baseline-');
    addTearDown(() => dir.delete(recursive: true));
    final bytes = buildTestEpub(
      title: '基线书',
      author: '作者',
      identifier: 's3-baseline',
    );
    final file = File('${dir.path}/baseline.epub');
    await file.writeAsBytes(bytes, flush: true);
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'local-book',
        title: '基线书',
        author: '作者',
        filePath: file.path,
        addedAt: DateTime.now(),
      );
    const config = ReaMicroS3Config(
      endpoint: 'https://s3.example.com',
      bucket: 'bucket',
      region: 'us-east-1',
      accessKey: 'access',
      secretKey: 'secret',
      prefix: 'reamicro',
    );
    await ReaMicroStore(library).saveS3Config(config);
    final s3 = _MemoryS3();
    final controller = await _createController(
      library,
      _FakeApi(),
      s3ClientFactory: (_) => s3,
    );
    addTearDown(controller.dispose);

    final result = await controller.syncS3(scheduleFollowUp: false);

    expect(result, isNotNull);
    expect(s3.puts, greaterThan(0));
    expect(
      (await ReaMicroStore(library).loadS3LocalBookUuids())['local-book'],
      'local-book',
    );
    await ReaMicroStore(library).saveS3PendingDeletions(<String>{'gone'});
    await controller.saveS3Config(config.copyWith(prefix: 'other'));
    expect(await ReaMicroStore(library).loadS3LocalBookUuids(), isEmpty);
    expect(await ReaMicroStore(library).loadS3PendingDeletions(), isEmpty);
  });

  test('按书名和作者自动关联云端书籍', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'book-a',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final api = _FakeApi()
      ..bookRecords = <ReaMicroBookRecord>[
        const ReaMicroBookRecord(
          bookId: 8,
          cloudBookId: 21,
          name: '本地书',
          author: '作者',
          cover: '',
          progress: 0.3,
          totalReadTimeSeconds: 600,
          readDays: 2,
          finishReadTime: 0,
          listeningDurationSeconds: 0,
          readingDurationSeconds: 600,
        ),
      ];
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    final linked = await controller.autoLinkMatchingBooks();

    expect(linked, 1);
    expect(controller.links['book-a']?.cloudBookId, 21);
    expect((await ReaMicroStore(library).loadLinks())['book-a']?.name, '本地书');
  });

  test('局域网进度按书名和作者匹配本地书籍', () async {
    final library = _TestLibrary()
      ..book = BookEntry(
        id: 'local-book',
        title: '本地书',
        author: '作者',
        filePath: '',
        addedAt: DateTime(2026, 11, 17),
        spineCount: 10,
        contentRevision: 'rev-1',
      );
    final progressStore = _MemoryProgressStore();
    final manifest = ReaMicroLanManifest.fromJson(<String, Object?>{
      'userId': 1,
      'deviceId': 'device-b',
      'generatedAt': 1763380800000,
      'books': <Object?>[
        <String, Object?>{
          'uuid': 'reamicro-book-uuid',
          'progressUpdatedAt': 1763380700000,
          'book': <String, Object?>{
            'uuid': 'reamicro-book-uuid',
            'title': '本地书',
            'author': '作者',
            'cloudId': 21,
            'epubcfi': 'epubcfi(/6/8!/4/2/1)',
            'chapter': '第三章',
            'progress': 37.5,
          },
        },
      ],
    });
    final controller = await _createController(
      library,
      _FakeApi(),
      progressStore: progressStore,
      lan: _FakeLan(manifest),
    );
    addTearDown(controller.dispose);

    final message = await controller.syncWithLanPeer(
      const ReaMicroLanSyncPeer(
        host: '127.0.0.1',
        port: 1,
        userId: 1,
        deviceId: 'device-b',
        nickname: '测试用户',
        deviceName: '测试设备',
      ),
    );

    expect(message, '已从 测试设备 合并 1 本阅读位置');
    expect(progressStore.items['local-book']?.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(
      progressStore.items['local-book']?.readingPercent,
      closeTo(0.375, 0.0001),
    );
    expect(progressStore.items['local-book']?.chapterTitle, '第三章');
  });

  test('局域网同步会下载本地缺失的图书并建立云端关联', () async {
    final library = _TestLibrary();
    final progressStore = _MemoryProgressStore();
    final manifest = ReaMicroLanManifest.fromJson(<String, Object?>{
      'userId': 1,
      'deviceId': 'device-b',
      'generatedAt': 1763380800000,
      'books': <Object?>[
        <String, Object?>{
          'uuid': 'reamicro-book-uuid',
          'progressUpdatedAt': 1763380700000,
          'book': <String, Object?>{
            'uuid': 'reamicro-book-uuid',
            'title': '远端新书',
            'author': '作者',
            'cloudId': 21,
            'epubcfi': 'epubcfi(/6/2!/4/2/1)',
            'chapter': '第三章',
            'progress': 37.5,
          },
          'files': <Object?>[
            <String, Object?>{
              'relativePath': 'mimetype',
              'size': 20,
              'md5': '',
            },
          ],
        },
      ],
    });
    final lan = _FakeLan(
      manifest,
      archive: buildTestEpub(
        title: '远端新书',
        author: '作者',
        identifier: 'urn:uuid:reamicro-book',
      ),
    );
    final controller = await _createController(
      library,
      _FakeApi(),
      progressStore: progressStore,
      lan: lan,
    );
    addTearDown(controller.dispose);

    final message = await controller.syncWithLanPeer(
      const ReaMicroLanSyncPeer(
        host: '127.0.0.1',
        port: 1,
        userId: 1,
        deviceId: 'device-b',
        nickname: '测试用户',
        deviceName: '测试设备',
      ),
    );

    expect(lan.downloadCalls, 1);
    expect(message, contains('下载 1 本图书'));
    final books = await library.list();
    expect(books, hasLength(1));
    expect(books.single.title, '远端新书');
    expect(controller.links[books.single.id]?.cloudBookId, 21);
    expect(progressStore.items[books.single.id]?.cfi, 'epubcfi(/6/2!/4/2/1)');
  });

  test('局域网单本导入失败不会中断其余图书同步', () async {
    final library = _TestLibrary();
    final manifest = ReaMicroLanManifest.fromJson(<String, Object?>{
      'userId': 1,
      'deviceId': 'device-b',
      'generatedAt': 1763380800000,
      'books': <Object?>[
        for (final title in <String>['损坏书', '正常书'])
          <String, Object?>{
            'uuid': 'remote-$title',
            'progressUpdatedAt': 0,
            'book': <String, Object?>{
              'uuid': 'remote-$title',
              'title': title,
              'author': '作者',
              'cloudId': title == '正常书' ? 22 : 21,
            },
            'files': <Object?>[
              <String, Object?>{
                'relativePath': 'mimetype',
                'size': 20,
                'md5': '',
              },
            ],
          },
      ],
    });
    final lan = _FakeLan(
      manifest,
      archives: <List<int>>[
        <int>[1, 2, 3, 4],
        buildTestEpub(
          title: '正常书',
          author: '作者',
          identifier: 'urn:uuid:normal-book',
        ),
      ],
    );
    final controller = await _createController(library, _FakeApi(), lan: lan);
    addTearDown(controller.dispose);

    final message = await controller.syncWithLanPeer(
      const ReaMicroLanSyncPeer(
        host: '127.0.0.1',
        port: 1,
        userId: 1,
        deviceId: 'device-b',
        nickname: '测试用户',
        deviceName: '测试设备',
      ),
    );

    expect(lan.downloadCalls, 2);
    expect(message, contains('1 本文件导入失败'));
    expect(message, contains('下载 1 本图书'));
    final books = await library.list();
    expect(books.single.title, '正常书');
    expect(controller.links[books.single.id]?.cloudBookId, 22);
  });

  test('云端较新标注导入本地并保留颜色、想法与时间戳', () async {
    final library = await _openDbLibrary();
    final book = await library.importBytes(
      buildTestEpub(title: '标注书', identifier: 'urn:uuid:mark-book'),
    );
    final api = _FakeApi()
      ..marks = <ReaMicroMark>[
        const ReaMicroMark(
          id: 77,
          bookId: '11',
          chapter: '第一章',
          kind: 1,
          startCfi: 'epubcfi(/6/4!/4/2/1)',
          endCfi: 'epubcfi(/6/4!/4/2/5)',
          quote: '原文',
          note: '云端想法',
          style: 1,
          color: '#FFFF0000',
          synced: 1,
          createdAt: 1000,
          updatedAt: 2000,
        ),
      ];
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      book.id,
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );

    final result = await controller.syncMarks();

    expect(result.success, isTrue);
    final annotations = await library.listBookAnnotations(book.id);
    expect(annotations, hasLength(1));
    final annotation = annotations.single;
    expect(annotation.type, ReaderAnnotationType.thought);
    expect(annotation.note, '云端想法');
    expect(annotation.style, ReaderAnnotationStyle.underline);
    expect(annotation.color, 0xFFFF0000);
    expect(annotation.createdAt.millisecondsSinceEpoch, 1000);
    expect(annotation.updatedAt.millisecondsSinceEpoch, 2000);
    expect(
      (await ReaMicroStore(library)
          .loadMarkIds())['${book.id}|${annotation.id}'],
      77,
    );
  });

  test('本地较新标注上传并记录云端标识，重复同步不重复上传', () async {
    final library = await _openDbLibrary();
    final book = await library.importBytes(
      buildTestEpub(title: '标注书', identifier: 'urn:uuid:mark-upload'),
    );
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      book.id,
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    await library.importBookAnnotation(
      book.id,
      ReaderAnnotation(
        id: 'local-mark',
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/4!/4/2/1)',
        endCfi: 'epubcfi(/6/4!/4/2/3)',
        quote: '本地原文',
        color: 0xFFFF0000,
        style: ReaderAnnotationStyle.underline,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
      ),
    );

    final first = await controller.syncMarks();

    expect(first.success, isTrue);
    expect(api.markUpserts, hasLength(1));
    final upload = api.markUpserts.single;
    expect(upload.cloudId, 0);
    expect(upload.createdAt, 1000);
    expect(upload.updatedAt, 5000);
    expect(upload.color, '#ffff0000');
    expect(
      (await ReaMicroStore(library).loadMarkIds())['${book.id}|local-mark'],
      500,
    );

    final second = await controller.syncMarks();

    expect(second.requests, 0);
    expect(api.markUpserts, hasLength(1));
  });

  test('本地删除标注后删除云端标注', () async {
    final library = await _openDbLibrary();
    final book = await library.importBytes(
      buildTestEpub(title: '标注书', identifier: 'urn:uuid:mark-delete'),
    );
    final api = _FakeApi();
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);
    await controller.linkBook(
      book.id,
      const ReaMicroCloudBook(cloudBookId: 11, name: '云端书'),
    );
    await library.importBookAnnotation(
      book.id,
      ReaderAnnotation(
        id: 'local-mark',
        type: ReaderAnnotationType.mark,
        startCfi: 'epubcfi(/6/4!/4/2/1)',
        endCfi: 'epubcfi(/6/4!/4/2/3)',
        quote: '本地原文',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
      ),
    );
    await controller.syncMarks();
    await library.removeBookAnnotation(book.id, 'local-mark');

    final result = await controller.syncMarks();

    expect(result.success, isTrue);
    expect(api.markDeletes, <int>[500]);
    expect(
      (await ReaMicroStore(
        library,
      ).loadMarkIds()).containsKey('${book.id}|local-mark'),
      isFalse,
    );
  });

  test('局域网清单中的标注合并到本地', () async {
    final library = await _openDbLibrary();
    final book = await library.importBytes(
      buildTestEpub(title: '局域网标注', identifier: 'urn:uuid:lan-mark'),
    );
    final manifest = ReaMicroLanManifest.fromJson(<String, Object?>{
      'userId': 1,
      'deviceId': 'device-b',
      'generatedAt': 1763380800000,
      'books': <Object?>[
        <String, Object?>{
          'uuid': book.id,
          'progressUpdatedAt': 0,
          'book': <String, Object?>{
            'uuid': book.id,
            'title': book.title,
            'author': book.author,
            'cloudId': 11,
          },
          'marks': <Object?>[
            <String, Object?>{
              'startCfi': 'epubcfi(/6/4!/4/2/1)',
              'endCfi': 'epubcfi(/6/4!/4/2/3)',
              'kind': 1,
              'chapter': '第一章',
              'quote': '局域网原文',
              'note': '局域网想法',
              'style': 0,
              'color': '#CC00FF00',
              'synced': 1,
              'cloudId': 88,
              'createdAt': 1000,
              'updatedAt': 3000,
            },
          ],
        },
      ],
    });
    final controller = await _createController(
      library,
      _FakeApi(),
      lan: _FakeLan(manifest),
    );
    addTearDown(controller.dispose);
    expect(manifest.books.single.marks, hasLength(1));

    final message = await controller.syncWithLanPeer(
      const ReaMicroLanSyncPeer(
        host: '127.0.0.1',
        port: 1,
        userId: 1,
        deviceId: 'device-b',
        nickname: '测试用户',
        deviceName: '测试设备',
      ),
    );

    expect(message, contains('合并 1 条标注'));
    final annotations = await library.listBookAnnotations(book.id);
    expect(annotations, hasLength(1));
    expect(annotations.single.id, 'mark-lan-88');
    expect(annotations.single.note, '局域网想法');
    expect(annotations.single.color, 0xCC00FF00);
  });

  test('读取里程碑、发布书评并删除里程碑', () async {
    final library = _TestLibrary();
    final api = _FakeApi()
      ..bookReview = ReaMicroBookReview.fromJson(<String, Object?>{
        'id': 21,
        'rating': 4,
        'comment': '旧书评',
        'status': 2,
        'bookName': '云端书',
      })
      ..milestones = <ReaMicroMilestone>[
        ReaMicroMilestone.fromJson(<String, Object?>{
          'id': 7,
          'rating': 5,
          'cloudBookId': 11,
          'name': '云端书',
          'comment': '读完了',
          'totalReadTime': 7200,
          'readDays': 3,
        }),
      ];
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    await controller.refreshMilestones();
    final review = await controller.loadBookReview(11);
    final saved = await controller.saveReview(
      cloudBookId: 11,
      rating: 4,
      comment: '新的书评',
      publish: true,
    );
    expect(controller.milestones.single.name, '云端书');
    final deleted = await controller.deleteMilestone(7);

    expect(review?.comment, '旧书评');
    expect(saved.success, isTrue);
    expect(api.reviewUploads.single.rating, 4);
    expect(api.reviewUploads.single.comment, '新的书评');
    expect(api.reviewUploads.single.publish, isTrue);
    expect(deleted.success, isTrue);
    expect(api.deletedMilestones, <int>[7]);
    expect(controller.milestones, isEmpty);
  });

  test('读取周期记录、标注书籍并切换书评点赞', () async {
    final library = _TestLibrary();
    final api = _FakeApi()
      ..periodRecords = <ReaMicroBookRecord>[
        ReaMicroBookRecord.fromJson(<String, Object?>{
          'bookId': 8,
          'cloudBookId': 11,
          'name': '云端书',
          'progress': 51.66,
          'totalReadTime': 600,
        }),
      ]
      ..markBooks = <ReaMicroMarkBook>[
        ReaMicroMarkBook.fromJson(<String, Object?>{
          'bookId': 8,
          'cloudBookId': 11,
          'bookName': '云端书',
          'thoughtCount': 2,
          'underlineCount': 3,
        }),
      ]
      ..reviewActors = <ReaMicroReviewActor>[
        ReaMicroReviewActor.fromJson(<String, Object?>{
          'userId': 2,
          'userName': '点赞用户',
          'actionType': 0,
        }),
      ]
      ..reviewActorTotal = 1
      ..reviewFlow = <ReaMicroBookReview>[
        ReaMicroBookReview.fromJson(<String, Object?>{
          'id': 9,
          'rating': 9,
          'comment': '很好看',
          'userName': '书评用户',
        }),
      ];
    final controller = await _createController(library, api);
    addTearDown(controller.dispose);

    final records = await controller.loadBookRecords(
      ReaMicroRecordPeriod.week,
      DateTime(2026, 11, 18),
    );
    final markBooks = await controller.loadMarkBooks();
    final hidden = await controller.hideBookRecord(8);
    final liked = await controller.setReviewLiked(9, true);
    final state = await controller.loadReviewAction(9);
    final actors = await controller.loadReviewActors(9);
    final flow = await controller.loadReviewFlow(cloudBookId: 11);
    final unliked = await controller.setReviewLiked(9, false);

    expect(records.single.progress, closeTo(0.5166, 0.0001));
    expect(markBooks.single.markCount, 5);
    expect(hidden.success, isTrue);
    expect(api.hiddenBookIds, <int>[8]);
    expect(liked.success, isTrue);
    expect(state.liked, isTrue);
    expect(actors.total, 1);
    expect(actors.items.single.userName, '点赞用户');
    expect(flow.single.rating, 9);
    expect(unliked.success, isTrue);
    expect(api.reviewActions, <bool>[true, false]);
    expect((await controller.loadReviewAction(9)).liked, isFalse);
  });
}
