import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_discovery.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/home/discover_choice_dialog.dart';
import 'package:reader_mobile/home/discover_filter_dialog.dart';
import 'package:reader_mobile/home/discover_page.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/reader_pump.dart';

void main() {
  testWidgets('发现页加载分类、切换分类、去重分页并搜索，搜索栏位于按钮栏上方', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('discover-test');
    final store = BookSourceStore(directoryProvider: () async => dir);
    final requested = <Uri>[];
    final service = BookSourceService(
      cookieStore: BookSourceCookieStore(directoryProvider: () async => dir),
      httpClient: BookSourceHttpClient(
        client: MockClient((request) async {
          requested.add(request.url);
          final name = request.url.host == 'second.example.com'
              ? '第二来源书'
              : request.url.path.contains('search')
              ? '搜索书'
              : request.url.queryParameters['sort'] == 'popular'
              ? '人气书'
              : '更新书';
          return http.Response(
            jsonEncode({
              'books': [
                {
                  'name': name,
                  'author': '作者',
                  'status': '连载',
                  'url': '/book/$name',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final controller = OnlineBookController(
      library: LibraryStore.memory(),
      store: store,
      service: service,
    );
    addTearDown(() async {
      controller.dispose();
      await dir.delete(recursive: true);
    });
    await tester.runAsync(() async {
      await store.importText(
        jsonEncode({
          'bookSourceName': '测试平台',
          'bookSourceUrl': 'https://example.com',
          'searchUrl': '/search?q={{key}}',
          'enabledExplore': true,
          'ruleToc': {
            'chapterList': r'$.chapters',
            'chapterName': 'name',
            'chapterUrl': 'url',
          },
          'ruleContent': {'content': 'content'},
          'exploreUrl': '最近更新::/latest?sort=updated&page={{page}}\n人气最高::/latest?sort=popular&page={{page}}\n起点::/latest?platform=qidian&page={{page}}\n玄幻奇幻::/latest?tag=玄幻&page={{page}}\n都市修真::/latest?tag=都市&page={{page}}',
          'ruleSearch': {
            'bookList': r'$.books',
            'name': 'name',
            'author': 'author',
            'bookUrl': 'url',
          },
          'ruleExplore': {
            'bookList': r'$.books',
            'name': 'name',
            'author': 'author',
            'bookUrl': 'url',
          },
        }),
      );
      await store.importText(
        jsonEncode({
          'bookSourceName': '第二来源',
          'bookSourceUrl': 'https://second.example.com',
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': {
            'bookList': r'$.books',
            'name': 'name',
            'author': 'author',
            'bookUrl': 'url',
          },
          'enabledExplore': true,
          'exploreUrl': '推荐::/recommended',
          'ruleToc': {
            'chapterList': r'$.chapters',
            'chapterName': 'name',
            'chapterUrl': 'url',
          },
          'ruleContent': {'content': 'content'},
          'ruleExplore': {
            'bookList': r'$.books',
            'name': 'name',
            'author': 'author',
            'bookUrl': 'url',
          },
        }),
      );
      await controller.initialize();
    });
    await tester.pumpWidget(
      MaterialApp(home: DiscoverPage(controller: controller)),
    );
    await pumpReaderUntil(tester, find.text('更新书'));
    await tester.pumpAndSettle();
    expect(find.text('更新书'), findsWidgets);
    expect(find.textContaining('作者 · 连载 / '), findsOneWidget);
    final categoryText = tester.widget<Text>(find.text('最近更新'));
    final categoryTheme = Theme.of(tester.element(find.text('最近更新')));
    expect(
      categoryText.style?.fontSize,
      categoryTheme.textTheme.bodyMedium?.fontSize,
    );
    expect(
      categoryText.style?.fontFamily,
      categoryTheme.textTheme.bodyMedium?.fontFamily,
    );
    expect(categoryText.style?.fontWeight, FontWeight.w600);
    final search = find.byKey(const ValueKey('discover-search-field'));
    final toolbar = find.byKey(const ValueKey('discover-category-toolbar'));
    expect(
      tester.getRect(search).bottom,
      lessThanOrEqualTo(tester.getRect(toolbar).top),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('discover-category-picker')))
          .right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('discover-toggle-view'))).left,
      ),
    );
    tester.view.physicalSize = const Size(800, 844);
    await tester.pumpAndSettle();
    expect(find.byTooltip('分类分组'), findsNothing);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('分类分组'));
    await tester.pumpAndSettle();
    final firstChoice = find.byKey(const ValueKey('discover-choice-最近更新'));
    final nextChoice = find.byKey(const ValueKey('discover-choice-人气最高'));
    expect(tester.getRect(firstChoice).top, tester.getRect(nextChoice).top);
    expect(
      tester.getRect(nextChoice).left,
      greaterThan(tester.getRect(firstChoice).left),
    );
    await tester.tap(nextChoice);
    await pumpReaderUntil(tester, find.text('人气书'));
    await tester.pumpAndSettle();
    expect(requested.last.queryParameters['sort'], 'popular');
    await tester.tap(find.text('最近更新'));
    await pumpReaderUntil(tester, find.text('更新书'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人气最高'));
    await pumpReaderUntil(tester, find.text('人气书'));
    await tester.pumpAndSettle();
    expect(find.text('人气书'), findsWidgets);
    expect(find.text('更新书'), findsNothing);
    await tester.tap(find.text('加载更多'));
    await pumpReaderUntilComplete(
      tester,
      () =>
          find.text('加载更多').evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    expect(requested.last.queryParameters['page'], '2');
    expect(find.text('加载更多'), findsNothing);
    await tester.enterText(search, '搜索书');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpReaderUntil(tester, find.text('搜索书'));
    await tester.pumpAndSettle();
    expect(find.text('搜索书'), findsWidgets);
    expect(find.text('人气书'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('返回发现'));
    await pumpReaderUntil(tester, find.text('人气书'));
    await tester.tap(find.byTooltip('筛选管理'));
    await tester.pumpAndSettle();
    expect(find.text('筛选条件'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discover-filter-平台')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('起点').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(requested.last.queryParameters['platform'], 'qidian');
    await tester.tap(find.byTooltip('网格视图'));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('discover-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      greaterThanOrEqualTo(3),
    );
    await tester.tap(find.byTooltip('筛选管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await pumpReaderUntil(tester, find.text('第二来源书'));
    await tester.pumpAndSettle();
    expect(find.text('推荐'), findsOneWidget);
    expect(find.byTooltip('分类分组'), findsNothing);
    expect(requested.last.host, 'second.example.com');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('筛选行紧凑，标签多列选择后应用到正式查询参数', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = BookSource.fromJson({
      'bookSourceName': '测试书源',
      'bookSourceUrl': 'https://example.com',
    });
    const filter = BookDiscoverFilter(
      BookDiscoverCategory('发现', '/books?page={{page}}'),
      [
        BookDiscoverFilterGroup('排序', [
          BookDiscoverFilterOption('最新', {'sort': 'updated'}),
        ]),
        BookDiscoverFilterGroup('平台', [BookDiscoverFilterOption('全部', {})]),
        BookDiscoverFilterGroup('分类', [BookDiscoverFilterOption('全部', {})]),
        BookDiscoverFilterGroup('标签', [
          BookDiscoverFilterOption('全部', {}),
          BookDiscoverFilterOption('凡人流', {'tag': '凡人流'}),
          BookDiscoverFilterOption('这个标签名称比较长需要完整换行显示', {'tag': '长标签'}),
        ]),
      ],
    );
    DiscoverFilterResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<DiscoverFilterResult>(
                context: context,
                builder: (_) => DiscoverFilterDialog(
                  sources: [source],
                  source: source,
                  filterFor: (_) => filter,
                  selections: const {},
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final sourceName = find.byKey(
      ValueKey('discover-source-name-${source.id}'),
    );
    final sourceArrow = find.byKey(const ValueKey('discover-source-arrow'));
    expect(
      tester.getRect(sourceArrow).left - tester.getRect(sourceName).right,
      inInclusiveRange(0, 8),
    );
    final sort = find.byKey(const ValueKey('discover-filter-排序'));
    final platform = find.byKey(const ValueKey('discover-filter-平台'));
    expect(tester.getRect(sourceArrow).right, tester.getRect(platform).right);
    expect(tester.getSize(sort).height, 44);
    expect(tester.getRect(sort).bottom, tester.getRect(platform).top);
    await tester.tap(find.byKey(const ValueKey('discover-filter-标签')));
    await tester.pumpAndSettle();
    final all = find.byKey(const ValueKey('discover-choice-全部'));
    final fanren = find.byKey(const ValueKey('discover-choice-凡人流'));
    expect(tester.getRect(all).top, tester.getRect(fanren).top);
    expect(tester.getRect(all).right, lessThan(tester.getRect(fanren).left));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('discover-choice-这个标签名称比较长需要完整换行显示')),
          )
          .height,
      greaterThan(tester.getSize(all).height),
    );
    await tester.tap(fanren);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result?.selection['标签'], '凡人流');
    expect(Uri.parse(result!.category!.url).queryParameters['tag'], '凡人流');
    expect(tester.takeException(), isNull);
  });

  testWidgets('多列选项在放大字号时完整换行且仍可选择', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const DiscoverChoiceDialog<String>(
          title: '分类分组',
          options: ['短名称', '这个分类分组名称比较长需要完整换行显示'],
          labelFor: _label,
        ),
      ),
    );
    expect(find.text('这个分类分组名称比较长需要完整换行显示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String _label(String value) => value;
