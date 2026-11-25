import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_ui/reader_session.dart';

class _Reviews implements BookReviewStore {
  Map<String, BookReview> values = {};
  @override
  Future<Map<String, BookReview>> snapshot() async => values;
  @override
  Future<void> save(
    String bookId, {
    num? rating,
    required String content,
  }) async {}
  @override
  Future<void> remove(String bookId) async {}
}

class _Library extends LibraryStore {
  _Library() : super.memory();
  final reviews = _Reviews();
  @override
  BookReviewStore reviewStore() => reviews;
}

class _Api implements ReaMicroApiClient {
  List<ReaMicroMilestone> milestones = [];
  ReaMicroBookReview? review;
  bool failUpload = false;
  final uploads =
      <
        ({
          int? bookId,
          int? cloudBookId,
          int rating,
          String comment,
          bool publish,
        })
      >[];
  @override
  Future<ReaMicroUser> fetchUser(String token) async =>
      const ReaMicroUser(id: 1, nickName: '测试');
  @override
  Future<List<ReaMicroChartPoint>> fetchReadTimeChart(
    String token, {
    int limit = 30,
  }) async => [];
  @override
  Future<ReaMicroS3CloudConfigResponse> fetchS3CloudConfig(
    String token,
  ) async =>
      const ReaMicroS3CloudConfigResponse(enabled: false, encryptedConfig: '');
  @override
  Future<List<ReaMicroMilestone>> fetchMilestones(
    String token, {
    int pageSize = 100,
  }) async => milestones.toList();
  @override
  Future<ReaMicroBookReview?> fetchBookReview(
    String token, {
    int? bookId,
    int? cloudBookId,
  }) async => review;
  @override
  Future<void> rateReview(
    String token, {
    int? bookId,
    int? cloudBookId,
    required int rating,
    required String comment,
    required bool publish,
  }) async {
    if (failUpload) throw const ReaMicroException('网络断开');
    uploads.add((
      bookId: bookId,
      cloudBookId: cloudBookId,
      rating: rating,
      comment: comment,
      publish: publish,
    ));
    review = ReaMicroBookReview.fromJson({
      'id': 7,
      'rating': rating,
      'comment': comment,
      'status': publish ? 2 : 1,
    });
    milestones = [
      ReaMicroMilestone.fromJson({
        'id': 7,
        'cloudBookId': cloudBookId,
        'rating': rating,
        'comment': comment,
      }),
    ];
  }

