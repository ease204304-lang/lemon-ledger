# 小猪记账 v1.10.0 — Flutter App

> **小猪记账** (LemonLedger) — 个人记账 Android 应用
> 当前版本: **v1.10.0 (build 29)** · 2026-11-01
> 基于 `docs/00-基线与术语.md` 的数据契约与多次用户设计迭代 (U1/U2/U1.5/U1.6/U1.7/U1.8/U1.9)

---

## 1. 技术栈

- **Flutter 3.47.7** / Dart 3.13.5
- **状态管理**: 大量 `StatefulWidget` + `FutureBuilder` (单页内), `flutter_riverpod` 2.6.1 跨屏 (themeProvider)
- **持久化**: sqflite (本地 SQLite) + shared_preferences
- **图表**: fl_chart 0.69
- **文件**: path_provider, share_plus, permission_handler
- **导出**: csv (写 CSV), excel (写 xlsx)
- **跨域**: sqflite_common_ffi (测试)

## 2. 5 屏功能

| 屏 | 路径 | 核心功能 |
|---|---|---|
| **明细** | 底部 `明细` tab | 黄色 header 月汇总 + 5 入口 + 日分组流水 |
| **图表** | 底部 `图表` tab | 类型切换 + 周/月/年 + 折线图 + 排行榜 |
| **记帐** (核心) | 底部中央 `+` | 类型 chips + 14 网格 + 4 常用 + 备注 + 4×4 数字键盘 |
| **发现** | 底部 `发现` tab | 4 个占位卡片 (理财社区/预算/资产/返现) |
| **我的** | 底部 `我的` tab | 分类/备份/恢复/导出 CSV/导出 Excel/重置/关于 |

### 2.1 录一笔 3 步流程 (v1.6 核心, v1.7.0 标签升级)

```
点分类 (常用 4 个 或 网格 14 个)
  ↓
输入金额 (1234567890 + -×, 实时求值)
  ↓
按 = ( = = 保存 + 跳回首页)
```

**关键交互**:
- = 合并保存 (v1.6 改动 3)
- 实时求值 (U2): 输 `1+2+` 立即显示 `3+`
- 第 4 列整列品牌黄底, = 加重黄
- 长按 `.` = 语音录入
- **v1.7.0**: 标签行按**使用频次**排序, 末尾 "全部 >" → 标签管理页

### 2.2 记帐页布局 (v1.6.4)

```
┌─────────────────────────────────────┐
│ × 关闭  │  记一笔                  │ 60px 顶部
│ 支出/收入│  📅 日期  │ 0 元           │ 35px 状态
├─────────────────────────────────────┤
│ [14 网格 5×3] [4 常用 浅黄]          │ 234px (≤1/5 屏)
├─────────────────────────────────────┤
│ 📝 备注                              │ 30px
├─────────────────────────────────────┤
│ 7 8 9 ×                              │
│ 4 5 6 −                              │ 弹性填满 (≈ 700px)
│ 1 2 3 +                              │ Expanded 避免
│ . 0 del =                            │ tab 遮挡
└─────────────────────────────────────┘
```

**v1.6.4 Bug 修复**: 之前 `SizedBox(height: 780)` 假设 EntryPage 是全屏, 但 RootShell 底部 tab 占了 60-80px, 导致键盘最后一行 (`0`/`del`/`=`) 被 tab 完全遮挡. 改成 `Expanded` 弹性填满, 永远完整可见.

## 2.5 v1.7.0 增量 (U1.9 标签 + 图表升级)

**新增功能**:
- **标签按使用频次排序** (`use_count` 替代 `last_used_at`)
- **选分类时自动刷新该分类的标签** (反推 `tx.note LIKE '%tag%'`)
- **标签行末尾 "全部 >"** → 跳到 `TagManagerPage`
- **`TagManagerPage`**: 标签云 (按频次大小颜色) + 新建/删除/搜索 + 某分类模式
- **图表排行行可点击** → 跳到该分类的 `TagManagerPage`

