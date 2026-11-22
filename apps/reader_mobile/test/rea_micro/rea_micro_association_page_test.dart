import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_manual_association.dart';
import 'package:reader_mobile/rea_micro/rea_micro_manual_association_page.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_public_reading_page.dart';

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
  bool scheduled = false;

  @override
  bool get signedIn => true;

  @override
  Future<List<ReaMicroPublicReadingGroup>> searchPublicReadingCandidates({
    required String name,
    String author = '',
  }) {
    final response = Completer<List<ReaMicroPublicReadingGroup>>();
    searches.add(response);
    return response.future;
  }

  @override
  Future<ReaMicroBookLink> registerAndLinkBook(
    String bookId, {
    ReaMicroCloudBook? cloudBook,
    ReaMicroCloudPublisher? publisher,
    ReaMicroManualAssociation? manual,
  }) async {
    saved = manual;
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
    await tester.enterText(
      find.byKey(const ValueKey('public-reading-name')),
      '新书',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('public-reading-search')),
    );
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
