import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_editor_sheet.dart';
import 'package:reader_ui/decorations/decoration_rule_editor.dart';
import 'package:reader_ui/decorations/decoration_rule_page.dart';
import 'package:reader_ui/decorations/decoration_rule_preview.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_style_preview.dart';
import 'package:reader_ui/panels/decoration_panel.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/panels/settings_panel.dart' show ReaderFontOption;
import 'package:reader_ui/decorations/decoration_highlight_editor.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/decorations/decoration_image_codec.dart';
import 'package:reader_ui/decorations/decoration_nine_slice_editor.dart';

import 'support/decoration_test_images.dart';

class _DecorationImages implements ReaderDecorationNinePatchImageStore {
  _DecorationImages(this.bytes);
  final Uint8List bytes;
  Uint8List? savedNinePatch;

  @override
  Future<String?> pickImage() async => '/local/texture.png';
  @override
  Future<Uint8List> loadImage(String path) async =>
      path.endsWith('.9.png') ? savedNinePatch! : bytes;
  @override
  Future<String> saveNinePatch(Uint8List bytes) async {
    savedNinePatch = bytes;
    return '/local/texture.9.png';
  }

  @override
  Future<void> removeUnused(Set<String> referencedPaths) async {}
}

Future<Uint8List> _imageBytes({int width = 12, int height = 6}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFFB6D7A8), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

const _testFonts = [
  ReaderFontOption(family: 'reader-test-font', label: '本地测试字体'),
];

class _RuleStore implements ReaderDecorationRuleStore {
  List<String>? reordered;
  final groups = [
    const ReaderDecorationRuleGroup(id: 'first', bookId: 'book', name: '第一组'),
    const ReaderDecorationRuleGroup(
      id: 'second',
      bookId: 'book',
      name: '第二组',
      sortOrder: 1,
    ),
    const ReaderDecorationRuleGroup(
      id: 'default',
      bookId: 'book',
      name: '本书默认组',
      isDefault: true,
    ),
    const ReaderDecorationRuleGroup(
      id: 'global',
      name: '全局默认组',
      isDefault: true,
    ),
  ];
  final rules = <ReaderDecorationRule>[];
  @override
  Future<List<ReaderDecorationRuleGroup>> listGroups() async => groups;
  @override
  Future<List<ReaderDecorationRule>> listRules() async => rules;
  @override
  Future<void> saveGroup(ReaderDecorationRuleGroup group) async {
    final index = groups.indexWhere((item) => item.id == group.id);
    if (index < 0) {
      groups.add(group);
    } else {
      groups[index] = group;
    }
  }

  @override
  Future<void> removeGroup(String id) async =>
      groups.removeWhere((item) => item.id == id);
  @override
  Future<void> saveRule(ReaderDecorationRule rule) async => rules.add(rule);
  @override
  Future<void> removeRule(String id) async =>
      rules.removeWhere((item) => item.id == id);
  @override
  Future<void> reorderGroups(List<String> ids) async => reordered = ids;
  @override
  Future<void> reorderRules(String groupId, List<String> ids) async {}
}

