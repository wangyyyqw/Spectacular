import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/ye_she_visuals.dart';

void main() {
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
