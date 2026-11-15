import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/paint/background_tiles.dart';

const _spaceX = CssBackgroundRepeat.axes(
  CssBackgroundRepeatMode.space,
  CssBackgroundRepeatMode.noRepeat,
);
const _roundX = CssBackgroundRepeat.axes(
  CssBackgroundRepeatMode.round,
  CssBackgroundRepeatMode.noRepeat,
);

void main() {
  test('space 首尾贴合定位区，至少两张时忽略该轴 position', () {
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(10, 20, 10, 4),
      const CssBackgroundLayer(
        repeat: _spaceX,
        position: CssBackgroundPosition(
          x: CssLength(100, isPercent: true),
          y: CssLength(0),
        ),
      ),
      intrinsicSize: const Size(4, 4),
    ).toList();
    expect(tiles, const [
      Rect.fromLTWH(10, 20, 4, 4),
      Rect.fromLTWH(16, 20, 4, 4),
    ]);
  });

  for (final width in [3.0, 6.0]) {
    test('space 可容纳不足两张时按位置绘制一张（宽 $width）', () {
      final tiles = backgroundTileRects(
        Rect.fromLTWH(0, 0, width, 6),
        const CssBackgroundLayer(
          repeat: _spaceX,
          position: CssBackgroundPosition(
            x: CssLength(50, isPercent: true),
            y: CssLength(50, isPercent: true),
          ),
        ),
        intrinsicSize: const Size(4, 4),
      ).toList();
      expect(tiles, [Rect.fromLTWH((width - 4) / 2, 1, 4, 4)]);
    });
  }

  test('round 调整整数瓦片数，并保持另一轴 auto 的图片比例', () {
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(0, 0, 10, 7),
      const CssBackgroundLayer(repeat: _roundX),
      intrinsicSize: const Size(4, 2),
    ).toList();
    expect(tiles, hasLength(3));
    expect(tiles.first.width, closeTo(10 / 3, 1e-10));
    expect(tiles.first.height, closeTo(5 / 3, 1e-10));
    expect(tiles.last.right, closeTo(10, 1e-10));
  });

  test('round 不改变另一轴的明确尺寸，两个 round 独立填满各轴', () {
    final explicit = backgroundTileRects(
      const Rect.fromLTWH(0, 0, 10, 7),
      const CssBackgroundLayer(
        repeat: _roundX,
        size: CssBackgroundSize.explicit(
          width: CssLength(4),
          height: CssLength(3),
        ),
      ),
      intrinsicSize: const Size(4, 2),
    ).toList();
    expect(explicit.first.height, 3);
    final both = backgroundTileRects(
      const Rect.fromLTWH(0, 0, 10, 7),
      const CssBackgroundLayer(
        repeat: CssBackgroundRepeat.axes(
          CssBackgroundRepeatMode.round,
          CssBackgroundRepeatMode.round,
        ),
      ),
      intrinsicSize: const Size(4, 2),
    ).toList();
    expect(both, hasLength(12));
    expect(both.last.right, closeTo(10, 1e-10));
    expect(both.last.bottom, closeTo(7, 1e-10));
  });

  test('round 按缩放后的瓦片尺寸解算百分比定位', () {
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(0, 0, 30, 12),
      const CssBackgroundLayer(
        repeat: _roundX,
        size: CssBackgroundSize.explicit(width: CssLength(12)),
        position: CssBackgroundPosition(
          x: CssLength(25, isPercent: true),
          y: CssLength(0),
        ),
      ),
      intrinsicSize: const Size(2, 2),
    ).toList();
    expect(tiles.map((tile) => tile.left), [-5, 5, 15, 25]);
    expect(tiles.every((tile) => tile.width == 10), isTrue);
  });

  test('渐变没有固有比例，round 不缩放另一轴 auto', () {
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(0, 0, 10, 8),
      const CssBackgroundLayer(
        repeat: _roundX,
        size: CssBackgroundSize.explicit(width: CssLength(4)),
      ),
    ).toList();
    expect(tiles, hasLength(3));
    expect(tiles.first.height, 8);
  });

  test('space 保持定位区间隔，继续覆盖更大的绘制区', () {
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(10, 0, 10, 4),
      const CssBackgroundLayer(repeat: _spaceX),
      intrinsicSize: const Size(4, 4),
      paintingBounds: const Rect.fromLTWH(0, 0, 30, 4),
    ).toList();
    expect(tiles.map((tile) => tile.left), [-2, 4, 10, 16, 22, 28]);
  });

  test('巨大定位区仅计算可见绘制范围内的瓦片', () {
    for (final repeat in [_spaceX, _roundX, CssBackgroundRepeat.repeatX]) {
      final tiles = backgroundTileRects(
        const Rect.fromLTWH(0, 0, 1e9, 4),
        CssBackgroundLayer(repeat: repeat),
        intrinsicSize: const Size(4, 4),
        paintingBounds: const Rect.fromLTWH(0, 0, 30, 4),
      ).toList();
      expect(tiles.map((tile) => tile.left), [0, 4, 8, 12, 16, 20, 24, 28]);
    }
  });

  for (final (area, edge, expectedCount) in [
    (const Size(1200, 900), 1.0, 1080000),
    (const Size(400, 800), 0.5, 1280000),
  ]) {
    test('稠密背景 ${area.width}×${area.height}/$edge 超预算后只铺一张', () {
      final before = BackgroundTileDiagnostics.fallbackCount;
      final diagnostics = <BackgroundTileLimitDiagnostic>[];
      final tiles = backgroundTileRects(
        Offset.zero & area,
        CssBackgroundLayer(
          size: CssBackgroundSize.explicit(
            width: CssLength(edge),
            height: CssLength(edge),
          ),
        ),
        intrinsicSize: const Size(1, 1),
        onLimitExceeded: diagnostics.add,
      ).toList();
      expect(tiles, [Offset.zero & area]);
      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single.columns * diagnostics.single.rows,
        expectedCount,
      );
      expect(diagnostics.single.maximumTiles, defaultBackgroundTileLimit);
      expect(
        diagnostics.single.message,
        startsWith('W_BACKGROUND_TILE_LIMIT:'),
      );
      expect(BackgroundTileDiagnostics.fallbackCount, before + 1);
      expect(BackgroundTileDiagnostics.lastFallback, same(diagnostics.single));
    });
  }

  test('上限边界包含最后一张，允许调用方调整预算', () {
    const layer = CssBackgroundLayer(
      size: CssBackgroundSize.explicit(
        width: CssLength(1),
        height: CssLength(1),
      ),
    );
    const bounds = Rect.fromLTWH(0, 0, 3, 2);
    final before = BackgroundTileDiagnostics.fallbackCount;
    expect(backgroundTileRects(bounds, layer, maximumTiles: 6), hasLength(6));
    expect(BackgroundTileDiagnostics.fallbackCount, before);
    expect(backgroundTileRects(bounds, layer, maximumTiles: 5), [bounds]);
    expect(BackgroundTileDiagnostics.fallbackCount, before + 1);
    expect(BackgroundTileDiagnostics.lastFallback?.maximumTiles, 5);
    expect(
      () => backgroundTileRects(bounds, layer, maximumTiles: 0).toList(),
      throwsArgumentError,
    );
  });

  test('每轴未超限但乘积超限时仍降级到完整绘制区', () {
    const painting = Rect.fromLTWH(-10, -10, 100, 100);
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(0, 0, 10, 10),
      const CssBackgroundLayer(),
      intrinsicSize: const Size(1, 1),
      paintingBounds: painting,
    ).toList();
    expect(tiles, [painting]);
    expect(BackgroundTileDiagnostics.lastFallback?.columns, 100);
    expect(BackgroundTileDiagnostics.lastFallback?.rows, 100);
  });

  test('极小尺寸与无法表达的轴计数在循环前降级', () {
    for (final mode in [
      CssBackgroundRepeatMode.repeat,
      CssBackgroundRepeatMode.space,
      CssBackgroundRepeatMode.round,
    ]) {
      for (final edge in [1e-10, 1e-300, 1e-320]) {
        const bounds = Rect.fromLTWH(0, 0, 100, 100);
        expect(
          backgroundTileRects(
            bounds,
            CssBackgroundLayer(
              repeat: CssBackgroundRepeat.axes(mode, mode),
              size: CssBackgroundSize.explicit(
                width: CssLength(edge),
                height: CssLength(edge),
              ),
            ),
          ),
          [bounds],
          reason: '${mode.name}/$edge 只产生一张有限矩形',
        );
      }
    }
  });

  test('坐标精度不足以继续前进时停止该轴，不重复生成同一位置', () {
    final tiles = backgroundTileRects(
      const Rect.fromLTWH(1e16, 0, 16, 1),
      const CssBackgroundLayer(
        repeat: CssBackgroundRepeat.repeatX,
        size: CssBackgroundSize.explicit(
          width: CssLength(1.5),
          height: CssLength(1),
        ),
      ),
    ).toList();
    expect(tiles, hasLength(3));
    expect(tiles.map((tile) => tile.left).toSet(), hasLength(tiles.length));
    expect(tiles.every((tile) => tile.isFinite && !tile.isEmpty), isTrue);
  });

  test('有限位置与尺寸相加溢出时不产生非有限矩形', () {
    expect(
      backgroundTileRects(
        const Rect.fromLTWH(1e308, 0, 1e307, 1),
        const CssBackgroundLayer(
          repeat: CssBackgroundRepeat.noRepeat,
          size: CssBackgroundSize.explicit(
            width: CssLength(1e308),
            height: CssLength(1),
          ),
        ),
      ),
      isEmpty,
    );
  });

  test('一轴不可见时立即退出，不遍历另一轴的巨大有限序列', () {
    expect(
      backgroundTileRects(
        const Rect.fromLTWH(0, 0, 100, 100),
        const CssBackgroundLayer(
          repeat: CssBackgroundRepeat.repeatY,
          size: CssBackgroundSize.explicit(
            width: CssLength(1),
            height: CssLength(1e-10),
          ),
          position: CssBackgroundPosition(x: CssLength(200), y: CssLength(0)),
        ),
      ),
      isEmpty,
    );
  });

  test('空区域和非有限尺寸不会产生瓦片', () {
    for (final width in [0.0, double.infinity]) {
      final tiles = backgroundTileRects(
        const Rect.fromLTWH(0, 0, 100, 100),
        CssBackgroundLayer(
          size: CssBackgroundSize.explicit(
            width: CssLength(width),
            height: const CssLength(1),
          ),
        ),
        intrinsicSize: const Size(4, 4),
      );
      expect(tiles, isEmpty);
    }
    expect(backgroundTileRects(Rect.zero, const CssBackgroundLayer()), isEmpty);
  });
}
