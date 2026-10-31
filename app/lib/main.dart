/// 小猪记账 入口
///
/// S1 改造:
///   - runApp 用 ProviderScope 包裹 (子 widget 可 ref.watch/read)
///   - LemonLedgerApp 改成 ConsumerStatefulWidget, 主题/字号从 themeProvider 读
///   - updateTheme / updateFontScale 改成调 provider.notifier
///   - RootShell 后续步骤再改成 ConsumerStatefulWidget
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/theme_provider.dart';
import 'screens/chart_page.dart';
import 'screens/discover_page.dart';
import 'screens/entry_page.dart';
import 'screens/home_page.dart';
import 'screens/mine_page.dart';
import 'theme/tokens.dart';
import 'widgets/error_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  // E1: 替换默认红屏 / 黑屏 → 友好错误页
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      AppErrorScreen(details: details);
  // E1: 异步异常 (zone 外) 也捕获
  installGlobalErrorHandlers();
  // S1: 整个 app 用 ProviderScope 包裹, 子树可以 ref.watch / ref.read
  runApp(
    const ProviderScope(
      child: LemonLedgerApp(),
    ),
  );
}

class LemonLedgerApp extends ConsumerStatefulWidget {
  const LemonLedgerApp({super.key});
  @override
  ConsumerState<LemonLedgerApp> createState() => LemonLedgerAppState();
}

class LemonLedgerAppState extends ConsumerState<LemonLedgerApp> {
  // S1: 加载状态还是 widget 内部 (只启动时一次, 没必要做 provider)
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // 启动时从 SettingsService 把持久化值灌到 themeProvider
    _initFromSettings();
  }

  Future<void> _initFromSettings() async {
    await ref.read(themeProvider.notifier).load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        // 国际化: DatePicker/Cupertino widgets 需要
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    // S1: 主题/字号从 themeProvider 读, 改的时候调 notifier
    final t = ref.watch(themeProvider);
    return MaterialApp(
      title: '小猪记账',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(fontScale: fontScaleOf(t.fontScale)),
      darkTheme: buildDarkTheme(fontScale: fontScaleOf(t.fontScale)),
      themeMode: t.themeMode,
      // 国际化: DatePicker/Cupertino widgets 需要
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  void _nav(int i) {
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // v1.8.1 Bug 修复: 系统回退键在非首页 tab 时直接退出应用
    // (RootShell 用 IndexedStack 式换页, 没有路由可 pop)
    // 修复: 非首页时拦截回退 → 回首页; 首页时才允许退出应用。
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return; // 首页: 允许退出
        _nav(0); // 其他 tab: 回首页
      },
      child: _buildPage(),
    );
  }

  Widget _buildPage() {
    switch (_index) {
      case 1: return ChartPage(onNavigate: _nav);
      case 2: return EntryPage(onNavigate: _nav);
      case 3: return DiscoverPage(onNavigate: _nav);
      case 4: return MinePage(onNavigate: _nav);
      case 0:
      default:
        return HomePage(onNavigate: _nav);
    }
  }
}
