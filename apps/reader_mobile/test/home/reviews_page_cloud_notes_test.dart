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
  final ReaderAnnotation? annotation;

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
    if (bookId == mark.bookId) return <ReaMicroMark>[mark];
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

void main() {
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
      disposeController();
    });
  }
}
