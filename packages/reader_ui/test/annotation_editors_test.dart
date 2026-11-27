import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_appearance_editor.dart';
import 'package:reader_ui/annotations/annotation_editor_sheet.dart';
import 'package:reader_ui/annotations/mark_settings.dart';
import 'package:reader_ui/annotations/note_composer_sheet.dart';
import 'package:reader_ui/panels/mark_settings_sheet.dart';
import 'package:reader_ui/panels/reader_settings_sheet.dart';
import 'package:reader_ui/theme/reader_section_slider.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

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

void main() {
  testWidgets('320dp 划线编辑器展示九种样式且没有溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openSheet<AnnotationEditAction>(
      tester,
      ReaderAnnotationEditorSheet(
        annotation: ReaderAnnotation(
          id: 'mark',
          type: ReaderAnnotationType.mark,
          startCfi: 'start',
          endCfi: 'end',
          quote: '这是一段跨行的原文预览',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      (_) {},
    );
    for (final style in ReaderAnnotationStyle.values) {
      expect(
        find.byKey(ValueKey<String>('annotation-style-${style.name}')),
        findsOneWidget,
      );
    }
    expect(find.text('背景'), findsOneWidget);
    expect(find.text('线条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final style = find.byKey(
      const ValueKey<String>('annotation-style-doubleUnderline'),
    );
    await tester.ensureVisible(style);
    await tester.tap(style);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('annotation-save-changes')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('想法正文不限制256字，保存包含当前划线样式和透明度', (tester) async {
    AnnotationEditAction? action;
    await _openSheet<AnnotationEditAction>(
      tester,
      const ReaderNoteComposerSheet(
        quote: '原文',
        markSettings: ReaderMarkSettings(
          lastStyle: ReaderAnnotationStyle.halfBackground,
          lastColor: 0xFF90CAF9,
        ),
      ),
      (result) => action = result,
    );
    final save = find.byKey(const ValueKey<String>('note-composer-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final note = List<String>.filled(300, '想').join();
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-composer-input')),
      '  $note  ',
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(action?.note, note);
    expect(action?.style, ReaderAnnotationStyle.halfBackground);
    expect(action?.color, 0xFF90CAF9);
    expect(action?.opacity, 0.34);
  });

  testWidgets('划线设置提交默认样式、线宽与连续填充，不提供无效透明度', (tester) async {
    ReaderMarkSettings? settings;
    await _openSheet<ReaderMarkSettings>(
      tester,
      const ReaderMarkSettingsSheet(settings: ReaderMarkSettings()),
      (result) => settings = result,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-opacity')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey<String>('line-tab')));
    await tester.pumpAndSettle();
    final style = find.byKey(
      const ValueKey<String>('annotation-style-dottedUnderline'),
    );
    await tester.ensureVisible(style);
    await tester.tap(style);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('width-tab')));
    await tester.pumpAndSettle();
    final width = find.byKey(const ValueKey<String>('annotation-width-2.6'));
    await tester.ensureVisible(width);
    await tester.tap(width);
    await tester.pump();
    final join = find.byKey(const ValueKey<String>('annotation-join-lines'));
    await tester.ensureVisible(join);
    await tester.tap(join);
    await tester.tap(find.byKey(const ValueKey<String>('mark-settings-save')));
    await tester.pumpAndSettle();
    expect(settings?.lastStyle, ReaderAnnotationStyle.dottedUnderline);
    expect(settings?.strokeWidth, 2.6);
    expect(settings?.joinBackgroundLines, isTrue);
  });

  testWidgets('升级划线为想法时保留原透明度', (tester) async {
    AnnotationEditAction? action;
    await _openSheet<AnnotationEditAction>(
      tester,
      const ReaderNoteComposerSheet(quote: '原文', initialOpacity: 0.6),
      (result) => action = result,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-composer-input')),
      '补充想法',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('note-composer-save')));
    await tester.pumpAndSettle();
    expect(action?.opacity, 0.6);
  });

  testWidgets('320dp 想法弹窗复用设置面板和分栏，切换保留正文与外观', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AnnotationEditAction? action;
    await _openSheet<AnnotationEditAction>(
      tester,
      const ReaderNoteComposerSheet(quote: '需要记录想法的原文'),
      (result) => action = result,
    );

    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
    expect(find.byType(ReaderSectionSlider), findsOneWidget);
    final sheet = find.byKey(const ValueKey<String>('note-composer-sheet'));
    final initialHeight = tester.getSize(sheet).height;
    expect(
      initialHeight,
      closeTo(800 * ReaderUiStyle.settingsSheetHeightFraction, 0.1),
    );
    final input = find.byKey(const ValueKey<String>('note-composer-input'));
    await tester.enterText(input, '切换外观分栏后仍保留的想法');
    await tester.pump();

    for (final section in ['color', 'background', 'line', 'width']) {
      expect(find.byKey(ValueKey<String>('$section-tab')), findsOneWidget);
    }
    expect(
      tester
          .widget<ReaderAnnotationAppearanceEditor>(
            find.byType(ReaderAnnotationAppearanceEditor),
          )
          .section,
      ReaderAnnotationAppearanceSection.color,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-style-background')),
      findsNothing,
    );

    final background = find.byKey(const ValueKey<String>('background-tab'));
    await tester.ensureVisible(background);
    await tester.tap(background);
    await tester.pumpAndSettle();
    final halfBackground = find.byKey(
      const ValueKey<String>('annotation-style-halfBackground'),
    );
    await tester.ensureVisible(halfBackground);
    await tester.tap(halfBackground);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('annotation-style-underline')),
      findsNothing,
    );

    final line = find.byKey(const ValueKey<String>('line-tab'));
    await tester.ensureVisible(line);
    await tester.tap(line);
    await tester.pumpAndSettle();
    final dotted = find.byKey(
      const ValueKey<String>('annotation-style-dottedUnderline'),
    );
    await tester.ensureVisible(dotted);
    await tester.tap(dotted);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('annotation-width-2.6')),
      findsNothing,
    );

    final width = find.byKey(const ValueKey<String>('width-tab'));
    await tester.ensureVisible(width);
    await tester.tap(width);
    await tester.pumpAndSettle();
    final thick = find.byKey(const ValueKey<String>('annotation-width-2.6'));
    await tester.ensureVisible(thick);
    await tester.tap(thick);
    await tester.pump();
    final join = find.byKey(const ValueKey<String>('annotation-join-lines'));
    await tester.ensureVisible(join);
    await tester.tap(join);
    await tester.pump();

    final color = find.byKey(const ValueKey<String>('color-tab'));
    await tester.ensureVisible(color);
    await tester.tap(color);
    await tester.pumpAndSettle();
    final blue = find.byKey(
      const ValueKey<String>('annotation-color-0xFF90CAF9'),
    );
    await tester.ensureVisible(blue);
    await tester.tap(blue);
    await tester.pump();
    final opacity = find.byKey(const ValueKey<String>('annotation-opacity'));
    await tester.ensureVisible(opacity);
    await tester.tap(opacity);
    await tester.pump();
    final savedOpacity = tester.widget<Slider>(opacity).value;
    expect(
      savedOpacity,
      isNot(ReaderAnnotationStyle.dottedUnderline.defaultOpacity),
    );
    expect(tester.widget<TextField>(input).controller?.text, '切换外观分栏后仍保留的想法');
    expect(tester.getSize(sheet).height, initialHeight);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('note-composer-save')));
    await tester.pumpAndSettle();
    expect(action?.note, '切换外观分栏后仍保留的想法');
    expect(action?.style, ReaderAnnotationStyle.dottedUnderline);
    expect(action?.color, 0xFF90CAF9);
    expect(action?.opacity, savedOpacity);
    expect(action?.markSettings?.strokeWidth, 2.6);
    expect(action?.markSettings?.joinBackgroundLines, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义色保存不覆盖刚选择的默认样式', (tester) async {
    ReaderMarkSettings? settings;
    await _openSheet<ReaderMarkSettings>(
      tester,
      const ReaderMarkSettingsSheet(settings: ReaderMarkSettings()),
      (result) => settings = result,
    );
    await tester.tap(find.byKey(const ValueKey<String>('line-tab')));
    await tester.pumpAndSettle();
    final style = find.byKey(
      const ValueKey<String>('annotation-style-wavyUnderline'),
    );
    await tester.ensureVisible(style);
    await tester.tap(style);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('color-tab')));
    await tester.pumpAndSettle();
    final addColor = find.byKey(const ValueKey<String>('annotation-add-color'));
    await tester.tap(addColor);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('reader-color-input')),
      'FF112233',
    );
    await tester.tap(find.byKey(const ValueKey<String>('reader-color-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('mark-settings-save')));
    await tester.pumpAndSettle();
    expect(settings?.lastStyle, ReaderAnnotationStyle.wavyUnderline);
    expect(settings?.lastColor, 0xFF112233);
    expect(settings?.customColors, [0xFF112233]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义颜色长按仅移除该颜色，预设颜色仍可选择并保存', (tester) async {
    ReaderMarkSettings? settings;
    await _openSheet<ReaderMarkSettings>(
      tester,
      const ReaderMarkSettingsSheet(
        settings: ReaderMarkSettings(customColors: [0xFF112233, 0xFF334455]),
      ),
      (result) => settings = result,
    );
    final custom = find.byKey(
      const ValueKey<String>('annotation-color-0xFF112233'),
    );
    expect(tester.getSize(custom), const Size(44, 44));
    await tester.tap(custom);
    await tester.pump();
    await tester.longPress(custom);
    await tester.pumpAndSettle();
    expect(custom, findsNothing);
    expect(
      find.byKey(const ValueKey<String>('annotation-color-0xFF334455')),
      findsOneWidget,
    );
    final preset = find.byKey(
      const ValueKey<String>('annotation-color-0xFF90CAF9'),
    );
    await tester.longPress(preset);
    await tester.pumpAndSettle();
    expect(preset, findsOneWidget);
    await tester.tap(preset);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('mark-settings-save')));
    await tester.pumpAndSettle();
    expect(settings?.lastColor, 0xFF90CAF9);
    expect(settings?.customColors, [0xFF334455]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('划线设置以分段按钮切换分区，预览紧邻按钮组上方', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openSheet<ReaderMarkSettings>(
      tester,
      const ReaderMarkSettingsSheet(settings: ReaderMarkSettings()),
      (_) {},
    );
    expect(find.text('划线设置'), findsNothing);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.textContaining('快捷划线使用这里的默认样式'), findsOneWidget);
    final navigation = find.byKey(
      const ValueKey<String>('mark-settings-section-tabs'),
    );
    final preview = find.byKey(const ValueKey<String>('mark-settings-preview'));
    final fixedHeight = find.byKey(
      const ValueKey<String>('mark-settings-fixed-height'),
    );
    final initialHeight = tester.getSize(fixedHeight).height;
    expect(
      tester.getTopLeft(navigation).dy - tester.getBottomLeft(preview).dy,
      closeTo(8, 0.1),
    );
    for (final section in ['color', 'background', 'line', 'width']) {
      expect(find.byKey(ValueKey<String>('$section-tab')), findsOneWidget);
    }
    expect(find.text('颜色'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('annotation-add-color')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('background-tab')));
    await tester.pumpAndSettle();
    expect(find.text('背景'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('annotation-style-halfBackground')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-style-underline')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('line-tab')));
    await tester.pumpAndSettle();
    expect(find.text('线条'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('annotation-width-1.8')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('width-tab')));
    await tester.pumpAndSettle();
    expect(find.text('线宽'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('annotation-width-1.8')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('annotation-join-lines')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('background-tab')));
    await tester.pumpAndSettle();
    expect(find.text('背景'), findsNWidgets(2));
    expect(tester.getSize(fixedHeight).height, initialHeight);
    expect(tester.takeException(), isNull);
  });
}
