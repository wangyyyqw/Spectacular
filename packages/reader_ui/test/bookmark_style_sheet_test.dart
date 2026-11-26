import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/bookmarks/bookmark_ribbon.dart';
import 'package:reader_ui/bookmarks/bookmark_style.dart';
import 'package:reader_ui/panels/bookmark_style_sheet.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'support/decoration_test_images.dart';

void main() {
  testWidgets('正式弹窗首帧不创建屏外滑块，展开与滚动后草稿可保存', (tester) async {
    tester.view.physicalSize = const Size(384, 853);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ReaderBookmarkStyle? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReaderBottomSheet<ReaderBookmarkStyle>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ReaderBookmarkStyleSheet(
                    style: ReaderBookmarkStyle(),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    await tester.pumpAndSettle();
    final width = find.byKey(const ValueKey('bookmark-宽度'));
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(width, 120, scrollable: list);
    tester.widget<Slider>(width).onChanged!(42);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byTooltip('关闭'),
      -160,
      scrollable: list,
    );
    await tester.scrollUntilVisible(width, 120, scrollable: list);
    expect(tester.widget<Slider>(width).value, 42);
    await tester.tap(find.byKey(const ValueKey('bookmark-style-save')));
    await tester.pumpAndSettle();
    expect(result!.width, 42);
    expect(tester.takeException(), isNull);
  });

  for (final save in [true, false]) {
    testWidgets('下拉书签开关${save ? '保存后返回新设置' : '取消后不保存'}', (tester) async {
      ReaderBookmarkStyle? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<ReaderBookmarkStyle>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const ReaderBookmarkStyleSheet(
                      style: ReaderBookmarkStyle(),
                    ),
                  );
                },
                child: const Text('打开书签设置'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开书签设置'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('bookmark-pull-enabled'));
      expect(tester.widget<ReaderSwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<ReaderSwitchListTile>(toggle).value, isFalse);
      await tester.tap(
        save
            ? find.byKey(const ValueKey('bookmark-style-save'))
            : find.byTooltip('关闭'),
      );
      await tester.pumpAndSettle();
      expect(
        result,
        save ? const ReaderBookmarkStyle(pullEnabled: false) : null,
      );
    });
  }

  testWidgets('选本地图片、取消选择、恢复默认图标；窄屏大字无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Uint8List image;
    await tester.runAsync(() async => image = await ninePatchTestBytes());
    String? next = 'image:local';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: ReaderBookmarkStyleSheet(
              style: const ReaderBookmarkStyle(
                width: 96,
                length: 200,
                rightInset: 160,
              ),
              onPickImage: () async => next,
              imageLoader: (_) async => image,
            ),
          ),
        ),
      ),
    );
    final pick = find.byKey(const ValueKey('bookmark-pick-image'));
    await tester.scrollUntilVisible(pick, 100);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderBookmarkRibbon>(find.byType(ReaderBookmarkRibbon))
          .style
          .imageId,
      'image:local',
    );
    next = null;
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderBookmarkRibbon>(find.byType(ReaderBookmarkRibbon))
          .style
          .imageId,
      'image:local',
    );
    await tester.tap(find.text('使用默认图标'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderBookmarkRibbon>(find.byType(ReaderBookmarkRibbon))
          .style
          .imageId,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片导入失败保留原样式；图片缺失时回退默认丝带', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderBookmarkStyleSheet(
            style: const ReaderBookmarkStyle(imageId: 'image:missing'),
            imageLoader: (_) async => throw StateError('文件已不存在'),
            onPickImage: () async => throw const FormatException('文件无效'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ClipPath), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bookmark-pick-image')));
    await tester.pumpAndSettle();
    expect(find.textContaining('图片导入失败'), findsOneWidget);
    expect(
      tester
          .widget<ReaderBookmarkRibbon>(find.byType(ReaderBookmarkRibbon))
          .style
          .imageId,
      'image:missing',
    );
    expect(tester.takeException(), isNull);
  });
}
