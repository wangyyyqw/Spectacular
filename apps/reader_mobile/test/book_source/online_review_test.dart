import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';
import 'package:reader_mobile/book_source/online_reading_book.dart';
import 'package:reader_mobile/book_source/online_review.dart';
import 'package:reader_mobile/book_source/online_review_launcher.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('热度与最新排序切换服务端参数并重置分页，不改不支持排序的页面', () {
    const page =
        '<script>var offset="0",pageSize=30;'
        'function apiUrl(){return "https://example.test?offset="+offset+"&sort=1&api_key="+key;}'
        'async function load(){}more.onclick=load;</script>';
    final sorted = prepareOnlineReviewPage(page);
    expect(sorted, contains('"&sort="+reviewSort+"&api_key="'));
    expect(sorted, contains('段评排序'));
    expect(
      sorted,
      contains(
        'reviewSort=Number(button.dataset.sort);offset="0";ended=false;loaded=0;total=0;',
      ),
    );
    expect(prepareOnlineReviewPage('<p>普通网页</p>'), '<p>普通网页</p>');
  });

  test('源直接拼接 JSON 引号的段评图片保留脚本大小写和 SVG 数量', () {
    final svg = base64Encode(utf8.encode('<svg><text x="0">123</text></svg>'));
    final raw =
        '第一章\n第一段<img src="data:image/svg+xml;base64,$svg,'
        '{"style":"TEXT","click":"showCmt(1,2,0)","extra":"<p>内层 HTML</p>"}" alt="段评">\n第二段';
    final prepared = prepareOnlineReviewHtml(raw);
    expect(prepared, contains('[123]'));
    final fragment = html_parser.parseFragment(prepared);
    final href = fragment.querySelector('a')!.attributes['href']!;
    expect(OnlineReviewAction.fromHref(href)!.script, 'showCmt(1,2,0)');
    expect(prepared, contains('\n第二段'));
  });
  late Directory directory;
  late BookSourceService service;
  late BookSource source;
  late OnlineReadingBook book;
  final requests = <String>[];
  const script = '''
var comments = JSON.parse(java.ajax('https://example.test/reviews')).text;
java.showBrowser('https://example.test/comment',
 '<p>'+book.name+':'+chapter.index+':'+comments+'</p>',
 'window.loaded=true', '{"height":70}');
''';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('online-review-');
    requests.clear();
    source = BookSource.fromJson({
      'bookSourceName': '段评测试源',
      'bookSourceUrl': 'https://example.test',
      'header': {'X-Source': 'review'},
      'ruleContent': {'content': r'$.content'},
    });
    final cookies = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    await cookies.saveLoginCookies('example.test', {
      'session': 'retained',
    }, source: source);
    service = BookSourceService(
      cookieStore: cookies,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => directory,
      ),
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          requests.add(request.url.path);
          expect(request.headers['cookie'], contains('session=retained'));
          return http.Response(
            jsonEncode(
              request.url.path == '/reviews'
                  ? {'text': '这是一条书源段评'}
                  : {
                      'content':
                          '<p>保留原文与段落位置<img src="dp:12,${jsonEncode({'click': script}).replaceAll('&', '&amp;').replaceAll('"', '&quot;')}"/>后续正文。</p>',
                    },
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    book = OnlineReadingBook(
      source: source,
      book: OnlineBook(
        sourceId: source.id,
        sourceName: source.name,
        name: '段评测试书',
        author: '作者',
        bookUrl: 'https://example.test/book',
      ),
      chapters: const [
        OnlineChapter(
          index: 0,
          title: '第一章',
          url: 'https://example.test/chapter',
        ),
      ],
      service: service,
    );
  });
  tearDown(() async {
    service.dispose();
    await service.chapterRequestsStopped;
    await directory.delete(recursive: true);
  });

  test('正式 JS 动作重放远程请求，保留书章上下文、展示参数与源请求头', () async {
    final page = await service.openReview(
      source,
      book.book,
      book.chapters.single,
      const OnlineReviewAction(src: 'dp:12', script: script),
    );
    expect(requests, ['/reviews']);
    expect(page.html, contains('段评测试书:0:这是一条书源段评'));
    expect(page.preloadJs, 'window.loaded=true');
    expect(page.headers['X-Source'], 'review');
    expect(page.headers['Referer'], 'https://example.test/chapter');
  });

  test('段评独立会话读取正文保存的内存原文，重开缓存正文后也可恢复', () async {
    final memorySource = BookSource.fromJson({
      ...source.toJson(),
      'jsLib':
          'function show(){java.showBrowser("https://example.test/comment",'
          '"<p>"+cache.getFromMemory("paragraph")+"</p>","","{}");}',
      'ruleContent': {
        'content': r'$.content@js:cache.putMemory("paragraph",result);result;',
      },
    });
    const action = OnlineReviewAction(src: 'dp:12', script: 'show()');
    await service.fetchChapterContent(
      memorySource,
      book.chapters.single,
      book.book.bookUrl,
    );
    final page = await service.openReview(
      memorySource,
      book.book,
      book.chapters.single,
      action,
    );
    expect(page.html, contains('保留原文与段落位置'));
    service.invalidateSourceSettings();
    requests.clear();
    final reopened = await service.openReview(
      memorySource,
      book.book,
      book.chapters.single,
      action,
    );
    expect(reopened.html, contains('保留原文与段落位置'));
    expect(requests, contains('/chapter'));
  });

  testWidgets('正式引擎生成可命中段评，点击交给宿主且不翻页、不打开脚注', (tester) async {
    final html = await tester.runAsync(
      () => service.fetchChapterContent(
        source,
        book.chapters.single,
        book.book.bookUrl,
      ),
    );
    final prepared = prepareOnlineReviewHtml(html!);
    final xhtml = const OnlineEpubBuilder().buildChapterDocument(
      OnlineEpubChapter(title: '第一章', html: prepared),
    );
    final anchors = FootnoteParser.parse(
      spineIndex: 0,
      path: 'text/chapter_0.xhtml',
      xhtml: xhtml,
    );
    expect(anchors.anchors, isNotEmpty, reason: xhtml);
    final opened = book.open();
    ReaderSession? session;
    String? clicked;
    int? spine;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: opened,
            bookId: book.id,
            store: MemoryReaderProgressStore(),
            contentRevision: book.revision,
            showPageFooter: false,
            padding: EdgeInsets.zero,
            overrides: const ReaderOverrides(),
            onSessionReady: (value) => session = value,
            onContentAction: (index, href) {
              spine = index;
              clicked = href;
              return true;
            },
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(requests, ['/chapter']);
    final page = session!.page!;
    final boxes = TextHitTester.lineBoxes(page);
    final box = boxes.firstWhere(
      (box) => box.slice.block.footnotes.any(
        (note) =>
            note.actionHref != null &&
            note.start >= box.blockTextOffset &&
            note.start < box.blockTextOffset + box.text.length,
      ),
    );
    final note = box.slice.block.footnotes.firstWhere(
      (note) => note.actionHref != null,
    );
    final block = box.slice.block;
    expect(block.layout.text.substring(note.start, note.end), '[12]');
    final badge = block.layout.runs.firstWhere(
      (run) => run.start <= note.start && run.end >= note.end,
    );
    expect(badge.style.color, const Color(0xff2878c8));
    expect(badge.style.fontSize, closeTo(block.style!.fontSize * .75, .01));
    expect(badge.baselineShift, lessThan(0));
    final rects = TextHitTester.selectionRects(
      box,
      note.start - box.blockTextOffset,
      note.end - box.blockTextOffset,
    );
    final point = rects.first.center + box.rect.topLeft;
    expect(TextHitTester.footnoteAt(page, point)?.actionHref, note.actionHref);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(find.byType(ReaderView)) + point);
    await tester.pumpAndSettle();
    expect(spine, 0);
    expect(OnlineReviewAction.fromHref(clicked!)?.script, script.trim());
    expect(find.byType(ReaderFootnoteDialog), findsNothing);
    expect(session!.page!.pageIndex, page.pageIndex);
    expect(requests, ['/chapter']);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      opened.close();
      await opened.preparationsStopped;
    });
  });

  test('原生面板接收 Cookie 和 HTML，返回后只更新该源 Cookie', () async {
    const channel = MethodChannel(
      'com.spectacular.reader_mobile/online_review',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map<Object?, Object?>;
          expect(args['cookie'], 'session=retained');
          expect(args['html'], '<p>段评</p>');
          return {
            'url': 'https://example.test/comment',
            'cookie': 'session=updated',
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await const OnlineReviewLauncher().show(
      source,
      service,
      const OnlineReviewPage(
        url: 'https://example.test/comment',
        html: '<p>段评</p>',
      ),
    );
    expect(
      service.cookieStore.cookieValue('example.test', 'session'),
      'updated',
    );
  });

  test('无动作图片和正文保持原样，损坏动作拒绝解析', () {
    const html = '<p>普通正文<img src="https://example.test/image.png"/></p>';
    expect(prepareOnlineReviewHtml(html), html);
    expect(OnlineReviewAction.fromHref('reader-review:broken'), isNull);
    const svg = 'data:image/svg+xml;base64,c3Zn';
    final prepared = prepareOnlineReviewHtml(
      '<p><img src="$svg,${jsonEncode({'pclick': '', 'click': 'java.showBrowser(baseUrl)'}).replaceAll('"', '&quot;')}"/></p>',
    );
    expect(prepared, contains('data-reader-action="true"'));
    expect(prepared, contains('[段评]'));
  });
}