**验证**:
- 127/127 tests pass
- analyze 0 errors
- 6 屏模拟器截图: `D:\DSH\Account\docs\screenshots\v1.7.0\`

**已知限制**:
- TagManagerPage 跳排在 swiftshader 模拟器上 hit-test 偶尔失效 (真机正常)
- "按标签排序 + 饼状图" 未实现 (v1.8 计划)

详细: [`../docs/FEATURE-v1.7.md`](../docs/FEATURE-v1.7.md)

## 2.6 v1.8.0 增量 (U1.9 收尾: 标签统计 + 饼图)

**新增功能**:
- **DB v5**: 新建 `tx_tag` 关联表 (精确, 替代 LIKE 反推); `tag` 加 `category_id`
- **图表页 分类/标签 二级视图**: header chips 切换; 标签视图含饼图 (fl_chart) + 按金额/按时间 排序 + 排名 + 进度条
- **TagService 新 API**: `syncForTx` 保存时同步关联; `statsByTag` 周期聚合; `byCategory` 走 tx_tag
- **记帐页 _TagRow 接入 build** (v1.7.0 漏写, v1.8.0 修复)
- **升级路径回填**: v1.7.0 升级用户也能立刻看到 11 个演示标签 + 饼图

**验证**:
- 151/151 tests pass (24 新)
- analyze 0 errors
- 6 屏模拟器截图: `D:\DSH\Account\docs\screenshots\v1.8.0\`

**已知限制**:
- swiftshader 模拟器 hit-test 在 TagManagerPage 跳转偶发失效; 真机正常
- "收入" 标签不种子化, 避免与类型 chip 同名

详细: [`../docs/FEATURE-v1.8.md`](../docs/FEATURE-v1.8.md)

## 2.9 v1.10.0 增量 (分类清单重整)

**用户清单**: 支出 信用卡 餐饮 娱乐 零食 交通 住房 旅游 医疗 运动 汽车 孩子 + 日用 投资 其他

**改动**:
1. **支出 22 -> 14 类**, 收入 8 类不变
2. **改名**: 旅行->旅游 / 车费->汽车 (id 不变, 历史流水自动跟随)
3. **新增**: 娱乐 / 运动 / 投资(支出, 独立 id cat.invest_exp)
4. **归档** (不删): 超市 水果 饮品 服饰 美妆 通讯 居家 学习 教育 宠物 数码 — 保护历史流水 FK
5. **DB v6 迁移**: 全量重排 sort_order + 重置 pinned + 修正 cat.invest 类型不一致 bug
6. **NLU 关键词** 重整 (咖啡->餐饮 / 电影->娱乐 / 健身->运动 / 股票->投资)

**验证**: 174/174 tests (含 10 个 v5->v6 迁移测试), analyze 0 errors, 2 张截图 docs/screenshots/v1.10.0/

## 2.8 v1.9.0 增量 (记一笔界面重设计)

**用户需求**: 金额移到键盘圆圈位置 / 分类 2/3 + 键盘 1/3 / 标签增强

**改动**:
1. **金额显示屏** 移到键盘顶部 (28pt 大字 + ¥ 前缀, 替代顶部行的小字预览)
2. **分类区** `Expanded(flex: 2)` 占 2/3 (原 234px 固定), 22 分类全部可滚动
3. **键盘** `Expanded(flex: 1)` 占 1/3 (原 Expanded 占满剩余)
4. **标签行** 增强: 高 32→40, 彩色 chip 背景, 字号 12→13, 频次胶囊, SingleChildScrollView

**验证**: 161/161 tests, analyze 0 errors, 2 张截图 `docs/screenshots/v1.9.0/`

## 2.7 v1.8.1 增量 (2 个 Bug 修复)

**Bug 1 — 回退键在记帐页退出应用**
- 根因: `RootShell` 在同一路由内换页, 无路由可 pop → 系统回退直接退出
- 修复: RootShell 加 `PopScope` — 非首页时拦截回退 → 回首页; 首页才允许退出

**Bug 2 — 日期选择需点"确定", 步骤多**
- 新增 `lib/widgets/date_picker_dialog.dart` 自定义日期对话框
- **双击某天 = 确定** (或再点一次已选中那天); 单击 = 选中; 保留"确定"/"取消" + "今天"快捷 chip
- 替换 3 处系统 `showDatePicker`: 记一笔选日期 / 首页日历 / 首页选月份

**验证**:
- 161/161 tests pass (10 新)
- analyze 0 errors
- 3 屏模拟器截图: `D:\DSH\Account\docs\screenshots\v1.8.1\`

## 3. 构建产物

| 类型 | 路径 | 大小 |
|---|---|---|
| **Release APK** | `build/app/outputs/flutter-apk/app-release.apk` | 54.91 MB (v1.6.4) |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` | 192 MB |
| 入口 | `lib/main.dart` | |

