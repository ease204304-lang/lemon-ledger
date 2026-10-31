/// 用户设置 (主题/字号/类别管理 等), 持久化到 shared_preferences
library;

import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme { light, dark, system }

enum FontScale { small, medium, large }

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const _kTheme = 'theme';
  static const _kFontScale = 'font_scale';

  Future<AppTheme> getTheme() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kTheme) ?? 'system';
    return AppTheme.values.firstWhere(
      (e) => e.name == s,
      orElse: () => AppTheme.system,
    );
  }

  Future<void> setTheme(AppTheme t) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, t.name);
  }

  Future<FontScale> getFontScale() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kFontScale) ?? 'medium';
    return FontScale.values.firstWhere(
      (e) => e.name == s,
      orElse: () => FontScale.medium,
    );
  }

  Future<void> setFontScale(FontScale f) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFontScale, f.name);
  }
}
