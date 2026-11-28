import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/reader_selection_ocr.dart';
import 'package:reader_mobile/ocr/local_ocr_worker.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_image.dart';

import 'support/legacy_selection_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sample = String.fromEnvironment('OCR_SAMPLE_EPUB');
  test('用户样书：实际字体复核与真实选区离线 OCR', () async {
    final dir = Directory('dist/selection-ocr');
    await dir.create(recursive: true);
    final temporary = await dir.createTemp('roundtrip-');
    addTearDown(() => temporary.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.absolute.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    final source = await EpubChapterSource.openFile(
      File(sample),
      contentWidth: 320,
      contentHeight: 640,
    );
    addTearDown(source.close);
    final ocr = ReaderSelectionOcr();
    final watch = Stopwatch()..start();
    expect(await ocr.requiresOcr(source.document), isTrue);
    final detectionMs = watch.elapsedMilliseconds;
    await source.applyOverrides(const ReaderOverrides(fontSize: 20));
    final pages = await source.loadChapter(14);
    final page = pages.firstWhere(
      (p) => TextHitTester.lineBoxes(p).any((b) => b.text.length > 15),
    );
    final lines = TextHitTester.lineBoxes(page)
        .where((b) => b.text.length > 15)
        .take(2)
        .toList();
    TextHit hit(PageLineBox box, int offset) => TextHit(
      lineBox: box,
      charOffset: offset,
      textOffset: box.textOffset + offset,
      atLineStart: offset == 0,
      atLineEnd: offset == box.text.length,
    );
    final selection = ReaderSelection.normalized(
      hit(lines.first, 0),
      hit(lines.last, lines.last.text.length),
      pageIndex: page.pageIndex,
    );
    watch.reset();
    final image = await captureLegacySelection(page, selection);
    await File('${dir.path}/selected.png').writeAsBytes(image);
    watch.reset();
    final baseline = await localOcrWorker.recognize(image);
    final baselineMs = watch.elapsedMilliseconds;
    expect(
      baseline.map((line) => line.text).join(),
      '《梦中人》是民国时期的著名歌曲，周星驰的电影《功夫》之中，曾以该曲作为插曲，包租公和',
    );
    watch.reset();
    final lineImages = await SelectionImage.captureLines(
      page,
      selection,
    ).toList();
    final captureMs = watch.elapsedMilliseconds;
    watch.reset();
    final recognized = (await Future.wait(lineImages.map(ocr.recognize)))
        .join();
    final recognitionMs = watch.elapsedMilliseconds;
    watch.reset();
    expect(
      (await Future.wait(lineImages.map(ocr.recognize))).join(),
      recognized,
    );
    final cachedMs = watch.elapsedMilliseconds;
    for (var i = 0; i < lineImages.length; i++) {
      await File('${dir.path}/line-$i.png').writeAsBytes(lineImages[i]);
    }
    final raw = SelectionOps.textOf(page, selection);
    await File('${dir.path}/result.txt')
        .writeAsString('原码点：$raw\n识别文字：$recognized\n');
    expect(recognized, '《梦中人》是民国时期的著名歌曲，周星驰的电影《功夫》之中，曾以该曲作为插曲，包租公和');
    final short = ReaderSelection.normalized(
      hit(lines.first, 1),
      hit(lines.first, 3),
      pageIndex: page.pageIndex,
    );
    final shortImage = await SelectionImage.captureLines(page, short).single;
    await File('${dir.path}/short.png').writeAsBytes(shortImage);
    watch.reset();
    expect(await ocr.recognize(shortImage), '梦中');
    final shortMs = watch.elapsedMilliseconds;
    final timings =
        '字体复核：${detectionMs}ms；旧检测识别：${baselineMs}ms；两行截图：${captureMs}ms；两行直接识别：${recognitionMs}ms；缓存：${cachedMs}ms；两字识别：${shortMs}ms';
    debugPrint(timings);
    await File('${dir.path}/timings.txt').writeAsString(timings);
    final session = await EpubEditSession.open(File(sample));
    addTearDown(session.close);
    final range = SelectionOps.cfiOf(selection)!;
    final edit = EpubParagraphEdit.fromSelection(
      session,
      page.spineIndex,
      range.start,
      range.end,
      recognizedText: recognized,
      sourceText: raw,
    );
    edit.apply('$recognized（本地编辑验证）');
    final output = File('${temporary.path}/edited.epub');
    await EpubWriter.write(session, output);
    final reopened = await EpubChapterSource.openFile(
      output,
      contentWidth: 320,
      contentHeight: 640,
    );
    addTearDown(reopened.close);
    final updatedPages = await reopened.loadChapter(page.spineIndex);
    expect(
      updatedPages
          .expand(TextHitTester.lineBoxes)
          .map((line) => line.text)
          .join(),
      contains('（本地编辑验证）'),
    );
    final recorder = ui.PictureRecorder();
    const PagePainter().paint(
      Canvas(recorder),
      page,
      pageSize: const Size(320, 640),
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(320, 640);
    picture.dispose();
    await File('${dir.path}/page.png').writeAsBytes(
      (await rendered.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
    rendered.dispose();
  }, skip: sample.isEmpty ? '需用 OCR_SAMPLE_EPUB 指定用户本地样书' : false);
}
