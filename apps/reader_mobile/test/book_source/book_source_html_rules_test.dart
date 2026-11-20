import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';

import 'book_source_test_helpers.dart';

void main() {
  test('HTML 规则走搜索、详情、目录与逐章分页，保留段落和插图', () async {
    final dist = await Directory('dist').absolute.create(recursive: true);
    final temporary = await dist.createTemp('book-source-html-rules-');
    addTearDown(() async {
      // 临时目录由本测试在 dist 中创建，删除前核对绝对路径。
      expect(
        temporary.absolute.path.startsWith(
          '${dist.path}${Platform.pathSeparator}',
        ),
        isTrue,
      );
      await temporary.delete(recursive: true);
    });
    final cookieStore = BookSourceCookieStore(
      directoryProvider: () async => temporary,
    );
    final requests = <String>[];
    final service = BookSourceService(
      cookieStore: cookieStore,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => temporary,
      ),
      scriptFactory: fakeScriptFactory(
        FakeBookSourceScriptSession(
          (code, result, variables, session) => result,
        ),
      ),
      httpClient: BookSourceHttpClient(
        cookieStore: cookieStore,
        client: MockClient((request) async {
          requests.add(request.url.path);
          final body = switch (request.url.path) {
            '/search' =>
              '''
<article class="book">
  <a class="title" href="/detail/one">连续阅读示例</a>
  <span class="author">示例作者</span>
  <img class="cover" src="/covers/one.jpg">
</article>
<article class="book">
  <a class="title" href="/detail/two">另一部作品</a>
  <span class="author">另一作者</span>
</article>
''',
            '/detail/one' =>
              '''
<main id="detail">
  <h1>连续阅读示例</h1><span class="author">示例作者</span>
  <div class="intro">简介第一段<br>简介第二段</div>
  <a class="toc" href="/toc/one">完整目录</a>
</main>
''',
            '/toc/one' =>
              '''
<section id="chapters">
  <a href="/chapter/1.html">第一章</a>
  <a href="/chapter/2.html">第二章</a>
</section>
''',
            '/chapter/1.html' =>
              '''
<div class="content"><p>第一段含有<em>强调文本</em>。广告</p><p>第二段。</p>
<img src="../images/one.png"></div><a class="next" href="1_2.html">下一页</a>
''',
            '/chapter/1_2.html' =>
              '''
<div class="content"><p>第三段。</p></div>
<a class="next" href="2.html">下一章</a>
''',
            '/chapter/2.html' => '<div class="content"><p>第二章正文。</p></div>',
            _ => throw StateError('出现意外请求：${request.url}'),
          };
          return http.Response(
            body,
            200,
            headers: const {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    const source = BookSource(
      id: 'html-source',
      name: 'HTML 测试源',
      sourceUrl: 'https://example.com',
      searchUrl: 'https://example.com/search?q={{key}}',
      search: BookListRule(
        bookList: '@css:.book',
        name: '.title@text',
        author: '.author@text',
        bookUrl: '.title@href',
        coverUrl: '.cover@src',
      ),
      bookInfo: BookInfoRule(
        init: 'id.detail',
        name: 'tag.h1@text',
        author: 'class.author@text',
        intro: 'class.intro@textNodes',
        tocUrl: 'class.toc@href',
      ),
      toc: TocRule(
        chapterList: 'id.chapters@tag.a',
        chapterName: 'text',
        chapterUrl: 'href',
      ),
      content: ContentRule(
        content: '.content##广告##',
        nextContentUrl: '.next@href',
      ),
    );

    final books = await service.search(source, '连续阅读示例');
    expect(books.map((book) => book.name), ['连续阅读示例', '另一部作品']);
    expect(books.first.author, '示例作者');
    expect(books.first.bookUrl, 'https://example.com/detail/one');
    expect(books.first.coverUrl, 'https://example.com/covers/one.jpg');
    final detail = await service.loadBookInfo(source, books.first);
    expect(detail.tocUrl, 'https://example.com/toc/one');
    expect(detail.intro, '简介第一段\n简介第二段');
    final chapters = await service.fetchToc(source, detail);
    expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章']);

    final first = await service.fetchChapterContent(
      source,
      chapters.first,
      detail.bookUrl,
      nextChapter: chapters.last,
    );
    final fragment = html_parser.parseFragment(first);
    expect(first, isNot(contains('广告')));
    expect(fragment.querySelectorAll('p').map((node) => node.text), [
      '第一段含有强调文本。',
      '第二段。',
      '第三段。',
    ]);
    expect(fragment.querySelector('em')?.text, '强调文本');
    expect(
      fragment.querySelector('img')?.attributes['src'],
      'https://example.com/images/one.png',
    );
    expect(requests, [
      '/search',
      '/detail/one',
      '/toc/one',
      '/chapter/1.html',
      '/chapter/1_2.html',
    ]);

    final second = await service.fetchChapterContent(
      source,
      chapters.last,
      detail.bookUrl,
    );
    expect(
      html_parser.parseFragment(second).querySelector('p')?.text,
      '第二章正文。',
    );
    expect(requests.last, '/chapter/2.html');
  });
}
