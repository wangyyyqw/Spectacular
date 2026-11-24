import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';
import 'package:reader_ui/annotations/annotation.dart';

class _CloudNotesLibrary extends LibraryStore {
  _CloudNotesLibrary({this.book, this.annotation}) : super.memory();

  final BookEntry? book;
  ReaderAnnotation? annotation;

  @override
  Future<void> removeBookAnnotation(String bookId, String annotationId) async {
    if (annotation?.id == annotationId) annotation = null;
  }

  @override
  Future<List<BookEntry>> list() async => [?book];

  @override
  Future<BookEntry?> bookById(String id) async => book;

  @override
  Future<List<ReaderAnnotation>> listBookAnnotations(String id) async => [
    ?annotation,
  ];

  @override
  Future<Map<String, BookNoteCounts>> bookNoteCounts() async => {
    if (book != null && annotation != null)
      book!.id: (thoughts: 1, marks: 0, updatedAt: annotation!.updatedAt),
  };
}

class _CloudNotesApi implements ReaMicroApiClient {
  _CloudNotesApi({required this.markBook, required this.mark});

  final ReaMicroMarkBook markBook;
  final ReaMicroMark mark;
  final deleted = <int>[];

  @override
  Future<void> deleteMark(String token, {required int id}) async {
    deleted.add(id);
  }

  @override
  Future<ReaMicroUser> fetchUser(String token) async =>
      const ReaMicroUser(id: 1, nickName: '测试用户');

  @override
  Future<List<ReaMicroChartPoint>> fetchReadTimeChart(
    String token, {
    int limit = 30,
  }) async => const <ReaMicroChartPoint>[];

  @override
  Future<List<ReaMicroMarkBook>> fetchMarkBooks(String token) async =>
      <ReaMicroMarkBook>[markBook];

  @override
  Future<List<ReaMicroMark>> fetchMarks(
    String token, {
    String? bookId,
    int pageSize = 200,
  }) async {
    if (bookId == mark.bookId && !deleted.contains(mark.id)) {
      return <ReaMicroMark>[mark];
    }
    return const <ReaMicroMark>[];
  }

  @override
  Future<ReaMicroS3CloudConfigResponse> fetchS3CloudConfig(
    String token,
  ) async =>
      const ReaMicroS3CloudConfigResponse(enabled: false, encryptedConfig: '');

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在测试中实现');
}

