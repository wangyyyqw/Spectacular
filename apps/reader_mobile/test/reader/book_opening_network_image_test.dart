import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import 'support/css_chapter_book.dart';

void main() {
  testWidgets('阅读页传入应用缓存目录，关闭重开后离线显示网络图片', (tester) async {
    final originalOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = originalOverrides);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('reader-page-network-'),
    ))!;
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    final address = 'http://127.0.0.1:${server.port}/photo.png';
    var requests = 0;
    await tester.runAsync(() async {
      server.listen((request) {
        requests += 1;
        request.response.add(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg6GD4DwACnAGIgL4sqAAAAABJRU5ErkJggg==',
          ),
        );
        unawaited(request.response.close());
      });
    });
    final bytes = buildCssChapterBook(
      body: '<p>附近正文</p><img src="$address" style="width:72px;height:54px"/>',
    );
    final file = (await tester.runAsync(
      () => File('${root.path}/book.epub').writeAsBytes(bytes),
    ))!;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => root.path,
    );
    Completer<void>? closing;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      if (closing != null) await pumpReaderTask(tester, closing!.future);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      await tester.runAsync(() async {
        await server.close(force: true);
        await root.delete(recursive: true);
      });
    });
    final store = MemoryReaderProgressStore();

    Future<void> showImage() async {
      closing = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: EpubReaderPage(
            sourcePath: file.path,
            contentRevision: 'network-image-page',
            bookId: 'network-image-page',
            store: store,
            onClosed: closing!.complete,
          ),
        ),
      );
      await pumpReaderUntilComplete(tester, () {
        final pages = find.byType(ReaderPage).evaluate();
        if (pages.isEmpty) return false;
        return (pages.single.widget as ReaderPage).imageCache?.lookup(
              address,
            ) !=
            null;
      }, description: '阅读页网络图片解码');
    }

    await showImage();
    expect(requests, 1);
    final files = (await tester.runAsync(
      () => Directory('${root.path}/epub_network_images').list().toList(),
    ))!;
    expect(files, hasLength(1), reason: '阅读页必须使用 path_provider 提供的应用目录');
    await tester.pumpWidget(const SizedBox());
    await pumpReaderTask(tester, closing!.future);
    await tester.runAsync(() => server.close(force: true));
    await showImage();
    expect(requests, 1, reason: '新来源和新解码缓存应直接复用持久字节');
    expect(tester.takeException(), isNull);
  });
}
