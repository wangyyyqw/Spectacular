import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_manual_association.dart';
import 'package:reader_mobile/rea_micro/rea_micro_manual_association_page.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_public_reading_page.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/rea_micro/rea_micro_source_icon.dart';

final _book = BookEntry(
  id: 'book',
  title: '本地书',
  author: '作者',
  description: '本地简介',
  filePath: '',
  addedAt: DateTime(2026),
);

class _Controller extends ReaMicroController {
  _Controller()
    : super(library: LibraryStore.memory(), enableLanLoginServer: false);
  final searches = <Completer<List<ReaMicroPublicReadingGroup>>>[];
  ReaMicroManualAssociation? saved;
  ReaMicroThirdPartyBook? savedThirdParty;
  final updates = <void Function(List<ReaMicroPublicReadingGroup>)?>[];
  bool scheduled = false;

  @override
  bool get signedIn => true;

  @override
  Future<List<ReaMicroPublicReadingGroup>> searchPublicReadingCandidates({
    required String name,
    String author = '',
    void Function(List<ReaMicroPublicReadingGroup>)? onUpdate,
    void Function(String)? onSourceError,
    bool Function()? isCancelled,
  }) {
    final response = Completer<List<ReaMicroPublicReadingGroup>>();
    searches.add(response);
    updates.add(onUpdate);
    return response.future;
  }

  @override
  Future<ReaMicroBookLink> registerAndLinkBook(
    String bookId, {
    ReaMicroCloudBook? cloudBook,
    ReaMicroCloudPublisher? publisher,
    ReaMicroManualAssociation? manual,
    ReaMicroThirdPartyBook? thirdParty,
  }) async {
    saved = manual;
    savedThirdParty = thirdParty;
    return ReaMicroBookLink(
      cloudBookId: 42,
      name: manual?.name ?? cloudBook!.name,
      userBookId: 7,
      linkedAt: DateTime(2026),
    );
  }

  @override
  void scheduleReadingSync({Duration delay = const Duration(seconds: 3)}) {
    scheduled = true;
  }
}

List<ReaMicroPublicReadingGroup> _groups(String title) => [
  ReaMicroPublicReadingGroup(
    publisherName: '起点中文网',
    candidates: [
      ReaMicroPublicReadingCandidate(
        book: ReaMicroCloudBook(cloudBookId: 42, name: title),
        publisher: const ReaMicroCloudPublisher(
          publisherId: 88,
          publisher: '起点中文网',
        ),
        publisherName: '起点中文网',
      ),
    ],
  ),
];

