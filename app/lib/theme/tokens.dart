/// 设计 token (从原型/参考图反解得出)
///
/// v1.2 增 dark 模式 + 字号缩放
library tokens;

import 'package:flutter/material.dart';

import '../data/settings_service.dart';

class L {
  // 品牌
  static const brandYellow      = Color(0xFFFFD946);
  static const brandYellowTrack = Color(0xFFFFFBD7);

  // 文字 (light)
  static const textPrimary   = Color(0xFF1A1A1A);
  static const textBody      = Color(0xFF333333);
  static const textSecondary = Color(0xFF8F8F8F);
  static const textTertiary  = Color(0xFF6B6B6B);
  static const textDisabled  = Color(0xFFC8C8C8);

  // 文字 (dark)
  static const dTextPrimary   = Color(0xFFE8E8E8);
  static const dTextBody      = Color(0xFFD0D0D0);
  static const dTextSecondary = Color(0xFF9A9A9A);
  static const dTextTertiary  = Color(0xFF777777);
  static const dTextDisabled  = Color(0xFF4A4A4A);

  // 表面
  static const surface       = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFF5F5F5);
  static const surfaceNote   = Color(0xFFECF0F3);

  // 表面 (dark)
  static const dSurface       = Color(0xFF1A1A1A);
  static const dSurfaceSubtle = Color(0xFF111111);
  static const dSurfaceNote   = Color(0xFF242424);

  // 分割
  static const dividerStrong = Color(0xFFD7D7D7);
  static const dividerLight  = Color(0xFFF0F0F0);
  static const dDividerStrong = Color(0xFF333333);
  static const dDividerLight  = Color(0xFF222222);

  // 图表
  static const chartGrid     = Color(0xFFE6E6E6);
  static const chartAxis     = Color(0xFFBCBCBC);
  static const chartLine     = Color(0xFF4A4A4A);
  static const dChartGrid    = Color(0xFF2A2A2A);
  static const dChartAxis    = Color(0xFF555555);
  static const dChartLine    = Color(0xFFBBBBBB);

  // 其他
  static const segmentSelected = Color(0xFF363233);
  static const warnRed         = Color(0xFFF5222D);
  static const dWarnRed        = Color(0xFFFF4D4D);
  static const okGreen         = Color(0xFF4FBC8B);
  static const dOkGreen        = Color(0xFF6FCFA2);

  // 间距
  static const pageH = 16.0;
  static const cardR = 12.0;
  static const btnR  = 8.0;
}

/// 字号缩放: 1.0 (medium) / 0.9 (small) / 1.15 (large)
double fontScaleOf(FontScale s) {
  switch (s) {
    case FontScale.small:  return 0.9;
    case FontScale.medium: return 1.0;
    case FontScale.large:  return 1.15;
  }
}

ThemeData buildLightTheme({double fontScale = 1.0}) {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: L.surfaceSubtle,
    colorScheme: base.colorScheme.copyWith(
      primary: L.brandYellow,
      onPrimary: L.textPrimary,
      secondary: L.textPrimary,
      surface: L.surface,
      error: L.warnRed,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: L.surfaceSubtle,
      foregroundColor: L.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: L.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: _textTheme(
      base.textTheme.apply(bodyColor: L.textBody, displayColor: L.textPrimary),
      scale: fontScale,
      light: true,
    ),
    cardTheme: const CardThemeData(
      color: L.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(L.cardR)),
      ),
    ),
    dividerColor: L.dividerLight,
  );
}

ThemeData buildDarkTheme({double fontScale = 1.0}) {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: L.dSurfaceSubtle,
    colorScheme: base.colorScheme.copyWith(
      primary: L.brandYellow,
      onPrimary: L.textPrimary,
      secondary: L.dTextPrimary,
      surface: L.dSurface,
      error: L.dWarnRed,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: L.dSurfaceSubtle,
      foregroundColor: L.dTextPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: L.dTextPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: _textTheme(
      base.textTheme.apply(bodyColor: L.dTextBody, displayColor: L.dTextPrimary),
      scale: fontScale,
      light: false,
    ),
    cardTheme: const CardThemeData(
      color: L.dSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(L.cardR)),
      ),
    ),
    dividerColor: L.dDividerLight,
  );
}

TextTheme _textTheme(TextTheme base, {required double scale, required bool light}) {
  TextStyle? s(TextStyle? st) {
    if (st == null) return null;
    return st.copyWith(fontSize: (st.fontSize ?? 14) * scale);
  }
  return base.copyWith(
    titleLarge: s(base.titleLarge),
    titleMedium: s(base.titleMedium),
    titleSmall: s(base.titleSmall),
    bodyLarge: s(base.bodyLarge),
    bodyMedium: s(base.bodyMedium),
    bodySmall: s(base.bodySmall),
    labelLarge: s(base.labelLarge),
    labelMedium: s(base.labelMedium),
    labelSmall: s(base.labelSmall),
  );
}
