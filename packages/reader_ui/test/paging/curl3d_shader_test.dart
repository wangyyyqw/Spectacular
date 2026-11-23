import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/curl3d_shader.dart';

Future<ui.Image> _paper() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFF0000), BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(50, 0, 50, 100),
    Paint()..color = const Color(0xFF0000FF),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(100, 100);
  picture.dispose();
  return image;
}

Future<ui.Image> _colorPaper(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(100, 100);
  picture.dispose();
  return image;
}

ui.FragmentShader _shader(
  ui.Image paper,
  List<double> normals, {
  Color background = const Color(0xFFFFFFFF),
}) {
  final shader = Curl3dShader.program!.fragmentShader();
  // 引擎使用未初始化的 uniform 内存，夹具需明确设置阴影平面与边界。
  for (
    var index = 0;
    index < Curl3dShader.shadowEdgesOffset + 12;
    index++
  ) {
    shader.setFloat(index, 0);
  }
  final values = <double>[
    100,
    100,
    background.r,
    background.g,
    background.b,
    background.a,
    0,
    0,
    paper.width.toDouble(),
    paper.height.toDouble(),
    paper.width.toDouble(),
    paper.height.toDouble(),
    0,
    0,
    1,
    0,
    2,
    0,
    0,
    normals[0],
    normals[2],
    for (var index = 1; index < Curl3dShader.profileCapacity; index++) ...[
      200,
      100,
      normals[3],
      normals[5],
    ],
  ];
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
  shader.setImageSampler(0, paper);
  shader.setImageSampler(1, paper);
  return shader;
}

Future<ByteData> _render(
  ui.Image paper,
  List<double> normals, {
  Color background = const Color(0xFFFFFFFF),
}) async {
  await Curl3dShader.load();
  final shader = _shader(paper, normals, background: background);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final vertices = ui.Vertices(ui.VertexMode.triangles, const [
    Offset.zero,
    Offset(200, 0),
    Offset(0, 200),
  ]);
  canvas.drawVertices(vertices, BlendMode.src, Paint()..shader = shader);
  shader.dispose();
  vertices.dispose();
  return _readPixels(recorder);
}