Future<void> _openSheet<T>(
  WidgetTester tester,
  Widget sheet,
  ValueChanged<T?> capture,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async => capture(
              await showModalBottomSheet<T>(
                context: context,
                isScrollControlled: true,
                builder: (_) => sheet,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Future<void> _openTypography(WidgetTester tester) async {
  final typography = find.byKey(
    const ValueKey<String>('decoration-typography'),
  );
  await tester.ensureVisible(typography);
  await tester.tap(typography);
  await tester.pumpAndSettle();
}

Future<void> _selectFont(WidgetTester tester, String label) async {
  final font = find.byKey(const ValueKey<String>('decoration-font'));
  await tester.ensureVisible(font);
  await tester.tap(font);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey<String>('decoration-save')),
);

Future<void> _pumpImageTask(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 80; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (ready()) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('图片任务未完成');
}

void main() {
  testWidgets('点九实时预览给边角留出行距，多行图案不互相遮挡', (tester) async {
    final images = _DecorationImages(
      (await tester.runAsync(ninePatchTestBytes))!,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 320,
                  child: ReaderDecorationStylePreview(
                    text: '甲乙\n丙丁',
                    style: const ReaderDecorationStyle(
                      backgroundImagePath: '/local/texture.png',
                      backgroundImageFit: ReaderDecorationImageFit.nineSlice,
                    ),
                    images: images,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final preview = find.byKey(const ValueKey('decoration-style-preview'));
    await _pumpImageTask(tester, () => tester.getSize(preview).height > 120);
    expect(tester.getSize(preview).height, greaterThan(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('正则匹配进行中调样式保留结果，颜色透明度立即应用且不用重新匹配', (tester) async {
    final pending = Completer<List<ReaderDecorationRulePreview>>();
    var calls = 0;
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'cached',
          groupId: 'group',
          pattern: r'\d+',
          isRegex: true,
          style: ReaderDecorationRuleStyle(
            highlight: ReaderDecorationHighlight(),
          ),
        ),
        onPreview: (_) {
          calls++;
          return pending.future;
        },
      ),
      (_) {},
    );
    await tester.tap(find.byKey(const ValueKey<String>('rule-preview')));
    await tester.pump();
    final swatch = find.byKey(
      const ValueKey('decoration-highlight-style-wavyUnderline'),
    );
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    pending.complete([
      const ReaderDecorationRulePreview(
        startCfi: 'start',
        endCfi: 'end',
        text: '123',
        style: ReaderDecorationRuleStyle(),
      ),
    ]);
    await tester.pumpAndSettle();
    final colors = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '蓝色',
    );
    expect(colors, findsOneWidget);
    await tester.ensureVisible(colors);
    await tester.tap(colors);
    await tester.pumpAndSettle();
    final opacity = find.descendant(
      of: find.byKey(const ValueKey('decoration-highlight-opacity')),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(opacity).onChanged!(0.45);
    await tester.pumpAndSettle();
    final previews = tester.widgetList<ReaderDecorationStylePreview>(
      find.byType(ReaderDecorationStylePreview),
    );
    expect(previews, hasLength(2));
    expect(previews.first.text, '123');
    expect(
      previews.every(
        (preview) =>
            preview.style.highlight!.style ==
                ReaderAnnotationStyle.wavyUnderline &&
            preview.style.highlight!.color == 0xFF90CAF9 &&
            preview.style.highlight!.opacity == 0.45,
      ),
      isTrue,
    );
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通图片可拖拽内容区转为点九副本，确认后规则保存同一路径与配置', (tester) async {
    final images = _DecorationImages((await tester.runAsync(_imageBytes))!);
    ReaderDecorationRule? saved;
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'nine',
          groupId: 'group',
          pattern: '文字',
          style: ReaderDecorationRuleStyle(
            backgroundImagePath: '/local/texture.png',
          ),
        ),
        images: images,
        onPreview: (_) async => [],
      ),
      (result) => saved = result,
    );
    final convert = find.byKey(const ValueKey('decoration-nine-slice-edit'));
    await tester.ensureVisible(convert);
    await tester.tap(convert);
    await _pumpImageTask(
      tester,
      () => find.byType(ReaderDecorationNineSliceEditor).evaluate().isNotEmpty,
    );
    final source = find.byKey(const ValueKey('decoration-nine-slice-source'));
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    final rect = tester.getRect(source);
    final imageRect = Alignment.center.inscribe(
      applyBoxFit(BoxFit.contain, const Size(12, 6), rect.size).destination,
      rect,
    );
    await tester.dragFrom(
      imageRect.topLeft + Offset(imageRect.width * 0.2, imageRect.height * 0.2),
      Offset(imageRect.width * 0.1, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('decoration-nine-slice-save')));
    await _pumpImageTask(
      tester,
      () => find.byType(ReaderDecorationNineSliceEditor).evaluate().isEmpty,
    );
    final preview = tester.widget<ReaderDecorationStylePreview>(
      find.byType(ReaderDecorationStylePreview),
    );
    expect(
      preview.style.backgroundImageFit,
      ReaderDecorationImageFit.nineSlice,
    );
    expect(
      preview.style.backgroundImageNineSlice!.content.left,
      greaterThan(0.2),
    );
    await tester.tap(find.byKey(const ValueKey<String>('rule-save')));
    await tester.pumpAndSettle();
    expect(
      saved!.style.backgroundImageNineSlice!.toJson(),
      preview.style.backgroundImageNineSlice!.toJson(),
    );
    expect(saved!.style.backgroundImagePath, '/local/texture.9.png');
    expect(preview.style.backgroundImagePath, saved!.style.backgroundImagePath);
    final decoded = (await tester.runAsync(
      () => ReaderDecorationImageCodec.decode(images.savedNinePatch!),
    ))!;
    addTearDown(decoded.image.dispose);
    expect(decoded.image.width, 12);
    expect(decoded.image.height, 6);
    expect(
      decoded.nineSlice!.toJson(),
      saved!.style.backgroundImageNineSlice!.toJson(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点九PNG导入自动选择点九拉伸，手工装饰保存内容标记', (tester) async {
    final images = _DecorationImages(
      (await tester.runAsync(ninePatchTestBytes))!,
    );
    ReaderDecorationStyle? saved;
    await _openSheet<ReaderDecorationStyle>(
      tester,
      ReaderDecorationEditorSheet(quote: '点九图片', images: images),
      (result) => saved = result,
    );
    final background = find.byKey(
      const ValueKey<String>('decoration-background'),
    );
    await tester.ensureVisible(background);
    await tester.tap(background);
    await tester.pumpAndSettle();
    final pick = find.widgetWithText(OutlinedButton, '选择本地背景图');
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await _pumpImageTask(tester, () => _saveButton(tester).onPressed != null);
    await tester.tap(find.byKey(const ValueKey<String>('decoration-save')));
    await tester.pumpAndSettle();
    expect(saved!.backgroundImageFit, ReaderDecorationImageFit.nineSlice);
    expect(
      saved!.backgroundImageNineSlice!.content,
      const Rect.fromLTRB(8 / 30, 7 / 20, 22 / 30, 13 / 20),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('单像素图片的点九内容区至少一像素，拖动和保存不会越界', (tester) async {
    final decoded = (await tester.runAsync(
      () async => ReaderDecorationImageCodec.decode(
        await _imageBytes(width: 1, height: 1),
      ),
    ))!;
    addTearDown(decoded.image.dispose);
    ReaderDecorationNineSliceSelection? saved;
    await _openSheet<ReaderDecorationNineSliceSelection>(
      tester,
      ReaderDecorationNineSliceEditor(image: decoded.image),
      (result) => saved = result,
    );
    final source = find.byKey(const ValueKey('decoration-nine-slice-source'));
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    await tester.drag(source, const Offset(40, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('decoration-nine-slice-save')));
    await tester.pumpAndSettle();
    expect(saved!.nineSlice.slice, const Rect.fromLTRB(0, 0, 1, 1));
    expect(saved!.nineSlice.content, const Rect.fromLTRB(0, 0, 1, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('点九保存期间禁用重复提交，失败后保留内容区并可重试', (tester) async {
    final images = _DecorationImages((await tester.runAsync(_imageBytes))!);
    final decoded = (await tester.runAsync(
      () => ReaderDecorationImageCodec.decode(images.bytes),
    ))!;
    addTearDown(decoded.image.dispose);
    final firstSave = Completer<String>();
    var saves = 0;
    ReaderDecorationNineSliceSelection? saved;
    await _openSheet<ReaderDecorationNineSliceSelection>(
      tester,
      ReaderDecorationNineSliceEditor(
        image: decoded.image,
        saveImage: (bytes) {
          saves++;
          return saves == 1 ? firstSave.future : images.saveNinePatch(bytes);
        },
      ),
      (result) => saved = result,
    );
    tester
        .widget<Slider>(
          find.byKey(const ValueKey('decoration-nine-slice-inset-0')),
        )
        .onChanged!(2);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('decoration-nine-slice-save'));
    await tester.tap(save);
    await _pumpImageTask(tester, () => saves == 1);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '取消',
            ),
          )
          .onPressed,
      isNull,
    );
    firstSave.completeError(StateError('测试保存失败'));
    await _pumpImageTask(
      tester,
      () => find.text('点九图片保存失败，请重试').evaluate().isNotEmpty,
    );
    expect(saved, isNull);
    expect(find.byType(ReaderDecorationNineSliceEditor), findsOneWidget);
    await tester.tap(save);
    await _pumpImageTask(
      tester,
      () => find.byType(ReaderDecorationNineSliceEditor).evaluate().isEmpty,
    );
    expect(saves, 2);
    expect(saved!.path, '/local/texture.9.png');
    expect(saved!.nineSlice.content.top, 2 / 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 大字点九预览随多行增高，保存按钮仍固定可见', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final decoded = (await tester.runAsync(
      () async => ReaderDecorationImageCodec.decode(await _imageBytes()),
    ))!;
    addTearDown(decoded.image.dispose);
    await _openSheet<ReaderDecorationNineSliceSelection>(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 600),
          textScaler: TextScaler.linear(1.6),
        ),
        child: ReaderDecorationNineSliceEditor(image: decoded.image),
      ),
      (_) {},
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('decoration-nine-slice-preview')))
          .height,
      greaterThan(180),
    );
    expect(
      find.byKey(const ValueKey('decoration-nine-slice-save')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('常用正则插入选中位置，窄屏与大字模式保持预览和保存可见', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openSheet<ReaderDecorationRule>(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 600),
          textScaler: TextScaler.linear(1.6),
        ),
        child: ReaderDecorationRuleEditor(
          rule: const ReaderDecorationRule(
            id: 'regex',
            groupId: 'group',
            pattern: '前后',
            isRegex: true,
            style: ReaderDecorationRuleStyle(),
          ),
          onPreview: (_) async => [],
        ),
      ),
      (_) {},
    );
    final pattern = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('rule-pattern')),
    );
    pattern.controller!.selection = const TextSelection.collapsed(offset: 1);
    final examples = find.byKey(const ValueKey<String>('rule-regex-examples'));
    await tester.ensureVisible(examples);
    await tester.tap(examples);
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'数字：\d+'));
    await tester.pumpAndSettle();
    expect(pattern.controller!.text, r'前\d+后');
    expect(
      find.byType(ReaderDecorationStylePreview).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rule-save')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('正则规则选择图片与铺放方式，命中预览和保存使用同一图片', (tester) async {
    final images = _DecorationImages((await tester.runAsync(_imageBytes))!);
    ReaderDecorationRule? saved;
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'image',
          groupId: 'group',
          pattern: r'甲|乙\d+',
          isRegex: true,
          style: ReaderDecorationRuleStyle(),
        ),
        images: images,
        onPreview: (rule) async => [
          ReaderDecorationRulePreview(
            startCfi: 'start',
            endCfi: 'end',
            text: '乙23',
            style: rule.style,
          ),
        ],
      ),
      (result) => saved = result,
    );
    final background = find.byKey(const ValueKey<String>('rule-background'));
    await tester.ensureVisible(background);
    await tester.tap(background);
    await tester.pumpAndSettle();
    final pick = find.byKey(
      const ValueKey<String>('rule-pick-background-image'),
    );
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await _pumpImageTask(
      tester,
      () =>
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey<String>('rule-save')),
              )
              .onPressed !=
          null,
    );
    final fit = find.byType(DropdownButtonFormField<ReaderDecorationImageFit>);
    await tester.ensureVisible(fit);
    await tester.tap(fit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('平铺').last);
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey<String>('rule-preview'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    final previews = tester.widgetList<ReaderDecorationStylePreview>(
      find.byType(ReaderDecorationStylePreview),
    );
    expect(previews, hasLength(2));
    expect(
      previews.every(
        (item) =>
            item.images == images &&
            item.style.backgroundImagePath == '/local/texture.png' &&
            item.style.backgroundImageFit == ReaderDecorationImageFit.tile,
      ),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey<String>('rule-save')));
    await tester.pumpAndSettle();
    expect(saved!.isRegex, isTrue);
    expect(saved!.pattern, r'甲|乙\d+');
    expect(saved!.style.backgroundImagePath, '/local/texture.png');
    expect(saved!.style.backgroundImageFit, ReaderDecorationImageFit.tile);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 高亮预设可编辑样式和连块，保存不改变字体度量', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ReaderDecorationStyle? saved;
    await _openSheet<ReaderDecorationStyle>(
      tester,
      const ReaderDecorationEditorSheet(quote: '高亮与划线沿用已有装饰的存储和原文定位。'),
      (result) => saved = result,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('decoration-preset-highlight')),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey<String>('decoration-highlight'));
    await tester.ensureVisible(panel);
    await tester.tap(panel);
    await tester.pumpAndSettle();
    final join = find.byKey(const ValueKey('decoration-highlight-join-lines'));
    await tester.ensureVisible(join);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderDecorationStylePreview>(
            find.byType(ReaderDecorationStylePreview),
          )
          .style
          .highlight!
          .joinLines,
      isTrue,
    );
    final swatch = find.byKey(
      const ValueKey('decoration-highlight-style-wavyUnderline'),
    );
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('decoration-save')));
    await tester.pumpAndSettle();
    expect(saved!.highlight!.style, ReaderAnnotationStyle.wavyUnderline);
    expect(saved!.changesMetrics, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动规则使用同一高亮编辑器，保存完整样式且不写预览结果', (tester) async {
    ReaderDecorationRule? saved;
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'rule',
          groupId: 'group',
          pattern: '重点',
          style: ReaderDecorationRuleStyle(),
        ),
        onPreview: (_) async => [],
      ),
      (result) => saved = result,
    );
    final panel = find.byKey(const ValueKey<String>('rule-highlight'));
    await tester.ensureVisible(panel);
    await tester.tap(panel);
    await tester.pumpAndSettle();
    final editor = find.byType(ReaderDecorationHighlightEditor);
    tester
        .widget<ReaderDecorationHighlightEditor>(editor)
        .onChanged(
          const ReaderDecorationHighlight(
            style: ReaderAnnotationStyle.halfBackground,
            color: 0xFF00FF00,
            opacity: 0.4,
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('rule-save')));
    await tester.pumpAndSettle();
    expect(saved!.style.highlight!.style, ReaderAnnotationStyle.halfBackground);
    expect(saved!.style.highlight!.color, 0xFF00FF00);
    expect(saved!.style.highlight!.opacity, 0.4);
    expect(saved!.style.decorationStyle.changesMetrics, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 装饰预设可保存，字体、背景、边框高级入口无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ReaderDecorationStyle? style;
    await _openSheet<ReaderDecorationStyle>(
      tester,
      const ReaderDecorationEditorSheet(quote: '装饰改变文字排版，而不是记录阅读想法。'),
      (result) => style = result,
    );
    expect(find.text('强调'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('便签'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('decoration-preset-tag')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('decoration-save')));
    await tester.pumpAndSettle();
    expect(style?.fontSizeScale, 0.85);
    expect(style?.fontWeight, 600);
    expect(style?.backgroundOpacity, 0.6);
    expect(style?.borderRadius, 4);
    expect(style?.paddingLeft, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('字体注册完成前禁用保存，完成后保存所选字体', (tester) async {
    final pending = Completer<void>();
    final loaded = <String>[];
    ReaderDecorationStyle? saved;
    await _openSheet<ReaderDecorationStyle>(
      tester,
      ReaderDecorationEditorSheet(
        quote: '所选字体注册成功后，预览和保存使用同一字体。',
        fonts: _testFonts,
        onLoadFont: (family) {
          loaded.add(family);
          return pending.future;
        },
      ),
      (result) => saved = result,
    );
    await _openTypography(tester);
    await _selectFont(tester, '本地测试字体');
    expect(loaded, ['reader-test-font']);
    expect(_saveButton(tester).onPressed, isNull);
    expect(find.text('正在加载字体，完成后可保存'), findsOneWidget);
    expect(
      tester
          .widget<ReaderDecorationStylePreview>(
            find.byType(ReaderDecorationStylePreview),
          )
          .style
          .fontFamily,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey<String>('decoration-save')));
    await tester.pumpAndSettle();
    expect(saved?.fontFamily, 'reader-test-font');
    expect(tester.takeException(), isNull);
  });

  testWidgets('字体加载失败显示错误且禁用保存，跟随正文可恢复', (tester) async {
    ReaderDecorationStyle? saved;
    await _openSheet<ReaderDecorationStyle>(
      tester,
      ReaderDecorationEditorSheet(
        quote: '加载失败不能保存不存在的字体。',
        fonts: _testFonts,
        onLoadFont: (_) async => throw StateError('字体文件不存在'),
      ),
      (result) => saved = result,
    );
    await _openTypography(tester);
    await _selectFont(tester, '本地测试字体');
    await tester.pumpAndSettle();
    expect(find.text('字体加载失败，请选择其他字体或跟随正文'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    final weight = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey<String>('decoration-weight')),
    );
    weight.onChanged!(700);
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNull);
    await _selectFont(tester, '跟随正文');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('decoration-font-error')),
      findsNothing,
    );
    expect(_saveButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey<String>('decoration-save')));
    await tester.pumpAndSettle();
    expect(saved?.fontFamily, isNull);
    expect(saved?.fontWeight, 700);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑记录的原字体未安装时禁止保存，重置后恢复', (tester) async {
    ReaderDecorationStyle? saved;
    await _openSheet<ReaderDecorationStyle>(
      tester,
      const ReaderDecorationEditorSheet(
        quote: '原字体已删除。',
        initialStyle: ReaderDecorationStyle(fontFamily: 'missing-font'),
      ),
      (result) => saved = result,
    );
    expect(find.text('原字体不可用，请选择已安装字体或跟随正文'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey<String>('decoration-save')));
    await tester.pumpAndSettle();
    expect(saved?.fontFamily, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切回正文后忽略过期字体加载失败', (tester) async {
    final pending = Completer<void>();
    await _openSheet<ReaderDecorationStyle>(
      tester,
      ReaderDecorationEditorSheet(
        quote: '异步字体结果不能覆盖最新选择。',
        fonts: _testFonts,
        onLoadFont: (_) => pending.future,
      ),
      (_) {},
    );
    await _openTypography(tester);
    await _selectFont(tester, '本地测试字体');
    final font = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey<String>('decoration-font')),
    );
    font.onChanged!('');
    await tester.pump();
    pending.completeError(StateError('过期字体加载失败'));
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey<String>('decoration-font-error')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('规则正则保存拦截无效格式，不调用预览', (tester) async {
    var previewCalls = 0;
    ReaderDecorationRule? saved;
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'rule',
          groupId: 'group',
          pattern: '',
          style: ReaderDecorationRuleStyle(),
        ),
        onPreview: (_) async {
          previewCalls++;
          return [];
        },
      ),
      (result) => saved = result,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rule-pattern')),
      '(',
    );
    final regex = find.byKey(const ValueKey<String>('rule-regex'));
    await tester.ensureVisible(regex);
    await tester.tap(regex);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('rule-save')));
    await tester.pump();
    expect(find.text('正则格式无效，请修改规则后重新生成预览'), findsOneWidget);
    expect(saved, isNull);
    expect(previewCalls, 0);
    expect(find.text('字体'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('规则管理区分作用域，默认组不删除且排序固定最后', (tester) async {
    final store = _RuleStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderDecorationRulePage(
          store: store,
          bookId: 'book',
          onPreview: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本书默认组'), findsOneWidget);
    expect(find.text('全局默认组'), findsNothing);
    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView).first,
    );
    reorderable.onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    expect(store.reordered, ['second', 'first', 'default']);
    final defaultCard = find.byKey(
      const ValueKey<String>('rule-group-default'),
    );
    final menu = find.descendant(
      of: defaultCard,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除分组'), findsNothing);
    await tester.tapAt(const Offset(8, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全局'));
    await tester.pumpAndSettle();
    expect(find.text('全局默认组'), findsOneWidget);
    expect(find.text('本书默认组'), findsNothing);
  });

  testWidgets('规则预览先展示5条，展开最多50条，不保存规则', (tester) async {
    ReaderDecorationRule? saved;
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'rule',
          groupId: 'group',
          pattern: '原文',
          style: ReaderDecorationRuleStyle(color: 0xFF374151),
        ),
        onPreview: (rule) async => List.generate(
          55,
          (index) => ReaderDecorationRulePreview(
            startCfi: 'start-$index',
            endCfi: 'end-$index',
            text: '命中 $index',
            style: rule.style,
          ),
        ),
      ),
      (result) => saved = result,
    );
    final preview = find.byKey(const ValueKey<String>('rule-preview'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDecorationStylePreview), findsNWidgets(6));
    final expand = find.byKey(const ValueKey<String>('rule-preview-expand'));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDecorationStylePreview), findsNWidgets(51));
    await tester.ensureVisible(expand);
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDecorationStylePreview), findsNWidgets(6));
    expect(saved, isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('装饰搜索框与搜索页统一：${brightness.name}', (tester) async {
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SearchPanel(
              onSearch: (_) async => const [],
              onSelect: (_) {},
            ),
          ),
        ),
      );
      final reference = tester.widget<TextField>(
        find.byKey(const ValueKey('search-input')),
      );
      final surface = tester.widget<Material>(
        find.byKey(const ValueKey('search-input-surface')),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ReaderDecorationPanel(
              decorations: const [],
              toc: const [],
              onSelect: (_) {},
              onEdit: (_) {},
              onRemove: (_) {},
              onRules: () {},
              ruleCount: 0,
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('decoration-search')),
      );
      final actual = tester.widget<Material>(
        find.byKey(const ValueKey('decoration-search-surface')),
      );
      expect(field.style, reference.style);
      expect(
        field.decoration?.enabledBorder,
        reference.decoration?.enabledBorder,
      );
      expect(field.decoration?.fillColor, reference.decoration?.fillColor);
      expect(
        field.decoration?.contentPadding,
        reference.decoration?.contentPadding,
      );
      expect(actual.color, surface.color);
      expect(actual.shadowColor, surface.shadowColor);
      expect(actual.elevation, surface.elevation);
      expect(actual.borderRadius, surface.borderRadius);
      expect(actual.surfaceTintColor, Colors.transparent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('装饰列表独立展示手工记录、待修复和规则入口', (tester) async {
    var rulesOpened = false;
    final selected = <ReaderDecoration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderDecorationPanel(
            decorations: [
              ReaderDecoration(
                id: 'manual',
                startCfi: 'epubcfi(/6/2!/4/2/1:0)',
                endCfi: 'epubcfi(/6/2!/4/2/1:2)',
                quote: '手工装饰原文',
                style: const ReaderDecorationStyle(fontWeight: 700),
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
                relocationStatus: 'pending',
              ),
            ],
            toc: const [TocEntry(title: '第一章', spineIndex: 0)],
            onSelect: selected.add,
            onEdit: (_) {},
            onRemove: (_) {},
            onRules: () => rulesOpened = true,
            ruleCount: 3,
          ),
        ),
      ),
    );
    expect(find.text('待修复 · 点击关联原文'), findsOneWidget);
    expect(find.text('字重 700'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('decoration-rules-entry')),
    );
    expect(rulesOpened, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey<String>('decoration-search')),
      '第一章',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('decoration-row-manual')),
    );
    expect(selected.single.id, 'manual');
  });

  testWidgets('预览计算期间修改匹配内容，不回填过期结果', (tester) async {
    final pending = Completer<List<ReaderDecorationRulePreview>>();
    await _openSheet<ReaderDecorationRule>(
      tester,
      ReaderDecorationRuleEditor(
        rule: const ReaderDecorationRule(
          id: 'rule',
          groupId: 'group',
          pattern: '原文',
          style: ReaderDecorationRuleStyle(),
        ),
        onPreview: (_) => pending.future,
      ),
      (_) {},
    );
    final preview = find.byKey(const ValueKey<String>('rule-preview'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pump();
    final pattern = find.byKey(const ValueKey<String>('rule-pattern'));
    await tester.ensureVisible(pattern);
    await tester.enterText(pattern, '新版原文');
    pending.complete([
      const ReaderDecorationRulePreview(
        startCfi: 'start',
        endCfi: 'end',
        text: '过期命中',
        style: ReaderDecorationRuleStyle(),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderDecorationStylePreview), findsOneWidget);
  });
}