  @override
  Future<void> deleteMilestone(
    String token, {
    required int milestoneId,
  }) async => milestones.removeWhere((m) => m.id == milestoneId);
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _position = ReaderProgress(
  spineIndex: 3,
  pageIndex: 5,
  cfi: 'epubcfi(/6/8!/4/2:3)',
  readingPercent: .42,
  chapterTitle: '第四章',
);
Future<ReaMicroController> _controller(
  _Library library,
  _Api api,
  MemoryReaderProgressStore progress,
) async {
  await ReaMicroStore(library).saveToken('测试令牌');
  final controller = ReaMicroController(
    library: library,
    api: api,
    progressStore: progress,
    enableLanLoginServer: false,
  );
  await controller.initialize();
  return controller;
}

ReaMicroCloudBook _cloudBook() =>
    ReaMicroCloudBook.fromJson({'cloudBookId': 11, 'name': '关联书'});

void main() {
  test('读完评价预填阅微半星，保存半星和正文保留公开状态', () async {
    final library = _Library();
    final api = _Api()
      ..review = ReaMicroBookReview.fromJson({
        'id': 7,
        'rating': 7,
        'comment': '已有阅微评价',
        'status': 2,
      });
    final progress = MemoryReaderProgressStore();
    await progress.save('local', _position);
    final controller = await _controller(library, api, progress);
    addTearDown(controller.dispose);
    await controller.linkBook('local', _cloudBook(), userBookId: 8);
    final review = await controller.loadFinishedReview('local');
    expect(review!.rating, 3.5);
    expect(review.content, '已有阅微评价');
    await controller.saveFinishedReview('local', 4.5, '调整后的评价');
    expect(api.uploads.last.rating, 9);
    expect(api.uploads.last.comment, '调整后的评价');
    expect(api.uploads.last.publish, isTrue);
  });

  test('本地标记读完后自动队列上传双 ID、评分并保留云端正文和发布状态', () async {
    final library = _Library();
    final api = _Api()
      ..review = ReaMicroBookReview.fromJson({
        'id': 7,
        'rating': 6,
        'comment': '已有公开正文',
        'status': 2,
      });
    final progress = MemoryReaderProgressStore();
    await progress.save('local', _position);
    final controller = await _controller(library, api, progress);
    addTearDown(controller.dispose);
    await controller.linkBook('local', _cloudBook(), userBookId: 8);
    await controller.trackedProgressStore!.save(
      'local',
      _position.withFinished(true),
    );
    final now = DateTime.now();
    library.reviews.values['local'] = BookReview(
      bookId: 'local',
      rating: 4,
      content: '',
      createdAt: now,
      updatedAt: now,
    );
    expect((await controller.syncFinishedBooks()).success, isTrue);
    expect(api.uploads.single, (
      bookId: 8,
      cloudBookId: 11,
      rating: 8,
      comment: '已有公开正文',
      publish: true,
    ));
    expect(await ReaMicroStore(library).loadPendingFinished(), isEmpty);
    await controller.syncFinishedBooks();
    expect(api.uploads, hasLength(1));
    expect(await progress.load('local'), _position.withFinished(true));
  });

  test('云端读完与取消读完同步到本地，保存的文本位置保持不变', () async {
    final library = _Library();
    final api = _Api()
      ..milestones = [
        ReaMicroMilestone.fromJson({'id': 7, 'cloudBookId': 11}),
      ];
    final progress = MemoryReaderProgressStore();
    await progress.save('local', _position);
    final controller = await _controller(library, api, progress);
    addTearDown(controller.dispose);
    await controller.linkBook('local', _cloudBook(), userBookId: 8);
    await controller.syncFinishedBooks();
    expect(await progress.load('local'), _position.withFinished(true));
    api.milestones = [];
    await controller.syncFinishedBooks();
    expect(await progress.load('local'), _position);
    expect(api.uploads, isEmpty);
  });

  test('离线读完保存待传状态，重启后补传评分，不回退本地读完状态', () async {
    final library = _Library();
    final api = _Api()..failUpload = true;
    final progress = MemoryReaderProgressStore();
    await progress.save('local', _position);
    var controller = await _controller(library, api, progress);
    await controller.linkBook('local', _cloudBook(), userBookId: 8);
    await controller.trackedProgressStore!.save(
      'local',
      _position.withFinished(true),
    );
    expect((await controller.syncFinishedBooks()).success, isFalse);
    expect(
      (await ReaMicroStore(library).loadPendingFinished())['local'],
      greaterThan(0),
    );
    expect((await progress.load('local'))?.finished, isTrue);
    controller.dispose();
    api.failUpload = false;
    controller = await _controller(library, api, progress);
    addTearDown(controller.dispose);
    await controller.syncFinishedBooks();
    expect(api.uploads, hasLength(1));
    expect(await ReaMicroStore(library).loadPendingFinished(), isEmpty);
  });

  test('关联时已有本地读完状态先上传，后续本地取消同步云端', () async {
    final library = _Library();
    final api = _Api();
    final progress = MemoryReaderProgressStore();
    await progress.save('local', _position.withFinished(true));
    final controller = await _controller(library, api, progress);
    addTearDown(controller.dispose);
    await controller.linkBook('local', _cloudBook(), userBookId: 8);
    await controller.syncFinishedBooks();
    expect(api.uploads, hasLength(1));
    await controller.trackedProgressStore!.save('local', _position);
    await controller.syncFinishedBooks();
    expect(api.milestones, isEmpty);
    expect(await progress.load('local'), _position);
  });
}
