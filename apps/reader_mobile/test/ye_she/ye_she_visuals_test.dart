import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/ye_she_visuals.dart';
import 'package:reader_mobile/theme/app_theme.dart';

void main() {
  for (final style in AppUiStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${style.name}/${brightness.name} 野社配色与空态随主题', (
        tester,
      ) async {
        final theme = buildAppTheme(
          uiStyle: style,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        );
        late BuildContext captured;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  captured = context;
                  return const Column(
                    children: [
                      YeSheTag('状态'),
                      YeSheEmpty('暂无记录'),
                      YeSheSectionLabel('社群'),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        final md3 = style == AppUiStyle.material3;
        final color = YeSheTokens.vermilion(captured);
        expect(
          color,
          md3
              ? theme.colorScheme.primary
              : brightness == Brightness.dark
              ? const Color(0xFFE3A08C)
              : const Color(0xFFA34A34),
        );
        final luminance = [
          color.computeLuminance(),
          theme.colorScheme.surface.computeLuminance(),
        ]..sort();
        expect(
          (luminance.last + .05) / (luminance.first + .05),
          greaterThan(4.5),
        );
        if (md3) {
          expect(YeSheTokens.jade(captured), theme.colorScheme.secondary);
          expect(YeSheTokens.gold(captured), theme.colorScheme.tertiary);
          expect(
            YeSheTokens.wash(captured),
            theme.colorScheme.surfaceContainerLow,
          );
        }
        final empty = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(YeSheEmpty),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (empty.decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(md3 ? 12 : 4),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('野社图片地址补全站内路径与协议', () {
    expect(yeSheImageUrl(''), '');
    expect(
      yeSheImageUrl('https://cdn.example.com/a.png'),
      'https://cdn.example.com/a.png',
    );
    expect(
      yeSheImageUrl('//cdn.example.com/a.png'),
      'https://cdn.example.com/a.png',
    );
    expect(
      yeSheImageUrl('/uploads/avatar/a.png'),
      'https://api.reamicro.zhendong.ltd/uploads/avatar/a.png',
    );
    expect(
      yeSheImageUrl('uploads/cover/a.png'),
      'https://api.reamicro.zhendong.ltd/uploads/cover/a.png',
    );
    expect(yeSheImageUrl('file:///tmp/a.png'), 'file:///tmp/a.png');
    expect(
      yeSheImageUrl('data:image/png;base64,AA=='),
      'data:image/png;base64,AA==',
    );
  });

  test('野社图片源识别 data 地址并保留空地址', () {
    expect(
      yeSheImageProvider('data:image/png;base64,AA=='),
      isA<MemoryImage>(),
    );
    expect(yeSheImageProvider(''), isNull);
  });

  test('野社本地素材按标识稳定选择', () {
    expect(YeSheTokens.sealAsset(21), endsWith('seal_21.webp'));
    expect(YeSheTokens.cityAsset(3), endsWith('shrine_city_4.webp'));
    expect(
      YeSheTokens.callingCardAsset('惊鸿'),
      endsWith('calling_card_jinghong.webp'),
    );
    expect(
      YeSheTokens.retainerAsset('shen-qi'),
      matches(RegExp(r'shrine_npc_\d+\.webp$')),
    );
    expect(YeSheTokens.auctionAsset('青瓷笔洗'), endsWith('shrine_auction_5.webp'));
    expect(YeSheTokens.medalAsset(33), endsWith('medal_33.png'));
    expect(YeSheTokens.medalAsset(45), endsWith('medal_45.png'));
    expect(YeSheTokens.medalAsset(99), endsWith('medal_fallback.png'));
  });

  testWidgets('头像空地址显示默认资源', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: YeSheAvatar(url: '')),
        ),
      ),
    );

    expect(find.byType(YeSheAvatar), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('头像网络失败回退默认资源', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: YeSheAvatar(url: 'https://invalid.invalid/avatar.png'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(YeSheAvatar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