## 4. 模拟器/真机安装

```bash
# Release (推荐, 已 AOT 编译)
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk

# Debug (含调试信息, 体积大)
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-debug.apk
```

## 5. 启动 App

```bash
adb shell am start -n com.lemonledger.lemon_ledger/com.lemonledger.lemon_ledger.MainActivity
```

或: `adb shell am start -n com.lemonledger.lemon_ledger/.MainActivity`

## 6. 功能完成度 (v1.6.4)

### 6.1 已实现 (5 屏 + 全核心)

- [x] **明细**: 黄色 header 月汇总 + 5 入口 (账单/预算/资产/返现/更多) + 18 笔种子流水 (10-05~10-09)
- [x] **图表**: 周/月/年 + 折线图修复 (v1.5.1 修复 Y 轴单位 bug) + 9 分类排行榜
- [x] **记帐**:
  - 类型切换 (支出/收入)
  - **常用分类** (4 个 pinned: 餐饮/交通/零食/信用卡)
  - **全部分类网格** (14 支出 / 5 收入)
  - **数字键盘** (123456789 自底向上 + ×−+, = = 保存)
  - **实时求值** (输 `1+2+` 显示 `3+`)
  - **= 合并保存** (按 = 完成录一笔, 跳回首页)
  - 备注 + 标签 + 语音 (长按 .)
- [x] **发现**: 4 个占位卡片
- [x] **我的**: 分类管理 / 数据备份 (JSON) / 数据恢复 (JSON) / 导出 CSV / 导出 Excel / 关于 v1.6.4 / **重置数据 二次确认** (输"确认"解锁)
- [x] **错误页** (v1.5 E1): 替换 Flutter 默认红屏/黑屏, 友好错误 + 重试 + stacktrace
- [x] **主题/字号** (v1.6 S1): light/dark + 3 档字号, 跨屏共享 (Riverpod)

### 6.2 不做 (v1.6 范围内)

- [ ] 云同步 (v1.3 占位) — 用户没要求
- [ ] 预算/理财社区/资产管理/购物返现 (发现页占位) — 后续版本
- [ ] 深色模式 — 跟随系统
- [ ] 多账本/多币种 — v2.0+

## 7. 测试 (127/127 通过)

```
flutter test                                       # 全量
flutter test test/widget_test.dart                 # 业务 + 模型
flutter test test/golden_test.dart                 # 真实 sqflite + 查询
flutter test test/ui_test.dart                     # 端到端 widget tree
flutter test test/home_save_flow_test.dart         # 录一笔流程
flutter test test/mine_reset_test.dart             # 重置数据
flutter test test/import_json_test.dart            # 数据导入/恢复
flutter test test/calculator_test.dart             # 计算器
flutter test test/chart_compare_test.dart          # 图表环比
flutter test test/chart_line_y_unit_test.dart      # 折线单位 (hotfix)
flutter test test/error_screen_test.dart           # 错误页
flutter test test/day_keys_test.dart                # 首页 GlobalKey
flutter test test/find_nearest_day_test.dart        # 最近日
flutter test test/month_picker_test.dart            # 月份选择
flutter test test/nlu_test.dart                     # 语音 NL 解析
```

### 7.1 关键测试数据 (种子)

- 总支出 ¥2,281.00, 总收入 ¥50.00
- 7 日点值: 1045/152/97/53/934/0/0 (10-05 ~ 10-11)
- 9 分类: 投资 818/日用 590/交通 476/餐饮 136/孩子 99/旅行 80/医疗 55/咖啡 7/停车费 20
- 9 分类占比合计 100.0%
- 27 分类 (19 支出 + 8 收入)
- 18 笔种子流水

## 8. 项目目录 (v1.6)