void main() {
  testWidgets('结果三行与封面等高，出版方资料和豆瓣图片请求头完整展示', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    const publisher = ReaMicroCloudPublisher(
      publisherId: 88,
      publisher: '示例平台',
      cover: 'https://img3.doubanio.com/version.jpg',
      intro: '第一行简介\n第二行简介',
      words: '32.1万',
      status: '完结',
    );
    const candidate = ReaMicroPublicReadingCandidate(
      book: ReaMicroCloudBook(
        cloudBookId: 42,
        name: '很长的示例书名很长的示例书名',
        author: '示例作者',
      ),
      publisher: publisher,
      publisherName: '示例平台',
    );
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ReaMicroPublicReadingPage(controller: controller, book: _book),
      ),
    );
    controller.searches.single.complete([
      const ReaMicroPublicReadingGroup(
        publisherName: '阅微书库',
        candidates: [candidate],
      ),
    ]);
    await tester.pumpAndSettle();
    final coverFinder = find.byKey(
      ValueKey('public-reading-result-cover-${candidate.key}'),
    );
    final textFinder = find.byKey(
      ValueKey('public-reading-result-text-${candidate.key}'),
    );
    final cover = tester.widget<BookCoverImage>(coverFinder);
    expect(cover.book.remoteCoverUrl, publisher.cover);
    expect(cover.httpHeaders['Referer'], 'https://book.douban.com/');
    expect(
      tester.getSize(coverFinder).height,
      tester.getSize(textFinder).height,
    );
    expect(tester.getTopLeft(coverFinder).dy, tester.getTopLeft(textFinder).dy);
    final texts = find.descendant(of: textFinder, matching: find.byType(Text));
    expect(texts, findsNWidgets(3));
    for (final text in tester.widgetList<Text>(texts)) {
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
    expect(find.text('第一行简介'), findsOneWidget);
    expect(find.text('第二行简介'), findsNothing);
    expect(find.text('示例作者 · 示例平台 · 完结 · 32.1万'), findsOneWidget);
    expect(find.byType(ReaMicroSourceIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('来源卡片默认只展示第一条并可独立展开折叠', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaMicroPublicReadingPage(controller: controller, book: _book),
      ),
    );
    controller.searches.single.complete([
      for (final source in ['阅微书库', '起点中文网'])
        ReaMicroPublicReadingGroup(
          publisherName: source,
          candidates: [
            for (var id = 1; id <= 2; id++)
              ReaMicroPublicReadingCandidate(
                book: ReaMicroCloudBook(
                  cloudBookId: (source == '阅微书库' ? 0 : 10) + id,
                  name: '$source结果$id',
                ),
                publisher: const ReaMicroCloudPublisher(
                  publisherId: 88,
                  publisher: '出版方',
                ),
                publisherName: '出版方',
              ),
          ],
        ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('聚合搜索'), findsNothing);
    expect(find.text('阅微书库结果1'), findsOneWidget);
    expect(find.text('阅微书库结果2'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('public-reading-source-toggle-阅微书库')),
    );
    await tester.pumpAndSettle();
    expect(find.text('阅微书库结果2'), findsOneWidget);
    expect(find.text('起点中文网结果2'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('public-reading-source-toggle-阅微书库')),
    );
    await tester.pumpAndSettle();
    expect(find.text('阅微书库结果2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索过期响应不覆盖新结果，封面标题固定且等待时可以返回', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => ReaMicroPublicReadingPage(
                  controller: controller,
                  book: _book,
                ),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('public-reading-name')), findsNothing);
    expect(find.text('聚合搜索'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('public-reading-search')));
    await tester.pump();
    expect(controller.searches, hasLength(2));
    controller.searches[1].complete(_groups('新书结果'));
    await tester.pumpAndSettle();
    controller.searches[0].complete(_groups('旧书结果'));
    await tester.pumpAndSettle();
    final headerBefore = tester.getTopLeft(
      find.byKey(const ValueKey('public-reading-cover')),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('新书结果'), findsOneWidget);
    expect(find.text('旧书结果'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('public-reading-cover'))),
      headerBefore,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('手动表单预填元数据，校验必填后提交完整草稿并安排同步', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaMicroManualAssociationPage(
          controller: controller,
          book: _book,
        ),
      ),
    );
    expect(find.text('本地书'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manual-association-save')));
    await tester.pump();
    expect(controller.saved, isNull);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '10万');
    await tester.ensureVisible(fields.at(3));
    await tester.enterText(fields.at(3), 'https://example.com/cover.png');
    await tester.tap(find.byKey(const ValueKey('manual-association-save')));
    await tester.pumpAndSettle();
    expect(controller.saved?.name, '本地书');
    expect(controller.saved?.intro, '本地简介');
    expect(controller.saved?.wordCount, '10万');
    expect(controller.saved?.error, isNull);
    expect(controller.scheduled, isTrue);
  });

  testWidgets('平台候选可在其他源等待期间选择关联并停止搜索', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaMicroPublicReadingPage(controller: controller, book: _book),
      ),
    );
    await tester.pump();
    const third = ReaMicroThirdPartyBook(
      source: 'ciweimao_1',
      title: '平台书',
      author: '平台作者',
      publisher: '刺猬猫阅读',
      words: '10万',
      status: '连载',
    );
    controller.updates.single!([
      ReaMicroPublicReadingGroup(
        publisherName: '刺猬猫阅读',
        candidates: [third.candidate],
      ),
    ]);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('public-reading-candidate-${third.key}')),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(
      find.byKey(ValueKey('public-reading-candidate-${third.key}')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('public-reading-link')));
    await tester.pump();
    expect(controller.savedThirdParty, same(third));
    expect(controller.scheduled, isTrue);
    controller.searches.single.complete([]);
    await tester.pumpAndSettle();
  });

  test('手动关联校验拒绝白名单外平台、无效封面及过长简介', () {
    ReaMicroManualAssociation draft({
      String platform = '起点中文网',
      String cover = 'https://example.com/cover.png',
      String intro = '简介',
    }) => ReaMicroManualAssociation(
      name: '书名',
      author: '作者',
      intro: intro,
      publisher: platform,
      wordCount: '10万',
      status: '完结',
      cover: cover,
    );
    expect(draft().error, isNull);
    expect(draft(platform: '任意平台').error, '请选择支持的来源平台');
    expect(draft(cover: 'file:///cover.png').error, contains('封面'));
    expect(draft(intro: '字' * 2001).error, '简介不能超过 2000 字');
  });
}
