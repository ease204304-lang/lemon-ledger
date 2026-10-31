/// 主题/字号 Provider (S1)
///
/// 状态: (themeMode, fontScale)
/// notifier: load() 从 SharedPreferences 灌值
///         setTheme(AppTheme) / setFontScale(FontScale) 持久化 + 改 state
///
/// 跨屏共享: 任何 widget 改主题/字号, 所有 ref.watch(themeProvider) 都会重 build
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_service.dart';

class ThemeState {
  final ThemeMode themeMode;
  final FontScale fontScale;
  const ThemeState({
    required this.themeMode,
    required this.fontScale,
  });

  ThemeState copyWith({ThemeMode? themeMode, FontScale? fontScale}) =>
      ThemeState(
        themeMode: themeMode ?? this.themeMode,
        fontScale: fontScale ?? this.fontScale,
      );

  static const initial = ThemeState(
    themeMode: ThemeMode.system,
    fontScale: FontScale.medium,
  );
}

class ThemeNotifier extends Notifier<ThemeState> {
  @override
  ThemeState build() => ThemeState.initial;

  /// 启动时从 SharedPreferences 加载 (一次性)
  Future<void> load() async {
    final t = await SettingsService.instance.getTheme();
    final f = await SettingsService.instance.getFontScale();
    state = ThemeState(themeMode: _toMode(t), fontScale: f);
  }

  /// 用户切换主题: 持久化 + state
  Future<void> setTheme(AppTheme t) async {
    await SettingsService.instance.setTheme(t);
    state = state.copyWith(themeMode: _toMode(t));
  }

  Future<void> setFontScale(FontScale f) async {
    await SettingsService.instance.setFontScale(f);
    state = state.copyWith(fontScale: f);
  }

  static ThemeMode _toMode(AppTheme t) => switch (t) {
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
        AppTheme.system => ThemeMode.system,
      };
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeState>(
  ThemeNotifier.new,
);
