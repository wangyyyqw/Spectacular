import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_search_bar.dart';
import 'desktop_layout.dart';

abstract final class BookCollectionLayout {
  static const inset = 16.0;
  static const rowPadding = EdgeInsets.symmetric(vertical: 8);
  static const rowSeparator = 1.0;
  static const rowTextGap = 14.0;
  static const coverAspectRatio = 3 / 4;
  static const titleGap = 6.0;
  static const titleHeight = 20.0;

  static double toolbarGap(BuildContext context) =>
      usesDesktopLayout(context) ? 12 : 8;

  static Size listCover(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(
          text: '阅微 Ag',
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final contentHeight = lineHeight(theme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)) +
        3 * lineHeight(theme.bodySmall) + 3 * scaler.scale(4);
    final height = math.max(88.0, contentHeight + 8);
    return Size(height * coverAspectRatio, height);
  }

  static double listInset(BuildContext context, double width) =>
      usesDesktopLayout(context) ? math.max(inset, (width - 920) / 2) : inset;

  static ({
    SliverGridDelegateWithFixedCrossAxisCount delegate,
    double cardWidth,
  })
  grid(BuildContext context, double width, {bool showTitles = true}) {
    const spacing = 16.0;
    const desktopMaxCoverWidth = 160.0;
    const mobileTargetCoverWidth = 192.0;
    final desktop = usesDesktopLayout(context);
    if (desktop) width = math.min(width, desktopBookPageMaxWidth);
    final available = width - inset * 2;
    final columns = desktop
        ? math.max(
            1,
            ((available + spacing) / (desktopMaxCoverWidth + spacing)).ceil(),
          )
        : math.max(
            3,
            (available + spacing) ~/ (mobileTargetCoverWidth + spacing),
          );
    final cardWidth = (available - spacing * (columns - 1)) / columns;
    return (
      delegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent:
            cardWidth / coverAspectRatio +
            (showTitles
                ? titleGap + MediaQuery.textScalerOf(context).scale(titleHeight)
                : 0),
        mainAxisSpacing: 20,
        crossAxisSpacing: spacing,
      ),
      cardWidth: cardWidth,
    );
  }
}
