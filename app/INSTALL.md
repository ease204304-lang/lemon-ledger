# 小猪记账 v1.9.0 — 安装与运行

> 当前版本: **v1.9.0 (build 28)** · 2026-10-31
> APK: `D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk` (54.3 MB)

---

## 1. APK 文件

| 类型 | 路径 | 大小 |
|---|---|---|
| **Release APK (推荐)** | `D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk` | **54.3 MB** |
| Debug APK (调试) | `D:\DSH\Account\app\build\app\outputs\flutter-apk\app-debug.apk` | ~192 MB |

Release 包已 AOT 编译, 体积小, 启动快, 适合真机发布.

## 2. 安装步骤

### 2.1 在 Android 模拟器上安装

```bash
# 启动模拟器
& 'D:\07.DevWorkspace\android-sdk\emulator\emulator.exe' -avd lemon_test -no-window -no-audio

# 等待 adb 检测到设备 (约 5-30 秒)
adb devices
# 期望: emulator-5554    device

# 安装 Release APK
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk
```

### 2.2 在真机上安装

```bash
# 1. USB 连接手机, 开启 USB 调试 (设置 → 开发者选项 → USB 调试)
# 2. 验证连接
adb devices
# 期望: 你的设备序列号    device

# 3. 安装
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk
```

### 2.3 卸载旧版本 (如果升 v1.6.4)

```bash
# 保留数据
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk

# 完全卸载
adb uninstall com.lemonledger.lemon_ledger
adb install D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk
```

## 3. 启动 App

```bash
# 方式 1: 通过包名 + 完整 activity
adb shell am start -n com.lemonledger.lemon_ledger/com.lemonledger.lemon_ledger.MainActivity

# 方式 2: 简写 (Android 12+)
adb shell am start -n com.lemonledger.lemon_ledger/.MainActivity

# 方式 3: 用 monkey 启动默认 activity
adb shell monkey -p com.lemonledger.lemon_ledger -c android.intent.category.LAUNCHER 1
```

## 4. 数据完全本地

- ✅ 流水数据存在 `/data/data/com.lemonledger.lemon_ledger/app_flutter/lemon_ledger.db` (sqflite)
- ✅ 主题/字号存在 shared_preferences
- ✅ 标签存 sqflite
- ✅ **无网络请求**, 无云同步, 无账号系统
- ✅ 数据备份/恢复通过 JSON 文件 (用户可手动管理)

## 5. 重新构建

### 5.1 准备工具链

- Flutter 3.47.7+
- Android SDK 36 (compileSdk 36, minSdk 24)
- JDK 17
- 已配置 `init_env.ps1` (DSH 提供的包装器, 自动设置 PATH + 镜像)

### 5.2 构建命令

```bash
# 1. 设置环境 (DSH 包装器)
powershell -ExecutionPolicy Bypass -File D:\07.DevWorkspace\init_env.ps1 "cd /d D:\DSH\Account\app && <command>"
```

或者手动:
```bash
# 1. 装包
flutter pub get

# 2. 静态分析 (应 0 errors)
flutter analyze

# 3. 跑测试 (应 127/127 通过)
flutter test

# 4. 构建 Release APK
flutter build apk --release
# → D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk

# 5. 构建 Debug APK
flutter build apk --debug
# → D:\DSH\Account\app\build\app\outputs\flutter-apk\app-debug.apk
```

## 6. 功能验证清单 (v1.6.4)

### 6.1 5 屏基础
- [x] 应用启动, 5 tab (明细/图表/+ /发现/我的) 正常
- [x] **明细**: 黄色 header (10月/收入 50.00/支出 2,281.00) + 5 入口 + 10月9日 6 笔流水
- [x] **图表**: 周/月/年 segment + 折线图 (修复后) + 排行榜
- [x] **记帐** (v1.6 核心): 14 网格 + 4 常用 + 4×4 数字键盘 (完整可见, v1.6.4 修)
- [x] **发现**: 4 个占位卡片
- [x] **我的**: 5 项 + 关于 v1.6.4 + 重置数据 (二次确认)

### 6.2 录一笔 3 步流程
- [x] 点常用 (餐饮) → 黄色高亮 (左网格 + 右常用同步)
- [x] 输 `1+2+5` → 金额区显示 `4.00+5` (实时求值)
- [x] 按 `=` → 保存到 DB + 跳回首页 + 流水 +1

### 6.3 数据导入/导出
- [x] 我的 → 数据备份 → 选保存路径 → JSON 文件
- [x] 我的 → 数据恢复 → 选 JSON → 选合并/覆盖 → 输"确认" → 流水恢复
- [x] 我的 → 导出 CSV → 分享
- [x] 我的 → 导出 Excel (.xlsx) → 分享

### 6.4 已知限制 (模拟器)
- 模拟器中文 IME 不能直接输中文, 输"确认"需用 adb input text (但 uiautomator 测出 disabled 状态)
- 真机手指点击比 adb input 精准, = 按钮在真机上更好按

## 7. 截图 (5 张)

最新截图在 `D:\07.DevWorkspace\sys\final-0[1-5]-*.png`:

| # | 屏 | 文件 |
|---|---|---|
| 1 | 首页 | `final-01-home.png` |
| 2 | 图表 | `final-02-chart.png` |
| 3 | 记帐 (核心) | `final-03-entry.png` |
| 4 | 发现 | `final-04-discover.png` |
| 5 | 我的 | `final-05-mine.png` |

## 8. 卸载

```bash
# 完全卸载 (清空所有数据)
adb uninstall com.lemonledger.lemon_ledger
```

数据全在本地, 卸载后**无法恢复** (除非之前手动备份过 JSON).

## 9. 真机已知问题

- Android 11+ 应用沙盒, 备份/恢复需要走 SAF (`ACTION_OPEN_DOCUMENT`) 而不是经典文件路径 (v1.5 D2 已实现)
- Android 13+ 通知权限 (目前 APP 不用通知, 暂未申请)
- 麦克风权限 (v1.5 U2 实现, 第一次用会弹)

## 10. 升级流程 (v1.0 → v1.6.4)

```bash
# 1. 备份 (防升级失败丢数据)
adb shell am start -n com.lemonledger.lemon_ledger/.MainActivity
# 进入 "我的" → "数据备份" → 选保存路径

# 2. 装新 APK
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk

# 3. 验证 v1.6.4 已装
adb shell dumpsys package com.lemonledger.lemon_ledger | grep versionName
# 期望: versionName=1.6.4

# 4. 启动
adb shell am start -n com.lemonledger.lemon_ledger/.MainActivity
```

数据自动兼容 (v1.5+ 的 schema_version 包含向前兼容).

完整功能说明: `D:\DSH\Account\docs\FEATURE-v1.6.md`
完整版本历史: `D:\DSH\Account\app\VERSION.md`
项目 README: `D:\DSH\Account\app\README.md`
