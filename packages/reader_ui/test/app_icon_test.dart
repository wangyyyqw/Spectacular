import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/icons/app_icon.dart';

void main() {
  testWidgets('图标在大点击区域内保持指定尺寸并居中', (tester) async {
    const target = ValueKey('图标区域');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            key: target,
            width: 48,
            height: 40,
            child: AppIcon(AppGlyph.search, size: 20),
          ),
        ),
      ),
    );
    final paint = find.descendant(
      of: find.byType(AppIcon),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint), const Size.square(20));
    expect(tester.getCenter(paint), tester.getCenter(find.byKey(target)));
  });

  testWidgets('图标继承主题尺寸颜色和透明度并响应主题更新', (tester) async {
    final boundaryKey = GlobalKey();
    for (final opacity in [0.4, 1.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: IconTheme(
                data: IconThemeData(
                  size: 24,
                  color: const Color(0xFF24689A),
                  opacity: opacity,
                ),
                child: const AppIcon(AppGlyph.radioChecked),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppIcon)), const Size.square(24));
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!;
        final pixel = (12 * image.width + 12) * 4;
        expect(bytes.getUint8(pixel + 3), closeTo(255 * opacity, 1));
        expect(bytes.getUint8(pixel), closeTo(0x24 * opacity, 1));
        expect(bytes.getUint8(pixel + 1), closeTo(0x68 * opacity, 1));
        expect(bytes.getUint8(pixel + 2), closeTo(0x9A * opacity, 1));
        image.dispose();
      });
    }
  });

  testWidgets('展开箭头跟随实际展开状态，菜单勾选保留语义和选择行为', (tester) async {
    String? selected;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const AppExpansionTile(
                title: Text('作者样式'),
                initiallyExpanded: true,
                children: [Text('样式内容')],
              ),
              PopupMenuButton<String>(
                tooltip: '排序',
                icon: const AppIcon(AppGlyph.sort),
                onSelected: (value) => selected = value,
                itemBuilder: (_) => [
                  appCheckedMenuItem(
                    value: 'recent',
                    checked: true,
                    child: const Text('最近更新'),
                  ),
                  appCheckedMenuItem(
                    value: 'reading',
                    checked: false,
                    child: const Text('阅读顺序'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.5,
    );
    await tester.tap(find.text('作者样式'));
    await tester.pumpAndSettle();
    expect(find.text('样式内容'), findsNothing);
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0,
    );
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('最近更新')).flagsCollection.isChecked,
      ui.CheckedState.isTrue,
    );
    await tester.tapAt(tester.getCenter(find.text('阅读顺序')));
    await tester.pumpAndSettle();
    expect(selected, 'reading');
    semantics.dispose();
  });

  testWidgets('全部 AppGlyph 字形在 24 尺寸下均可正常绘制无异常', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final glyph in AppGlyph.values) ...[
                AppIcon(glyph, size: 24),
                AppIcon(glyph, size: 24, filled: true),
              ],
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