class _CloudEditApi extends _CloudNotesApi {
  _CloudEditApi()
    : super(
        markBook: const ReaMicroMarkBook(
          bookId: 8,
          cloudBookId: 11,
          name: '云端书评',
          author: '',
          cover: '',
          thoughtCount: 0,
          underlineCount: 0,
        ),
        mark: ReaMicroMark(
          id: 31,
          bookId: '8',
          chapter: '',
          kind: 0,
          startCfi: '',
          endCfi: '',
          quote: '',
          note: '',
          style: 0,
          color: '',
          synced: 1,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
  bool fail = false;
  final submissions =
      <
        ({
          int? bookId,
          int? cloudBookId,
          int rating,
          String comment,
          bool publish,
        })
      >[];
  ReaMicroMilestone milestone = ReaMicroMilestone.fromJson({
    'id': 7,
    'cloudBookId': 11,
    'name': '云端书评',
    'rating': 9,
    'comment': '',
    'status': 1,
  });
  @override
  Future<List<ReaMicroMilestone>> fetchMilestones(
    String token, {
    int pageSize = 100,
  }) async => [milestone];
  @override
  Future<void> rateReview(
    String token, {
    int? bookId,
    int? cloudBookId,
    required int rating,
    required String comment,
    required bool publish,
  }) async {
    if (fail) throw const ReaMicroException('网络断开');
    submissions.add((
      bookId: bookId,
      cloudBookId: cloudBookId,
      rating: rating,
      comment: comment,
      publish: publish,
    ));
    milestone = ReaMicroMilestone.fromJson({
      'id': 7,
      'cloudBookId': 11,
      'name': '云端书评',
      'rating': rating,
      'comment': comment,
      'status': publish ? 2 : 1,
    });
  }
}

void main() {
  testWidgets('云端书可编辑发布，失败保留草稿，未修改评分保留十分制原值', (tester) async {
    final library = _CloudNotesLibrary();
    final api = _CloudEditApi();
    await ReaMicroStore(library).saveToken('token');
    final controller = ReaMicroController(
      library: library,
      api: api,
      enableLanLoginServer: false,
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewsPage(library: library, reaMicro: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('书评'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('review-pending-rea-cloud-review-11')),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('review-content'));
    expect(tester.widget<TextField>(input).maxLength, 2000);
    await tester.enterText(input, '新评价正文');
    await tester.ensureVisible(find.byKey(const ValueKey('review-publish')));
    await tester.tap(find.byKey(const ValueKey('review-publish')));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.ensureVisible(find.byKey(const ValueKey('review-save')));
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-editor')), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '新评价正文');
    expect(find.text('网络断开'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await tester.pumpAndSettle();
    expect(api.submissions.single.cloudBookId, 11);
    expect(api.submissions.single.rating, 9);
    expect(api.submissions.single.publish, isTrue);
    expect(api.submissions.single.comment, '新评价正文');
    expect(find.byKey(const ValueKey('review-editor')), findsNothing);
    expect(
      find.byKey(const ValueKey('review-card-rea-cloud-review-11')),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('没有云端映射的旧局域网想法显示本地并可删除', (tester) async {
    final now = DateTime(2026);
    final library = _CloudNotesLibrary(
      book: BookEntry(
        id: 'retained',
        title: '本地旧书',
        author: '',
        filePath: '',
        addedAt: now,
      ),
      annotation: ReaderAnnotation(
        id: 'mark-lan-1-epubcfi(/6/24/4/6/1/1:0)-epubcfi(/6/24/4/6/1/1:16)',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/24/4/6/1/1:0)',
        endCfi: 'epubcfi(/6/24/4/6/1/1:16)',
        quote: '原文',
        note: '测试旧想法',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: ReviewsPage(library: library)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地旧书'));
    await tester.pumpAndSettle();
    expect(find.text('本地'), findsOneWidget);
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('测试旧想法'), findsNothing);
    expect(library.annotation, isNull);
  });

  for (final imported in [false, true]) {
    testWidgets(imported ? '已导入且 CFI 转换的云端想法在笔记页只显示一次' : '云端笔记书打开后显示正文而不是空状态', (
      tester,
    ) async {
      final now = DateTime(2026);
      final library = _CloudNotesLibrary(
        book: imported
            ? BookEntry(
                id: 'local',
                title: '仅云端笔记',
                author: '阅微作者',
                filePath: '',
                addedAt: now,
              )
            : null,
        annotation: imported
            ? ReaderAnnotation(
                id: 'mark-cloud-31',
                type: ReaderAnnotationType.thought,
                startCfi: 'epubcfi(/6/2!/4/2/1:4)',
                endCfi: 'epubcfi(/6/2!/4/2/1:12)',
                quote: '被划线的原文',
                note: '云端笔记正文',
                createdAt: now,
                updatedAt: now,
              )
            : null,
      );
      final api = _CloudNotesApi(
        markBook: const ReaMicroMarkBook(
          bookId: 8,
          cloudBookId: 11,
          name: '仅云端笔记',
          author: '阅微作者',
          cover: 'https://cdn.reamicro.test/cloud-note.jpg',
          thoughtCount: 1,
          underlineCount: 0,
        ),
        mark: ReaMicroMark(
          id: 31,
          bookId: '8',
          chapter: '第一章',
          kind: 1,
          startCfi: 'epubcfi(/6/2/4/2/1/1:4)',
          endCfi: 'epubcfi(/6/2/4/2/1/1:12)',
          quote: '被划线的原文',
          note: '云端笔记正文',
          style: 0,
          color: '',
          synced: 1,
          createdAt: DateTime(2026).millisecondsSinceEpoch,
          updatedAt: DateTime(2026).millisecondsSinceEpoch,
        ),
      );
      await ReaMicroStore(library).saveToken('token');
      final controller = ReaMicroController(
        library: library,
        api: api,
        enableLanLoginServer: false,
      );
      var disposed = false;
      void disposeController() {
        if (disposed) return;
        disposed = true;
        controller.dispose();
      }

      addTearDown(disposeController);
      await controller.initialize();

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewsPage(library: library, reaMicro: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('想法 1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is BookCoverImage
              ? widget.book.remoteCoverUrl ==
                    'https://cdn.reamicro.test/cloud-note.jpg'
              : false,
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('仅云端笔记'));
      await tester.pumpAndSettle();

      expect(find.text('云端笔记正文'), findsOneWidget);
      expect(find.text('被划线的原文'), findsOneWidget);
      expect(find.text('这本书还没有笔记'), findsNothing);
      expect(find.text('本地'), findsNothing);
      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();
      expect(api.deleted, [31]);
      expect(find.text('云端笔记正文'), findsNothing);
      disposeController();
    });
  }
}
