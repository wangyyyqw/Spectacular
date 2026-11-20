import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show BookMeta;
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

class _ChapterLoader {
  final failures = <int, Object>{};
  final gates = <int, Completer<void>>{};
  final requested = <int>[];
  final completed = <int>[];

  Future<String> load(int spine) async {
    requested.add(spine);
    try {
      await gates[spine]?.future;
      final failure = failures[spine];
      if (failure != null) throw failure;
      return '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<p id="content">这是第 ${spine + 1} 章的稳定正文。'
          '用于错误提示、重新加载和阅读位置的验收。</p></body></html>';
    } finally {
      completed.add(spine);
    }
  }
}

/// 正式解析作业包含 isolate 消息，同时交付测试时钟与真实事件循环。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  String description = '阅读任务',
}) async {
  for (var frame = 0; frame < 100; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (ready()) {
      await tester.pump();
      return;
    }
  }
  fail('$description 未完成');
}

Future<void> _openMenu(WidgetTester tester) async {
  final menu = tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay));
  if (!menu.open) await tester.tap(find.byType(ReaderView));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<({ReaderSession session, EpubChapterSource source})> _open(
  WidgetTester tester,
  _ChapterLoader loader, {
  int initialSpine = 0,
  bool menu = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final source = EpubChapterSource.fromChapterLoader(
    meta: const BookMeta(
      title: '逐章加载失败回归',
      author: '测试作者',
      language: 'zh-CN',
      identifier: 'chapter-errors',
    ),
    chapterTitles: const ['第一章', '第二章', '第三章'],
    loadChapterXhtml: loader.load,
  );
  final store = MemoryReaderProgressStore();
  await store.save(
    'chapter-errors',
    ReaderProgress(
      spineIndex: initialSpine,
      pageIndex: 0,
      contentRevision: 'chapter-errors-1',
    ),
  );
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source,
          store: store,
          bookId: 'chapter-errors',
          contentRevision: 'chapter-errors-1',
          bookTitle: '逐章加载失败回归',
          overrides: const ReaderOverrides(
            fontSize: 18,
            lineHeight: 1.6,
            paragraphSpacing: 10,
          ),
          pageTurnMode: PageTurnMode.none,
          showPageFooter: false,
          onSessionReady: (value) => session = value,
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    var stopped = false;
    unawaited(source.preparationsStopped.then((_) => stopped = true));
    await _pumpUntil(tester, () => stopped, description: '章节源准备作业释放');
  });
  await _pumpUntil(
    tester,
    () =>
        session.hasContent &&
        find.byKey(const ValueKey('reader-content')).evaluate().isNotEmpty,
    description: '正式引擎首屏',
  );
  if (menu) await _openMenu(tester);
  expect(tester.takeException(), isNull);
  return (session: session, source: source);
}

Future<void> _navigate(WidgetTester tester, String kind) async {
  switch (kind) {
    case '上一章':
      await tester.tap(find.byKey(const ValueKey('menu-prev-chapter')));
    case '下一章':
      await tester.tap(find.byKey(const ValueKey('menu-next-chapter')));
    case '百分比':
      final bounds = tester.getRect(
        find.byKey(const ValueKey('menu-progress-slider')),
      );
      await tester.tapAt(
        Offset(bounds.left + bounds.width * 0.9, bounds.center.dy),
      );
    case '目录':
      await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('toc-row-2-第三章')));
    case '翻页':
      final bounds = tester.getRect(find.byType(ReaderView));
      await tester.tapAt(bounds.centerRight - const Offset(20, 0));
    default:
      fail('未知导航方式：$kind');
  }
}

void main() {
  for (final (kind, initialSpine, targetSpine) in [
    ('下一章', 0, 1),
    ('上一章', 2, 1),
    ('百分比', 0, 2),
    ('目录', 0, 2),
    ('翻页', 0, 1),
  ]) {
    testWidgets('正式逐章来源$kind失败提示且保留原文位置，再次操作可重试', (tester) async {
      final loader = _ChapterLoader()
        ..failures[targetSpine] = StateError('正文暂时获取失败');
      final reader = await _open(
        tester,
        loader,
        initialSpine: initialSpine,
        menu: kind != '翻页',
      );
      final session = reader.session;
      final origin = session.page;
      final cfi = session.readingCfi;
      final progress = session.progress;
      expect(cfi, isNotNull);

      await _navigate(tester, kind);
      await _pumpUntil(
        tester,
        () => find.textContaining('章节加载失败').evaluate().isNotEmpty,
        description: '$kind加载失败提示',
      );
      expect(loader.requested, contains(targetSpine));
      expect(session.page, same(origin));
      expect(session.readingCfi, cfi);
      expect(session.progress, progress);
      expect(session.error, isNull);
      expect(session.jumpLoadingTitle, isNull);
      expect(tester.takeException(), isNull);

      loader.failures.remove(targetSpine);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      if (kind == '目录') await _openMenu(tester);
      await _navigate(tester, kind);
      await _pumpUntil(
        tester,
        () =>
            session.page?.spineIndex == targetSpine &&
            session.jumpLoadingTitle == null,
        description: '$kind重试',
      );
      expect(session.readingCfi, isNot(cfi));
      expect(session.error, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final superseded in [false, true]) {
    testWidgets('正式逐章目录${superseded ? '被新导航接管' : '取消'}后晚到的真实错误不提示', (
      tester,
    ) async {
      final gate = Completer<void>();
      final loader = _ChapterLoader()
        ..failures[2] = StateError('已经过期的正文失败')
        ..gates[2] = gate;
      final reader = await _open(tester, loader);
      final session = reader.session;
      await _navigate(tester, '目录');
      await _pumpUntil(
        tester,
        () => loader.requested.contains(2),
        description: '目录正文开始获取',
      );
      if (superseded) {
        final pending = session.jumpToTocEntry(reader.source.toc[1]);
        await _pumpUntil(
          tester,
          () =>
              session.page?.spineIndex == 1 && session.jumpLoadingTitle == null,
          description: '新目录导航',
        );
        expect(await pending, isTrue);
      } else {
        session.cancelPendingLoads();
      }
      final current = session.page;
      final cfi = session.readingCfi;
      final progress = session.progress;
      gate.complete();
      await _pumpUntil(
        tester,
        () => loader.completed.contains(2),
        description: '旧正文错误交付',
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('章节加载失败'), findsNothing);
      expect(session.page, same(current));
      expect(session.readingCfi, cfi);
      expect(session.progress, progress);
      expect(session.error, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