```
app/
├── lib/
│   ├── main.dart                       # ProviderScope + ErrorWidget 替换
│   ├── providers/
│   │   └── theme_provider.dart         # 跨屏主题 (Riverpod)
│   ├── data/
│   │   ├── models.dart                 # Tx, Category (含 pinned), Budget, Tag
│   │   ├── seed.dart                   # 27 分类 + 18 种子
│   │   ├── database.dart               # v4 schema (加 pinned)
│   │   ├── repository.dart             # CRUD + 统计
│   │   ├── settings_service.dart       # 主题/字号
│   │   ├── budget_service.dart
│   │   └── tag_service.dart
│   ├── services/
│   │   ├── backup.dart                 # JSON 导入/导出
│   │   ├── nlu_service.dart            # 语音解析
│   │   └── voice_service.dart          # 语音 STT
│   ├── theme/
│   │   └── tokens.dart                 # 12 design tokens
│   ├── widgets/                        # 14 个 widget
│   │   ├── error_screen.dart           # E1 错误页
│   │   ├── icons.dart                  # 27 分类色板
│   │   ├── category_icon.dart
│   │   ├── segment.dart                # 周/月/年
│   │   ├── top_tab_bar.dart            # 5 tab
│   │   ├── entry_header.dart           # 记帐页 × 标题
│   │   ├── entry_amount_panel.dart
│   │   ├── entry_category_grid.dart    # 旧版 19 分类
│   │   ├── entry_pinned_categories.dart # 鲨鱼 4 常用
│   │   ├── entry_split_categories.dart # U1.5 左右分栏
│   │   ├── entry_tag_bar.dart
│   │   ├── entry_note_bar.dart
│   │   ├── entry_short_note.dart       # U1.5 单行备注
│   │   ├── entry_bottom_action_bar.dart
│   │   └── entry_keypad.dart           # 4×4 数字键盘
│   ├── screens/
│   │   ├── home_page.dart
│   │   ├── chart_page.dart
│   │   ├── entry_page.dart             # 458 行
│   │   ├── discover_page.dart
│   │   ├── mine_page.dart
│   │   └── import_data_dialog.dart     # 数据恢复对话框
│   ├── utils/
│   │   ├── calculator.dart            # 表达式求值
│   │   └── date_utils.dart
│   └── screens/...
├── test/                               # 13 个测试文件, 127 个测试
├── android/                            # Android 原生
├── ios/                                # iOS 原生 (未配置)
├── pubspec.yaml                        # 1.6.4+24
└── VERSION.md                          # 完整版本历史
```

## 9. 关键设计亮点

- **业务口径**: 平均 = 周期总额 / **已过天数** (而非周期总天数)
- **金额精度**: `Long` 分 (cents), 全流程无浮点
- **日期精度**: `epochDay` (自 1970-01-01 起的天数), 无时区漂移
- **设计 token**: 12 个 token (颜色 + 间距 + 圆角) 从参考图实测
- **bottomNavigationBar**: 56px 固定高, 防止 body 高度为 0 (v1.0 修过)
- **v1.6.4 数字键盘**: `Expanded` 弹性填满, 永远不被 tab 遮挡
- **错误页** (v1.5 E1): `ErrorWidget.builder` 全局替换 + `installGlobalErrorHandlers` 捕获异步
- **主题/字号** (v1.6 S1): Riverpod Notifier 跨屏共享

## 10. 模拟器 e2e 验证 (v1.6.4)

5 张截图: `D:\07.DevWorkspace\sys\final-0[1-5]-*.png`
- 01 首页 / 02 图表 / 03 记帐 (核心) / 04 发现 / 05 我的

## 11. 安装到真机

```bash
# 1. USB 连接手机, 开启 USB 调试
# 2. 验证
adb devices
# 3. 安装 v1.6.4
adb install -r D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk
# 4. 启动
adb shell am start -n com.lemonledger.lemon_ledger/com.lemonledger.lemon_ledger.MainActivity
```

完整安装文档: [`INSTALL.md`](INSTALL.md)
完整功能说明书: [`../docs/FEATURE-v1.6.md`](../docs/FEATURE-v1.6.md)
版本历史: [`VERSION.md`](VERSION.md)