Future<ByteData> _readPixels(ui.PictureRecorder recorder) async {
  final picture = recorder.endRecording();
  final image = picture.toImageSync(200, 200);
  picture.dispose();
  final bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

Future<ByteData> _renderShadow(int alphaIndex) async {
  await Curl3dShader.load();
  final shader = Curl3dShader.shadowProgram!.fragmentShader();
  for (
    var index = 0;
    index < Curl3dShader.shadowTriangleCapacity * 16;
    index++
  ) {
    shader.setFloat(index, 0);
  }
  shader.setFloat(2, alphaIndex / 255 * 0.5);
  shader.setFloat(3, 1);
  // 模拟上一批残留的透明度：未启用的槽位不能参与当前批次混合。
  shader.setFloat(18, 0.5);
  final vertices = ui.Vertices(ui.VertexMode.triangles, const [
    Offset.zero,
    Offset(200, 0),
    Offset(0, 200),
  ]);
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawVertices(vertices, BlendMode.src, Paint()..shader = shader);
  shader.dispose();
  vertices.dispose();
  return _readPixels(recorder);
}

Future<ByteData> _renderPair(ui.Image paper) async {
  await Curl3dShader.load();
  final shader = _shader(paper, [0, 0, 1, 0, 0, 1, 0, 0, 1]);
  final paint = Paint()..shader = shader;
  final vertices = ui.Vertices(ui.VertexMode.triangles, const [
    Offset.zero,
    Offset(100, 0),
    Offset(0, 100),
  ]);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawVertices(vertices, BlendMode.src, paint);
  for (final index in [20, 24]) {
    shader.setFloat(index, -1);
  }
  canvas.translate(100, 0);
  canvas.drawVertices(vertices, BlendMode.src, paint);
  shader.dispose();
  vertices.dispose();
  return _readPixels(recorder);
}

List<int> _pixel(ByteData bytes, int x, int y) {
  final offset = (y * 200 + x) * 4;
  return List.generate(4, (channel) => bytes.getUint8(offset + channel));
}

void main() {
  testWidgets('阴影片元写回匹配 GLES 透明度端点和敏感色阶', (tester) async {
    // 阴影像素的 RGBA8 读回；包含最近取整会误加一级的位置。
    for (final swatch in {
      0: 0,
      1: 0,
      2: 1,
      9: 4,
      127: 63,
      128: 64,
      254: 127,
      255: 128,
    }.entries) {
      final bytes = (await tester.runAsync(
        () => _renderShadow(swatch.key),
      ))!;
      expect(_pixel(bytes, 20, 20), [0, 0, 0, swatch.value]);
    }
  });

  for (final swatch in <Color, List<int>>{
    const Color(0xFF808080): [132, 129, 132, 255],
    const Color(0xFF123456): [16, 53, 82, 255],
    const Color(0xFF84A7C3): [132, 166, 197, 255],
  }.entries) {
    testWidgets('RGB565 正面采样匹配 GLES 色块 ${swatch.key}', (tester) async {
      final paper = (await tester.runAsync(() => _colorPaper(swatch.key)))!;
      addTearDown(paper.dispose);
      final bytes = (await tester.runAsync(
        () => _render(paper, [0, 0, 1, 0, 0, 1, 0, 0, 1]),
      ))!;
      expect(_pixel(bytes, 20, 20), swatch.value);
    });
  }

  testWidgets('纸背按混色写回顺序取整', (tester) async {
    final paper = (await tester.runAsync(
      () => _colorPaper(const Color(0xFF123456)),
    ))!;
    addTearDown(paper.dispose);
    final bytes = (await tester.runAsync(
      () => _render(paper, [
        0,
        0,
        -1,
        0,
        0,
        -1,
        0,
        0,
        -1,
      ], background: const Color(0xFFFFFDF4)),
    ))!;
    // GLSL + RGB565 多色色带，平直纸背、无阴影位置的实际读回值。
    expect(_pixel(bytes, 20, 20), [243, 245, 238, 255]);
  });

  testWidgets('片元坐标使用纸面UV，变形后图案仍固定在纸上', (tester) async {
    final paper = (await tester.runAsync(_paper))!;
    addTearDown(paper.dispose);
    final bytes = (await tester.runAsync(
      () => _render(paper, [0, 0, 1, 0, 0, 1, 0, 0, 1]),
    ))!;
    expect(_pixel(bytes, 80, 20), [255, 0, 0, 255]);
    expect(_pixel(bytes, 120, 20), [0, 0, 255, 255]);
  });

  testWidgets('纸背按片元归一化完整法线后混合透印与背景', (tester) async {
    final paper = (await tester.runAsync(_paper))!;
    addTearDown(paper.dispose);
    final bytes = (await tester.runAsync(
      () => _render(paper, [1, 0, 0, 0, 0, -1, 1, 0, 0]),
    ))!;
    // x=80映射到UV40，权重约0.4；normalize(0.6,0,-0.4).z≈-0.5547。
    final pixel = _pixel(bytes, 80, 20);
    expect(pixel[0], closeTo(198, 2));
    expect(pixel[1], closeTo(188, 2));
    expect(pixel[2], closeTo(188, 2));
    expect(pixel[3], 255);
  });

  testWidgets('同一着色器连续绘制保留各三角形的法线数据', (tester) async {
    final paper = (await tester.runAsync(_paper))!;
    addTearDown(paper.dispose);
    final bytes = (await tester.runAsync(() => _renderPair(paper)))!;
    expect(_pixel(bytes, 20, 20), [255, 0, 0, 255]);
    expect(_pixel(bytes, 120, 20), [255, 242, 242, 255]);
  });
}
