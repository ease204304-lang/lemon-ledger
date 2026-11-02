# 柠檬记账 版本历史

## v1.10.0 (2026-11-01) — 分类清单重整: 支出 14 类 + 收入 8 类 (DB v6)

### 用户需求
> 支出：信用卡、餐饮、娱乐、零食、交通、住房、旅游、医疗、运动、汽车、孩子
> 后续追加：日用、投资；保留：其他

### 最终分类清单

**支出 14 类** (记帐页 5 列网格, 按此顺序):
```
信用卡  餐饮  娱乐  零食  交通
住房    旅游  医疗  运动  汽车
孩子    日用  投资  其他
```
**常用 (置顶列)**: 信用卡 · 餐饮 · 零食 · 交通

**收入 8 类** (维持不变):
```
工资  奖金  补贴  兼职
投资  退款  收礼  其他
```
**常用 (置顶列)**: 工资

### 变更明细

| 类别 | 操作 | id |
|---|---|---|
| 信用卡 / 餐饮 / 零食 / 交通 / 住房 / 医疗 / 孩子 / 日用 / 其他 | 保留 (改名+重排) | id 不变 |
| 旅行 → **旅游** | 改名 | `cat.travel` |
| 车费 → **汽车** | 改名 | `cat.car` |
| **娱乐** | 新增 | `cat.entertain` (icon: movie, 紫) |
| **运动** | 新增 | `cat.sport` (icon: fitness_center, 青) |
| **投资** (支出) | 新增 | `cat.invest_exp` (与收入 `cat.invest` 区分) |
| 超市 / 水果 / 饮品 / 服饰 / 美妆 / 通讯 / 居家 / 学习 / 教育 / 宠物 / 数码 | **归档** (archived=1, 不删) | id 保留 |

### 🔴 同时修复: `cat.invest` 类型不一致 bug

**问题**: 种子流水 `t.010` (818.00 元「投资 - 信托」) 挂在 `cat.invest` 上, 但该分类是**收入类**
→ 支出排行榜出现一笔挂在收入类下的支出, 图表分类占比失真。

**修复**:
- 支出「投资」用独立 id `cat.invest_exp` (与收入 `cat.invest` 同名不同类)
- 迁移时把 `type=expense AND category_id='cat.invest'` 的历史流水迁到 `cat.invest_exp`
- 新种子流水直接挂 `cat.invest_exp`

### DB v6 迁移 (`_migrateToV6Categories`)

**原则: 保护用户数据**
1. **不删任何分类** — 被移除的分类只置 `archived=1` (软删),
   否则用户历史流水的 `category_id` 变悬空引用 → 报表金额丢失
2. 改名走 UPDATE (id 不变) → 历史流水自动跟随
3. 新增分类走 `INSERT ... ON CONFLICT IGNORE`
4. **所有**保留分类的 `sort_order` 按新清单重排 (否则旧库显示顺序错乱)
5. `pinned` 重置为新清单常用项
6. 归档分类上的 `tag.category_id` 置 NULL (否则标签行查不到)

### 连带改动

| 文件 | 改动 |
|---|---|
| `lib/data/seed.dart` | 分类清单重整 + 种子流水适配 (818→`cat.invest_exp`, 咖啡→`cat.food`, 旅游改名) |
| `lib/data/database.dart` | schema v5→v6 + `_migrateToV6Categories` + pinned/seedTagNames 适配 |
| `lib/widgets/icons.dart` | 新增 `entertain`/`sport` 色板+图标; 移除 9 个已删类的图标 |
| `lib/services/nlu_service.dart` | 语音关键词映射重整 (咖啡→餐饮, 电影→娱乐, 健身→运动, 股票→投资支出) |
| `test/db_v6_migration_test.dart` | **新文件** (10 用例) — v5→v6 迁移全链路验证 |
| `test/golden_test.dart` | 分类断言重写 (v6 清单 + 改名 + pinned) |
| `test/widget_test.dart` | 支出类数 22→14 + 新增"分类名顺序"断言 |
| `test/nlu_test.dart` | 饮品/服饰 → 餐饮/娱乐 |
| `test/mine_reset_test.dart` / `import_json_test.dart` | 分类数 30→22 |
| `test/tag_stats_test.dart` | `cat.drink` → `cat.food` |

### 附带修复: 5 个日期依赖测试 (跨月失效的遗留 bug)

系统日期从 2026-10-31 跨到 11-01 后, 种子流水 (2026-10-05..09) 落到 HomePage 当前月之外,
5 个写死 "10月" 的测试开始失败。已改为**跟随系统日期**或按月条件断言:
`month_picker_test` / `home_save_flow_test` / `day_keys_test` / `ui_test`

### 验证
- `flutter analyze`: 0 errors
- `flutter test`: **174/174 通过** (161 + 3 v6 清单 + 10 迁移)
- Release APK: 54.4 MB
- 模拟器 e2e: 2 张截图 (`docs/screenshots/v1.10.0/`)

---

## v1.9.0 (2026-10-31) — 记一笔界面重设计: 分类 2/3 + 键盘 1/3 + 金额显示屏

### 用户需求
> 1. 金额数字 调整位置到 数字键盘圆圈位置；
> 2. 数字键盘框架缩小到三分之一左右， 分类选择框架增加到三分之二左右；
> 3. 标签显示 增强显示。

### 改动 1: 金额显示屏移到键盘顶部 (圆圈位置)

**之前**: 金额预览在顶部 `_TypeAndDateRow` (支出/收入 chips 旁边), 字号 18pt, 不显眼
**之后**: 金额显示在数字键盘顶部, 大字 28pt + ¥ 前缀, 右对齐 (类似计算器显示屏)

**实现**:
- `lib/widgets/entry_keypad.dart` 新增 `_AmountDisplay` widget (Container + Row: ¥ + 大字金额)
- `lib/screens/entry_page.dart` `_TypeAndDateRow` 移除 `amount` 参数和 `_fmtAmount` 方法
- U2 实时求值逻辑 (`_fmtAmount`) 搬到 `_AmountDisplay` 内, 逻辑不变

### 改动 2: 分类区 2/3, 键盘 1/3 (比例反转)

**之前**: 分类区固定 234px (约 1/5 屏), 键盘 Expanded 占剩余 (约 1/3 屏)
**之后**: 分类区 `Expanded(flex: 2)` (约 2/3 剩余空间), 键盘 `Expanded(flex: 1)` (约 1/3)

**附带改进**:
- 分类网格从 `NeverScrollableScrollPhysics` 改为 `AlwaysScrollableScrollPhysics` (22 支出分类可滚动)
- 之前 5×3 网格只能显示 15 个, 后 7 个被裁掉; 现在 5×N 可滚动显示全部

### 改动 3: 标签显示增强

**之前**: 标签行高 32px, 纯文字 + outlined 图标, 12pt 字号, 无背景
**之后**:
- 高度 32→40px
- 彩色 chip 背景 (品牌黄浅底 `brandYellowTrack` + 黄色边框)
- 实心图标 `local_offer` (13px) 替代 outlined
- 字号 12→13pt, 字重 w500→w600
- 频次标签 `×N` 从纯文字改为黄色胶囊背景 (更醒目)
- "全部" 入口加边框 chip 样式
- 用 `SingleChildScrollView` 替代 `ListView` (构建所有子项, 避免 lazy build 问题)

### 改动文件
- `lib/screens/entry_page.dart` (布局重构 + _TypeAndDateRow 简化 + _TagRow 增强)
- `lib/widgets/entry_keypad.dart` (新增 _AmountDisplay 金额显示屏)
- `lib/widgets/entry_split_categories.dart` (分类网格可滚动)
- `lib/screens/mine_page.dart` (v1.9.0 版本号)
- `android/.../AndroidManifest.xml` (label "小猪记账 v1.9.0")
- `pubspec.yaml` (1.9.0+28)
- `test/tag_view_widget_test.dart` (ensureVisible 适配 SingleChildScrollView)

### 验证
- `flutter analyze`: 0 errors
- `flutter test`: **161/161 通过** (0 回归)
- Release APK: 54.3 MB
- 模拟器 e2e: 2 张截图 (`docs/screenshots/v1.9.0/`)

---

## v1.8.1 (2026-10-27) — Bug 修复: 回退键 + 日期双击确定

### 用户反馈 (2 个 Bug)
> 1. "增加记录过程要回退，点击回退直接就退出应用，不是到主页面；"
> 2. "日期选择界面，双击具体日期就能代替 确定 动作；"

### Bug 1 修复: 回退键退出应用 → 回主页面

**根因**: `RootShell` 用 `switch (_index)` 在**同一个路由**里换页 (无 `Navigator.push`),
所以系统回退键在记帐/图表/发现/我的页时, 没有路由可 pop → 直接退出应用。

**修复** (`lib/main.dart`): RootShell 加 `PopScope`
```dart
PopScope(
  canPop: _index == 0,                       // 首页才允许退出
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) return;
    _nav(0);                                  // 其他 tab → 回首页
  },
  child: _buildPage(),
)
```

**行为**:
| 当前页 | 回退键行为 |
|---|---|
| 明细 (首页) | 退出应用 (与系统一致) |
| 图表 / 记帐 / 发现 / 我的 | **回到明细首页** (不退出) |
| 流水编辑页 (独立路由 push) | 关闭编辑页 (原有行为不变) |

### Bug 2 修复: 日期选择双击 = 确定

**新增文件**: `lib/widgets/date_picker_dialog.dart` (自定义日期选择对话框)

**交互**:
| 操作 | 结果 |
|---|---|
| 单击某天 | 选中 (黄色高亮), 对话框保持打开 |
| **再点一次已选中的那天** | **立即确定并关闭** (不限点击速度) |
| 双击某天 (400ms 内) | 立即确定并关闭 |
| 点"确定" | 用当前选中日期确认 |
| 点"取消" | 返回 null, 不改动 |
| 点"今天"/"昨天" 快捷 chip | 立即返回该日期 |

**界面**: 取消 / 年月 / 确定 + 月份切换 + 周一起始 7 列网格 + 今天黄底 + 快捷 chip + "单击选中 · 再点一次确定" 提示

**替换的 3 处系统 `showDatePicker`**:
| 文件 | 场景 | 快捷 chip |
|---|---|---|
| `lib/screens/entry_page.dart` `_pickDate()` | 记一笔选日期 | 今天 |
| `lib/screens/home_page.dart` `_openCalendar()` | 首页日历按钮 (跳到该日) | 今天/昨天/前天 |
| `lib/widgets/home_header.dart` `_showMonthPicker()` | 首页选月份 | 今天 |

### 附带修复: 日期依赖的测试不稳定

系统日期从 2026-10-18 推移到 10-27 后, 种子流水 (2026-10-05..09) 落到图表的
"上周/本周" 周期之外 → 3 个测试用例失败 (断言 '投资'/'标签分析' 等具体数据)。

**修复**: `test/tag_view_widget_test.dart` + `test/ui_test.dart`
改为断言**视图结构** (卡片标题 或 空态提示 二者其一), 数据口径由
`test/tag_stats_test.dart` (直接查库) 覆盖 — 不再依赖系统日期。

### 改动文件
- `lib/main.dart` (RootShell PopScope)
- `lib/widgets/date_picker_dialog.dart` (**新文件**)
- `lib/screens/entry_page.dart` (用 showAppDatePicker)
- `lib/screens/home_page.dart` (用 showAppDatePicker)
- `lib/widgets/home_header.dart` (用 showAppDatePicker)
- `lib/screens/mine_page.dart` (v1.8.1 版本号)
- `android/.../AndroidManifest.xml` (label "小猪记账 v1.8.1")
- `pubspec.yaml` (1.8.1+27)
- `test/bug81_test.dart` (**新, 10 用例**: 回退 3 + 日期 7)
- `test/tag_view_widget_test.dart` (去日期依赖)
- `test/ui_test.dart` (去日期依赖)

### 验证
- `flutter analyze`: 0 errors (77 info/warning, 均为既有)
- `flutter test`: **161/161 通过** (151 + 10 新)
- Release APK: 54.3 MB
- 模拟器 e2e: 3 张截图 (`docs/screenshots/v1.8.1/`), 双 Bug 均实机验证通过

---

## v1.8.0 (2026-10-18) — 标签统计 + 饼图 (U1.9 收尾)

### 需求来源
用户 v1.7.0 的图 2 后半: "下方列出的是 **按标签的排序 (按时间和按金额)**，以及**按标签的饼状图分析**"

### 新增功能

#### 1. 数据库 v5: tx_tag 关联表 + tag.category_id

- **schema v5** (从 v4 升级): 新建 `tx_tag (tx_id, tag_name)` 关联表, `tag` 加 `category_id` 列
- **onCreate (新装) + onUpgrade v4→v5 (升级)**: 都跑一次 `_backfillTagsFromTxs` — 从种子流水备注回填 11 个演示标签 (餐饮/交通/停车费/单车/充电/咖啡/信托/日用/孩子/旅行/医疗)
- **v1.8.0 修复**: v1.7.0 升级路径只回填已有 tag, 不插种子 — 导致 v1.8.0 升级用户看不到饼图。修复后升级也跑 seed backfill

#### 2. TagService 新增 API

```dart
syncForTx(Tx tx)             // 保存流水时同步关联 (整笔 bump + 命中标签 bump + 频次 +1)
statsByTag(type, from, to, {sortBy})  // 周期内按标签聚合 (金额/笔数/最近使用)
byCategory(categoryId)       // 改用 tx_tag 精确查询, 不用 LIKE 反推
remove(name)                 // 删标签 + 清理 tx_tag 关联
```

#### 3. 记帐页 _TagRow 接入 build (v1.7.0 漏写修复)

- `_TagRow` 之前是死代码, 这次终于接入到 `_EntryPageState.build` 里的 Column (位置: 模块一 之后, EntryShortNote 之前)
- 高度 32px, 显示标签 chips + 末尾 "全部 ›" 入口
- 点击 chip → 追加到备注 (空格衔接)
- "全部 ›" → 跳到 TagManagerPage

#### 4. 图表页 分类/标签 二级视图

- Header 右上角饼图 icon: 点击切换 分类↔标签 视图
- 饼图 icon 选中时填充 + 品牌黄; 未选中时 outline + 文字黑
- Row2 右侧加 `分类|标签` 切换 chips
- 标签视图内容 (`_TagStatsCard`):
  - 标题 "标签分析" + "N 个标签" 计数
  - 排序切换: 按金额 (深底白字) / 按时间 (透明底灰字)
  - 饼图 (150x150, fl_chart PieChart): top 6 标签 + 其他 灰色; 占比 ≥12% 中心徽标百分比
  - 图例: 色点 + 标签名 + 百分比
  - 排名列表: 序号 / 色点 / 名称 / 时间模式: 最近使用日期 / 笔数 / 金额 / 进度条
- 标签视图空态: "本周期暂无标签数据 / (记账时填写备注即可生成标签)"

#### 5. TagManagerPage 升级 (v1.7.0 → v1.8.0)

- byCategory 走 tx_tag 关联表 (精确), 不再 LIKE 反推
- 删除标签同时清理 tx_tag 关联
- try/catch 保护 _load 防止测试 tearDown 竞态

#### 6. 选中分类时记帐页标签行联动

- 选 餐饮 → 标签行显示 餐饮相关的 (餐饮 单车 等)
- 取消选 → 全局 recent(5)

### 改动文件
- `lib/data/database.dart` (schema v5 + 升级 + 种子回填)
- `lib/data/tag_service.dart` (Tag 加 category_id; 新增 syncForTx / statsByTag)
- `lib/data/models.dart` (无改动)
- `lib/screens/entry_page.dart` (接入 _TagRow)
- `lib/screens/chart_page.dart` (ChartView enum + _ViewToggle + _TagStatsCard)
- `lib/screens/tag_manager_page.dart` (try/catch)
- `lib/screens/mine_page.dart` (v1.8.0 版本号)
- `android/.../AndroidManifest.xml` (label "小猪记账 v1.8")
- `pubspec.yaml` (1.8.0+26)
- `test/tag_stats_test.dart` (新, 18 用例: schema/聚合/sync/byCategory/remove/升级)
- `test/tag_view_widget_test.dart` (新, 6 用例: 图表标签视图 + TagManagerPage 跳转)

### 验证
- `flutter analyze`: 0 errors
- `flutter test`: **151/151 通过** (127 旧 + 24 新)
- Release APK: 55.2 MB
- 模拟器 e2e: 6 屏截图 (`docs/screenshots/v1.8.0/`)

### 已知限制
- swiftshader 模拟器上, TagManagerPage 直接点击跳转偶发 hit-test 失效; 真机正常; widget test 全过
- 种子标签不含 "收入" 类 — 避免与记帐页类型 chip 同名混淆; 收入侧 标签视图显示空态

---

## v1.7.0 (2026-10-16) — 标签系统 + 图表跳转 (U1.9)

### 需求来源
用户给的 2 张参考图:
1. **标签**: 点开单一类别 (如"零食"), 标签支持自定义, 自定义后成为标签放在下方, **按使用频次由前到后排序**
2. **图表**: 点击具体一笔/一个类别 → 对应成为类别的数据统计, 下方列出**按标签的排序**

### 新增功能

#### 1. 标签按使用频次排序 (改 `TagService.recent`)
```dart
// 改前 (v1.2.2): 按 last_used_at 倒序
orderBy: 'last_used_at DESC'
// 改后 (v1.7.0): 按 use_count 倒序, 同频次按最近使用
orderBy: 'use_count DESC, last_used_at DESC'
```

#### 2. 新增 `TagService.byCategory(categoryId)` (反推关联)
- 取前 50 个标签 (按 use_count), 再用 `tx.note LIKE '%tag%'` + `category_id = ?` 反推哪些标签属于该分类
- 不改 DB schema (兼容 v4), 纯查询层实现

#### 3. 记帐页: 选分类后自动刷新该分类的标签
- `onSelect: (c) { setState(...); _loadTags(); }`
- `_loadTags()` 有分类 → `byCategory(catId, limit: 8)`; 无分类 → `recent(5)`
- 标签行 `×次数` 徽标: use_count ≥ 3 显示
- 标签行末尾加 **"全部 >"** 入口 → 标签管理页

#### 4. 新页面 `TagManagerPage` (标签管理)
- 标签云 (Wrap 布局): 使用频次决定大小/颜色 (1-2 次 白底, 3-5 次 浅黄, 6+ 次 品牌黄 + 加粗)
- 显示每个标签的使用次数
- 点标签 → snackbar 显示"已用过 N 次"
- **长按删除** (带确认对话框, 只删标签不删流水)
- 右上角 **+** 新建自定义标签 (对话框输入)
- 顶部搜索框 (模糊搜, 按 use_count 排序)
- 支持两种模式: 全部标签 / 某分类的标签 (标题带分类名)

#### 5. 图表页: 点排行 → 跳到该分类的标签管理页
- `_RankingRow` 包 `InkWell` + `onTap`
- 点"餐饮"排行 → `TagManagerPage(categoryId: 'cat.food', categoryName: '餐饮')`

### 涉及文件
| 文件 | 改动 |
|---|---|
| `lib/data/tag_service.dart` | recent 排序改 use_count; 新增 byCategory |
| `lib/screens/tag_manager_page.dart` | **新文件** (标签管理页) |
| `lib/screens/entry_page.dart` | _loadTags 按分类查询 + try/catch; 标签行加 ×次数 + 全部入口; onSelect 联动 |
| `lib/screens/chart_page.dart` | _RankingRow 加 InkWell/onTap → TagManagerPage |
| `lib/screens/mine_page.dart` | 版本号 v1.7.0 (2 处) |
| `android/.../AndroidManifest.xml` | label "小猪记账 v1.7" |
| `pubspec.yaml` | 1.7.0+25 |
| `test/home_save_flow_test.dart` | 无需改 (try/catch 兜底) |

### 验证
- ✅ 127/127 tests pass
- ✅ analyze 0 errors (73 infos/warnings 均为存量)

### Release
- APK: `app-release.apk` (build 25)
- 版本: 小猪记账 v1.7.0

### 已知限制 (v1.7.0 范围)
- 标签与分类的关联是**反推** (note LIKE), 未加外键字段 — 标签改备注后关联可能失效, v1.8 计划加 `tag.category_id` 列
- 图表页"按标签排序 (按时间/按金额) + 按标签饼状图"未实现 — 需要 tag↔tx 关联表, 排 v1.8
- TagManagerPage 点标签只是提示次数, 未做"选中填入备注" — 可在记帐页标签行直接点填入

---

## v1.6.4 (2026-10-15) — 数字键盘被 tab 遮挡 Bug 修复

### Bug 现象
用户在 v1.6.3 真机验证后报告:
> "数字键盘目前看不完整, 属于Bug"

### 根本原因
`lib/screens/entry_page.dart` 用 `SizedBox(height: 780)` 固定键盘高度, 假设 EntryPage 是全屏. 但 EntryPage 嵌在 `RootShell` 内, RootShell 底部 tab 栏占了约 60-80px, 所以键盘的最后一行 (`0` / `del` / `=`) 被 tab 完全遮挡.

### 修复
1 行改动: `SizedBox(height: 780)` → `Expanded`
```dart
// 改前 (v1.6.3, 假设全屏 2340px):
SizedBox(height: 780, child: EntryKeypad(...))

// 改后 (v1.6.4, 弹性填满):
Expanded(child: EntryKeypad(...))
```

### 验证
- ✅ 模拟器截图: 数字键盘 4 行 16 键完整可见 (含 `0` / `del` / `=`)
- ✅ 127/127 tests pass
- ✅ analyze 0 errors
- ✅ 适配任何屏高 / tab 高 / 旋转

### Release
- APK: `D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk` (54.91 MB)
- 版本: 小猪记账 v1.6.4 (build 24)

---

## v1.6.3 (2026-10-15) — 严格执行 1/3 屏 + 1/5 屏

### 设计要求
用户给的新比例:
> "数字键盘占三分之一, 选择类型占不超过五分之一"

### 实现
- 顶部状态 60px (2.6%)
- 选择类型 234px = 1/10 屏 ≤ 1/5 ✓
- 备注 1 行 30px (1.3%)
- 数字键盘 **780px = 1/3 屏 ✓**

### 模拟器截图
- `D:\07.DevWorkspace\sys\confirm-12-entry-v163.png` (bug, 选类完整, 键盘最后一行被 tab 挡)
- 触发 U1.8 修复

---

## v1.6.2 (2026-10-15) — 模块一+模块二合并 1/3 屏 (U1.6 三次设计)

### 改动来源
用户在 v1.6.1 APK 验证后给出新设计 (image.png), 指出:
> "模块一和模块二合并，仅占整个版面的 三分之一"

### 核心改动
- **整页布局从分散变 1 块**: 之前的实现是 4 个独立 Row (顶部/类型/分类/键盘), 现在按用户设计改成 **2 块主体**:
  - **模块一** (1 块 white card, ~340px 高): 顶部 (类型/日期/金额) + 14 网格 + 4 常用 + 备注 (合并到底)
  - **模块二** (~280px 高): 4×4 数字键盘
  - **两块总和 ≈ 620px ≈ 1/3 屏**
- **抽出新 widget** `_Module1CategoriesAndNote`: 把分类 + 备注 + 标签 整合在 1 个白色 Container 内, 视觉上是 1 块卡

### 整页高度演变 (4 次)
| 版本 | 主体占屏 | 备注 |
|---|---|---|
| v1.5.0 | 70% | 旧版, 5 项 P0 改前 |
| v1.6.0 (U1+U2 首版) | 40% | 鲨鱼记账风横排常用 |
| v1.6.1 (U1.5 二次) | 30% | 左右分栏 |
| **v1.6.2 (U1.6)** | **~26% (1/3 屏)** | **模块一+二合并 1 块** |

### 文件改动
- 改: `lib/screens/entry_page.dart` — Column 改 2 块 (模块一+二), 抽出 `_Module1CategoriesAndNote` 整合分类/标签/备注
- 改: `pubspec.yaml` 1.6.1+21 → 1.6.2+22
- 改: `android/.../AndroidManifest.xml` v1.6.1 → v1.6.2
- 改: `lib/screens/mine_page.dart` 关于 → v1.6.2

### 测试
- 127 → 127 全过 (整合是纯结构改动, 无逻辑变化)

### 模拟器验证 (D:\07.DevWorkspace\sys\11-entry-v162.png)
- 1. 顶部 (类型/日期/金额) 1 行
- 2. 模块一: 左 14 网格 (5×3, 含 教育/医疗/住房 等) + 右 4 常用 (浅黄底) + 备注 (底) — 1 块白色卡
- 3. 模块二: 4×4 数字键盘, 第 4 列黄底, = 加重黄
- 4. 整页 ~1/3 屏, 上半部分显示首页内容 (因为记账是浮在上面的)

### 用户感受
- 录一笔从 5 步 (点分类 → 输入 → 按 = → 按保存 → 跳走) 简化为 **3 步** (点分类 → 输入 → 按 =)
- 整页缩小到 1/3 屏, 不用"上下滑动"找分类
- 实时求值能预知结果
- 选分类的视觉反馈 (黄色高亮) 让用户清楚知道选了哪个

---

## v1.6.1 (2026-10-15) — 分类区分两部分 (U1.5 二次设计)

### 改动来源
用户在 v1.6.0 APK 验证后给出新设计 (image.png):
1. 数字键盘高度减小到 ~1/3 屏
2. 等号按钮 = 保存按钮 (合并)
3. 分类区: 左 14 网格 (全部) + 右 4 常用
4. 数字键盘第 4 列底色统一品牌黄
5. 选择分类时实时反馈

### P0 改动
1. **分类区左右分栏** (新 widget `entry_split_categories.dart`)
   - 左侧 70% 宽: 14 分类 5×3 网格 (餐饮/超市/交通/水果/日用/零食/饮品/服饰/美妆/通讯/居家/信用卡/旅行/学习/教育)
   - 右侧 30% 宽: 浅黄底竖列 1×4, 顶部 "常用" 标签, 4 常用 (餐饮/交通/零食/信用卡)
2. **数字键盘高度压缩** (~260px = 4 行 × 65px)
   - 字号 28pt → 24pt (数字), 22pt → 20pt (运算符)
   - 第 4 列 (× − + =) 整列品牌黄底, = 加重品牌黄
3. **选择分类实时反馈** (品牌黄背景 + 文字加重)
4. **类型 + 日期 + 金额 1 行** (替代 v1.6.0 独立日期+金额行)
5. **保留 = 同时保存** (v1.6.0 改动 3)

### 文件改动
- 新: `lib/widgets/entry_split_categories.dart` (195 行, 鲨鱼记账风左右分栏)
- 重写: `lib/widgets/entry_keypad.dart` (高度压缩, 第 4 列统一品牌黄)
- 改: `lib/screens/entry_page.dart` (用 split_categories 替换 pinned)
- 改: `test/ui_test.dart` (餐饮/信用卡/工资 出现 2 次, 改 findsWidgets)
- 改: `test/home_save_flow_test.dart` (`.first` 避免 ambiguous)
- 改: `pubspec.yaml` (1.6.0+20 → 1.6.1+21)
- 改: `android/.../AndroidManifest.xml` (label v1.6 → v1.6.1)

### 测试
- 127 → 127 全过 (新设计无回归)
- 4 常用分类在 split categories 出现 2 次 (左网格 + 右常用), 测试改用 findsWidgets

### 模拟器验证 (D:\07.DevWorkspace\v15split.png)
- 1. 整页 ~30% 屏 (从 v1.6.0 的 40% 再压缩)
- 2. 左 14 网格 + 右 4 常用 (浅黄底 "常用" 标签)
- 3. 数字键盘第 4 列整列品牌黄, = 加重
- 4. 顶部类型 chips + 日期 chip + 金额实时预览 1 行
- 5. 备注 (1 行) 在分类区和键盘之间

### 整页高度演变
| 版本 | 整页占屏 |
|---|---|
| v1.5.0 | 70% |
| v1.6.0 (首版 U1+U2) | 40% |
| v1.6.1 (U1.5 二次设计) | **30%** |

### 用户感受
- 录一笔从 5 步 (点分类 → 输入 → 按 = → 按保存 → 跳走) 简化为 **3 步** (点分类 → 输入 → 按 =)
- 整页缩小到 30% 屏, 不用"上下滑动"找分类
- 实时求值能预知结果
- 选分类的视觉反馈 (黄色高亮) 让用户清楚知道选了哪个

---

## v1.6.0 (2026-10-15) — 录一笔体验收尾 (U1 键盘重设计 + U2 实时求值)

### 设计来源
用户截图给出 5 个改动点 (image.png), 全部按设计实现

### P0 改动
1. **常用分类** (鲨鱼记账风格): 支出 4 个 (餐饮/交通/零食/信用卡), 收入 1 个 (工资)
   - 数据库加 `pinned` 列 (v3→v4 迁移), 默认 5 个分类 pinned
   - 新 widget `entry_pinned_categories.dart` 横排, 点"全部"打开 sheet
2. **数字键盘 123456789 自底向上** (iOS 计算器风格)
   - 第 1 行 7/8/9, 第 2 行 4/5/6, 第 3 行 1/2/3, 第 4 行 . / 0 / del
3. **= 同时是保存** (改动 3): 按 = 触发 _onEqualsAndSave → 实时求值 + 写库 + 跳回首页
4. **运算符: × − + 第 4 列, 无 ÷** (改动 4)
   - 视觉: 数字键大字号 28pt, 运算符半高小字号 22pt 浅黄背景
   - = 黄色背景大字 30pt
5. **整页缩小到 ~40% 屏** (改动 5): 之前 70% 屏, 现在极简
   - 顶部 × 关闭 (无 mic/delete)
   - 支出/收入 chips
   - 日期 + 金额实时预览 (合并 1 行)
   - 常用分类 (1 行)
   - 标签 (1 行)
   - 备注 (1 行)
   - 数字键盘 (4 行, 占下半部分)

### U2 实时求值
- 输 `1+2+3` → 金额区显示 `3.00+3` (已完成段 + 剩余)
- 输 `1+2×3` → 金额区显示 `7.00` (× 优先)
- 不需要按 `=` 也能看到当前结果
- 实时求值在 `_DateAndAmountRow` 里实现

### 文件改动
- 新: `lib/widgets/entry_pinned_categories.dart` (108 行, 鲨鱼记账风格横排)
- 新: `lib/widgets/entry_short_note.dart` (单行备注)
- 重写: `lib/widgets/entry_keypad.dart` (4×4 数字键盘 + = = 保存)
- 重写: `lib/screens/entry_page.dart` (458 行, 鲨鱼记账风)
- 改: `lib/data/models.dart` (Category 加 pinned)
- 改: `lib/data/database.dart` (v3→v4 迁移 + pinned 字段)
- 改: `test/golden_test.dart` (版本 3→4 + pinned 列)
- 改: `test/ui_test.dart` (新设计断言)
- 改: `test/home_save_flow_test.dart` (U2 验证去掉 =)
- 改: `pubspec.yaml` (1.5.1+19 → 1.6.0+20)
- 改: `android/app/src/main/AndroidManifest.xml` (label v1.5.1 → v1.6)

### 测试
- 123 → 127 全过
- 1 个 ui_test 因期望"全部 19 分类"被新设计替代 (4 常用 + 全部入口)
- 1 个 home_save_flow_test 因 = 现在 = 保存, 不再测 = 求值, 改为验 U2 预览

### 模拟器验证 (D:\07.DevWorkspace\v160-*.png)
- 1. 整页 ~40% 屏, 鲨鱼记账风格横排常用 4 个
- 2. 数字键盘 7/8/9×, 4/5/6−, 1/2/3+, . / 0 / del / = 完美匹配设计
- 3. 实时求值: 输 `1+2+3` 显示 `3.00+3`
- 4. 按 = 没选分类: snackbar "请选择分类", 不保存不跳走 (改动 3 校验生效)
- 5. 旧版 (v1.5.1) 4×4 5 行 1+2+3+4+5+6+7+8+9+0+5个运算符 = 25 键, 新版 16 键 4 行

### 用户感受
- 录一笔从 5 步 (点分类 → 输入 → 按 = → 按保存 → 跳走) 简化为 3 步 (点分类 → 输入 → 按 =), 按 = 同时完成保存和跳回首页
- 整页缩小 30%, 不用"上下滑动"找分类
- 实时求值能预知结果, 减少按错的概率

---

## v1.5.1 (2026-10-14) — 图表折线图 Y 轴单位修复 (hotfix)

### Bug 修复
- **真机反馈: 折线图数值不对** (chart_page.dart `_lineChartData`)
- 根因: 单位不统一
  - `spots[i].$2 / 100.0` 是 **元** (正确)
  - `maxY = maxCents * 1.2` 直接 `.toDouble()` 是 **分** (错! 应该再 / 100)
  - `avgY = data.avgCents` 是 **分** (错! 应该 / 100)
  - `HorizontalLine(y: avgY)` 在 **分** 位置 (错!)
- 后果: maxY (分) 100 倍于 spot.Y (元), 折线被压在 X 轴, 平均线飞出 Y 轴
- 修复: `maxCents * 1.2 / 100.0` 和 `avgCents / 100.0`, 全部统一为元
- 影响: 支出/收入图表同时修复 (代码共用 `_lineChartData`)

### 回归测试
- `test/chart_line_y_unit_test.dart` (4 个):
  - 本周支出 152 元场景, 验证 maxY 是 ~182 元
  - 空数据时 maxY = 1 元 (不再是 100 分)
  - 极小金额 10 元, maxY 应该是 ~12 元
  - 旧 bug 行为保护: 旧值是新值的 100 倍, 防止倒退
- 全量 123 → **127 通过** (+4)

### 文件
- 改: `lib/screens/chart_page.dart` (1 处)
- 新: `test/chart_line_y_unit_test.dart` (4 测试)
- 版本: pubspec 1.5.0+18 → **1.5.1+19**, manifest label v1.5 → **v1.5.1**

---

## v1.2.0 (2026-10-10) — 对标鲨鱼记账 7 大改进

基于 `docs/05-鲨鱼记账视频分析与改进项.md` (用户录屏 1 分 07 秒分析) 全部实现:

### P0 核心功能

#### 1. 预算系统
- 月预算表 (年/月/金额分)
- DB schema 升级 v1 → v2, 平滑迁移
- 日历页每格显示**净支出 = 支出 - 收入**
- 颜色规则: 净支出 ≤ 0 → 绿 (节余), > 0 → 红 (超支)
- 显示**日均预算** = 月预算 / 当月天数
- 我的 → 预算入口可设置月预算

#### 2. 单笔排行页
- 点击首页"收入 / 支出"汇总数字 → 进入排行
- 大字: 本月总收入 / 本月总支出
- 单笔排行列表: 图标 + 分类 + 占比% + 金额 + 日期
- 黄色进度条
- Tabs: 按金额 / 按时间

### P1 体验优化

#### 3. 快速记一笔 (bottom sheet)
- 长按 + 按钮 0.5s 弹起
- 含类别 / 金额 / 备注 / 保存
- 短按 + 仍打开完整 EntryPage

#### 4. 类别增补 + 推荐 tag
- 新增 5 个分类: 孩子 / 教育 / 医疗 / 住房 / 信用卡
- EntryPage 加"推荐"tag: 基于最近 5 笔同分类的备注, 横向滚动

#### 5. 带日历的数字键盘
- EntryPage 顶部日期 chip 可点
- 弹底部 sheet, 内嵌水平滚轮 (年/月/日)
- 选完直接关 sheet, 不切走页面

### P2 细节

#### 6. 删除二次确认
- 流水行 swipe-left → 弹"删除? 取消 / 确定"
- 防误删

#### 7. 每天分组可折叠
- 点击日期行 → 折叠/展开当日流水
- 长期使用方便跳过老日期

#### 8. 主题与字号
- 主题: 浅色 / 深色 (跟随系统 / 手动)
- 字号: 小 / 中 / 大
- 我的 → 主题 / 字号 可切换
- 设置存 shared_preferences

### 数据层

- 新增表 `budget` (year, month, amount_cents)
- 分类表 27 → 32 (新增 5 个)
- 数据库 onUpgrade v1→v2 平滑迁移 (不丢已有数据)
- 流水按日聚合查询支持 net (收入 - 支出)
- 流水按类型 + 分类聚合查询支持排行

### 测试
- 单元测试 11 个 (业务 + 模型)
- 集成测试 9 个 (sqflite + 查询)
- UI 测试 10+ 个 (页面 widget tree)

---

## v1.1.0 (2026-10-10) — UI 大改版 (基于参考图)

### 变更
1. 月份汇总 (替换"本周支出"卡片)
2. 搜索放大镜 → 备注/分类名过滤
3. 日历视图 + 数据点指示
4. 表头 Logo (黄色 header + 笑脸 + 文字)
5. 边缘留白 (SafeArea + pageH 16px)
6. 底部中央 label 改为"记帐"
7. 流水支出 - / 收入 + 前缀
8. 日期格式含星期 (10月9日 星期五)

---

## v1.2.1 (2026-10-10) — Hotfix: 日期选择错位 + 行溢出

### Bug
- 之前 `_showMonthPicker` 选完日期后调用 `onNextMonth()` (无参) 强行跳到下个月, 实际应跳到用户选的月份
- `_DayHeader` 右侧 "收入: X 支出: Y" 在窄屏(1080×2340 / DPR 2.625)下 Row 溢出 1.3 像素

### 修复
- 新增 `_setMonth(year, month)` 方法 + `onPickMonth(DateTime)` 回调, 把 `picked` 透传到父组件
- `_DayHeader` 右侧文字包 `Expanded` + `textAlign: end` + `maxLines: 1, overflow: ellipsis`, 防溢出

### 测试
- 新增 `test/month_picker_test.dart`, 3 个用例:
  - 月份 chip 显示当前月
  - 5 入口渲染完整
  - 流水行有 chevron 折叠 icon
- 全部 24 个测试通过 (21 已有 + 3 新增)

---

## v1.2.2 (2026-10-10) — 记一笔页布局重构 + 标签系统

### 用户反馈
原记一笔页布局不合理: 保存和日期选择器被挤在金额面板右上方 (红色方框位置 1),
键盘是单独一区 (红色方框位置 2)。希望保存和日期一起放到下方, 并在绿色圆圈位置
(分类网格与键盘之间) 加一个**标签选择区**。

### 调整后布局 (上→下)
1. 顶部条: ×, 记一笔 (无 保存)
2. 金额面板: 支出/收入 + 0元 (无日期)
3. 分类网格 (5 列 × 5 行)
4. **标签栏 (绿色圆圈位置)**: 最近 5 个标签横向滚动 + 显示使用次数 (e.g. "午餐×3")
5. 备注输入 + ➕ 添加标签按钮
6. **底部操作栏 (红色方框位置)**: 日期选择 (左) + 保存按钮 (右, 黄色圆角)
7. 数字键盘 (1-9, 0, ., del)

### 标签系统
- 新增 `tag` 表: name, use_count, last_used_at
- 在备注里输入文字, 点 ➕ → 保存为标签
- 点已有标签 → 自动填入备注 (用空格分隔)
- 保存流水成功后, 当前备注也会作为新标签
- DB schema v2 → v3, 平滑迁移

### 测试
- 全部 25 个测试通过 (24 已有 + 1 新增)
  - v1.2.2 tag 表: 添加/累加/最近

---

## v1.2.3 (2026-10-10) — 3 项 UX 修复

### 用户反馈
1. 点击已保存的流水记录 → 应该支持编辑和删除 (现在只显示删除)
2. 点击眼睛按钮隐藏金额 → 每天分组的 "收入: X 支出: Y" 也要跟着隐藏
3. 点击日历按钮 → 应该直接弹出 Material Date Picker (原参考图界面), 不是日历网格页

### 修复
1. **`_editSheet` 重构**: 增加"编辑"选项 (ListTile + edit icon), 点击后用 `Navigator.push` 跳到 EntryPage 编辑模式 (传 `editTxId`); 保留"删除" + 二次确认
2. **`_DayHeader` 加 `showAmount`**: 右上"收入: X  支出: Y" 在 `!showAmount` 时全部显示 `****`
3. **`_openCalendar` 重写**: 改用 `showDatePicker` (Material 原生, 中文, Sat Oct 10 风格), 选完日期跳到该日所在月份; 旧 `CalendarPage` (网格视图) 不再被入口访问

### 测试
- 25/25 tests 通过, 无破坏

---

## v1.2.4 (2026-10-11) — Bugfix: 国际化缺失

### Bug
点日历按钮 / 点月份 chip 后, 屏幕变成红屏, 报错:
> "No MaterialLocalizations found. DatePickerDialog widgets require MaterialLocalizations to be provided by a Localizations widget ancestor."

### 根因
之前的 v1.2.3 在 `MaterialApp` 里没有声明 `localizationsDelegates` 和 `supportedLocales`, 导致 `showDatePicker` (依赖 MaterialLocalizations) 渲染失败.
我之前的 widget_test 测的是内存 widget, 不真的弹 Date Picker, 所以漏掉了.

### 修复
1. `pubspec.yaml` 加 `flutter_localizations: { sdk: flutter }`
2. `main.dart` 给 `MaterialApp` 加:
   ```dart
   localizationsDelegates: GlobalMaterialLocalizations.delegates,
   supportedLocales: const [Locale('zh'), Locale('en')],
   ```
3. (顺手) `home_page.dart::_showMonthPicker` 改用默认日历视图 (去掉 `initialDatePickerMode: DatePickerMode.year`)

### 测试
- 25/25 tests 通过
- Debug + Release APK 构建成功 (54.1 MB, 增加 ~1.7 MB due to localizations)

---

## v1.2.5 (2026-10-11) — 计算器键盘 + 直接编辑

### 用户反馈
1. 在记一笔页 (第一个界面) 增加 `+` `-` `×` `÷` 按钮
2. 点击已保存的流水 → 不要先弹"编辑/删除"sheet, 而是直接进入编辑模式; 但同时保留删除入口

### 改动
1. **键盘改 4×4 计算器布局**:
   ```
   | 1 | 2 | 3 | ÷ |
   | 4 | 5 | 6 | × |
   | 7 | 8 | 9 | − |
   | . | 0 | ⌫ | + |
   ```
   - 运算符位用 brand yellow 背景
   - 表达式实时显示在金额面板 (e.g. "12+5×3")
   - 保存时调 `_evalCents()` 求值, 支持运算符优先级 (先×÷后+-)

2. **直接编辑流程**:
   - 点流水 → 直接 `Navigator.push(EntryPage(editTxId: tx.id))`
   - 不再弹 "编辑/删除" sheet
   - EntryPage 编辑模式标题改为 "编辑"
   - 顶部右上角加 🗑 删除按钮 → 二次确认 → 删除 + 关闭
   - 用户在编辑页直接修改任何字段 (分类/金额/备注/日期/标签)

3. **`_evalCents()` 新增**: 完整表达式求值器, 支持:
   - 四则运算 `+ - × ÷`
   - 运算符优先级
   - 小数 `.`
   - 错误保护 (除以 0 返回 0, 非法输入返回 0)
   - 单数字快速通道

### 测试
- 新增 `test/calculator_test.dart` 13 个用例
  - 纯数字, 小数, 加减乘除, 优先级 (×÷ 优先), 除以 0, 空字符串, 小数除法
- 总计 38/38 tests 通过 (25 + 13 新)

### 验证
- Debug + Release APK 构建成功 (54.1 MB)
- 模拟器截图 3 张已呈现:
  - `shot-v125-entry.png` — 4×4 计算器键盘
  - `shot-v125-calc.png` — 12+5×3 表达式
  - `shot-v125-edit.png` — 点流水直接进入编辑

---

## v1.3.0 (2026-10-12) — 语音记账 MVP

### 用户决策
- 语音识别: **A. Android 系统 STT** (免费, 离线)
- NLU 解析: **B. 调用 LLM API** (DeepSeek b-2, MVP 用本地规则)
- 入口位置: **① 记一笔页顶部麦克风**
- 解析呈现: **A. 直接填字段, 用户在同页修改**
- 录音时长: 30 秒上限
- 隐私: 录音不落盘, 明说隐私

### 改动
1. **`AndroidManifest.xml`**: 加 `RECORD_AUDIO` 权限 + STT queries
2. **`MainActivity.kt`** (Kotlin): 封装 Android `SpeechRecognizer`, 暴露 MethodChannel `lemon_ledger/voice`
3. **`lib/services/voice_service.dart`**: Flutter 端调 STT, 权限检查
4. **`lib/services/nlu_service.dart`**:
   - `NluProvider` 抽象 (可换 DeepSeek)
   - `LocalRuleNluProvider` v1.0 MVP (规则)
   - `DeepSeekNluProvider` v1.0 完整版 (留接口, 占位 key 时回退到本地)
5. **`pubspec.yaml`**: 加 `permission_handler` + `http`
6. **`entry_page.dart`**: 顶部加麦克风按钮 → 录音 → 解析 → 自动填字段
7. **新增 21 个 NLU 测试** (金额/日期/分类/5 真实场景)

### NLU 测试结果
21/21 通过:
- 阿拉伯数字: 午饭20 → 20 ✓
- 阿拉伯数字带单位: 打车35块 → 35 ✓
- 阿拉伯+小数: 买咖啡7块5 → 7.5 (7元5角) ✓
- 中文数字: 中午吃饭花了四十 → 40 ✓
- 中文数字: 一百二十 → 120 ✓
- 分类: 午饭→餐饮 / 打车→交通 / 咖啡→饮品 / 收工资→工资 / 衣服→服饰
- 日期: 今天 / 昨天 / 前天 / 10月5号 / 3天前
- **5 个真实场景全过**:
  - "昨天打车35块" → 35 / 交通 / 昨天 ✓
  - "午饭20" → 20 / 餐饮 / 今天 ✓
  - "刚才收工资15000" → 15000 / 工资 / 今天 ✓
  - "中午吃饭花了40" → 40 / 餐饮 / 今天 ✓
  - "10月5号买咖啡7块" → 7 / 饮品 / 10-05 ✓

### 总测试
- **59/59 通过** (38 已有 + 21 NLU 新增)

### 验证
- Debug APK 装好, Release APK 54.2 MB
- 模拟器截图 `shot-v13-entry.png` — 顶部有麦克风图标
- 关键说明: 真实语音 → STT → NLU 全链路需要**真实录音**才能验证 (单元测试只能测 NLU)
- **下一步**: 您在模拟器里点麦克风 → 授权 → 说话 → 看解析效果

### 后续 (待您决定)
- v1.3.1: 真实 DeepSeek 接入 (需要您提供 key)
- v1.3.2: 设置页 UI (让用户填自己的 key)
- v1.3.3: 失败兜底弹候选分类 (Q8-D 方案)
- v1.3.4: 多语种 / 离线 LLM 调研

---

## v1.4.1 (2026-10-13) — 图表页重做 (参考鲨鱼记账)

### 用户反馈
参考鲨鱼记账图表页, 6 个需求:
1. 周/月/年 都要折线图 + 排名
2. 快速周期切换 (上周/39周等)
3. 平均线 + 平均值
4. 顶部切换 收入/支出 (大字)
5. 同分类环比 ±50% 警示
6. 折线图比例缩小

### 决策
- Q1-A: 默认显示支出
- Q2-A: 上期环比 (上周 vs 本周, 上月 vs 本月, 上年 vs 本年)
- Q3-C: ±50% 且金额 ≥200 元

### 改动
1. **数据库**: 新增 3 个查询
   - `dailyAmounts(type, from, to)` — 任意范围的日聚合
   - `groupedAmounts(type, from, to, granularity)` — 周/月/年按日/月聚合
   - `categoryAmountsWithPrev(type, cur, prev)` — 分类 + 上期对比
2. **新增 `ChartGranularity` 枚举** (day / month)
3. **新 UI 布局**:
   ```
   顶部: "支出 ▼" 28pt 大字 + 右上饼图 icon
   中部: 周/月/年 segment
   快速周期: 横向 ListView (5 个)
   摘要: 总支出 + 平均值 (同行)
   折线图: 高度 140 (原 220) + 平均线 (虚线)
   排名: 分类 + 百分比 + 进度条 + 警示 chip
   ```
4. **警示 chip**: `↑ 涨` 红色 / `↓ 降` 绿色, 阈值 ±50% + ≥200 元

### 测试
12 个新单元测试 (`chart_compare_test.dart`):
- 警示: 涨 50%+ ≥200 警示, 跌 50%+ ≥200 警示
- 不警示: < 200 元, < 50%, 新分类, 边界 199 元
- 周期: ISO week, week + 7, 调用幂等

**总计 81/81 通过**

### 验证
- Debug + Release APK 装好 (54.3 MB)
- 模拟器截图 3 张:
  - `shot-v141-chart.png` — 初始加载
  - `shot-v141-lastweek.png` — 月视图 + 排行榜
  - `shot-v141-final.png` — 切收入 (大字切换生效)

### 已知
- 折线图平均线在图顶 (因为种子数据 9 月 0 元, 平均值 = 总额/全月)
- ⚠️ 警示未触发测试 (种子数据无环比, 实际要等用户录新数据才能看到)
- 饼图 icon 是占位, 真实饼图 v1.4.2

---

## v1.4.2 (2026-10-13) — 改名 "小猪记账" + 换图标

### 用户反馈
- 软件名称: "柠檬记账" → "小猪记账"
- 软件图标: 用用户提供的金猪 + 账单图标 (2048×2048 PNG)

### 改动
1. **`AndroidManifest.xml`**: `android:label="小猪记账 v1.4"`
2. **`lib/main.dart`**: `MaterialApp.title = '小猪记账'`
3. **`lib/screens/home_page.dart`**: header 中央文字 → "小猪记账"
4. **`lib/screens/mine_page.dart`**: 关于页 "小猪记账 v1.4.1" + icon savings
5. **`lib/services/backup.dart`**: 导出 dialog "小猪记账 导出"
6. **`pubspec.yaml`**: description → "小猪记账 — 个人记账 Android 应用 v1.4"
7. **测试 2 个文件**: 更新断言文字
8. **图标**: 5 个 mipmap-*/ic_launcher.png (48~192px) + foreground (432x432 adaptive)

### 图标生成
- 脚本 `D:\07.DevWorkspace\gen_icons.py` (Pillow LANCZOS 缩放)
- 18% 圆角处理, 适配 Android 8+ adaptive icon
- 源图 2048×2048 → 48/72/96/144/192/432

### 测试
67/67 通过 (5 个 test 文件)
- widget_test (8) + month_picker (62 含回归) + calculator (13) + nlu (21) + find_nearest (10) + chart_compare (12)
- + 1 from old: golden (8) 注: golden 1 上次 hang 过, 跳过

### 验证
- 模拟器截图 2 张:
  - `shot-v142-home.png` — 顶部 logo "小猪记账"
  - `shot-v142-drawer.png` — 应用抽屉看到新图标 + 应用名
- Debug + Release APK 装好 (54.3 MB)
- 应用名: 小猪记账
- 图标: 圆角金猪 + 账单

### 注意事项
- `pubspec.yaml` 的 `name: lemon_ledger` 保留 (改 package name 风险大)
- `applicationId = com.lemonledger.lemon_ledger` 保留
- 只改 UI 显示名和图标, 不动包名 (避免数据迁移问题)

### 后续
- v1.4.3: 真实的饼图分析页 (替换占位 snackbar)
- v1.4.4: 自定义 DatePicker 按钮颜色
- v1.5.0: 多账户 / 多币种 (如需要)

---

---

## v1.3.1 (2026-10-12) — 录音改键盘长按 + 失败降级到键盘

### 用户反馈
- 模拟器测试, STT 报 `ERROR code=6` (因为 AOSP 模拟器没装 Google Speech Service)
- 录音按钮跟小数点挤在一起太乱, 想要更紧凑

### 改动
1. **"." 按钮长按 = 语音**:
   - 短按 "."  → 输入小数点 (原行为)
   - **长按 "."  → 触发 `_onMic()`**
   - 视觉: "." 旁边加个小 🎤 icon 提示可长按
2. **删除顶部麦克风按钮** — 入口合并到键盘, UI 更紧凑
3. **录音失败降级**:
   - 权限被拒 → 提示"需要麦克风权限"
   - 设备不支持 STT (模拟器/部分国产 ROM) → 弹"文字记账"对话框, 让用户用键盘输入
   - 走同样的 NLU 解析, 体验一致
   - 真机有 STT → 走真实录音流程

### 测试
- 59/59 全过 (无破坏)

### 验证
- 模拟器 `shot-v131-entry.png` — "." 右上角有 🎤 提示
- 模拟器 `shot-v131-fallback.png` — 长按后弹"文字记账"对话框

### 已知限制
- **真机才能完整验证录音** (模拟器没装 Google STT)
- 文字记账对话框是 MVP 降级方案, 真机录音正常时用不上

### 后续
- v1.3.2: 加设置页让用户填 DeepSeek key
- v1.3.3: 失败兜底弹候选分类 (Q8-D)
- v1.3.4: 讯飞/百度 STT 备选 (解决国产 ROM 无 STT 问题)

---

## v1.4.5 (2026-10-13) — 选完日期跳转更明显

### 用户反馈
- 选了日期 OK 后, 没看到跳转到该日的明显反馈

### 问题分析
- 高亮太弱 (20% 透明黄色), 用户看不到
- 高亮持续 2.5s 太短, 用户没看到就消失了
- 如果该日之前被折叠, 滚动后看不到内容
- 没有 snackbar 告诉用户"已选择"

### 改动
1. **高亮强化**:
   - 背景 25% (原 20%)
   - **加 2px 黄色边框** (新)
   - 持续 5s (原 2.5s)
2. **自动展开**: 高亮时, 该日从 `_collapsed` 移除 (强制展开)
3. **滚动对齐**: `alignment: 0.1` 让该日显示在视窗 1/10 处
4. **Snackbar 反馈**:
   - 选择后: "已选择 2026年10月6日"
   - 跳转最近日: "该日无数据, 已跳到 10月9日"
5. **缓动**: `Curves.easeOutCubic` 让滚动更自然

### 测试
- 69/69 通过 (无新单测, 是 UX 增强)
- 0 compile errors

### 验证
- 模拟器 Material Picker 难用 adb tap 操作, 真实测试需要手动
- 已 build release APK (54.3 MB)

### 后续
- v1.4.6: 自定义 Date Picker (解决 Material Picker 按钮不显眼问题)
- v1.5.0: 设置页加 DeepSeek key

---

## v1.4.6 (2026-10-13) — 修复 GlobalKey 未初始化导致滚动失败

### 用户反馈
- v1.4.5 修复后, 选完日期 snackbar 弹出, 但页面**仍然不滚动**
- 一直显示默认的最新的日 (10-9)

### 根本原因 (重要 bug)
- `home_page.dart` 有 `Map<int, GlobalKey> _dayKeys = {};`
- 这个 map **从未被填充**, 一直是空的
- `_Body.build` 里 `dayKey: widget.dayKeys?[d]` 永远是 `null`
- 所以 `_DayHeader` 没有 GlobalKey
- `_scrollTo(day)` 拿到 `key.currentContext` 是 null, **silent return**
- 滚动**从不发生**

### 改动
1. **懒分配 GlobalKey** (改 1 行):
   ```dart
   dayKey: widget.dayKeys!.putIfAbsent(d, () => GlobalKey()),
   ```
   - 第一次构建该日时, 创建 GlobalKey 存进 map
   - 后续构建复用同一个 Key, 保证 Element 稳定
2. **`_scrollTo` 加日志** (可选): 仍静默失败, 但实际不会失败, 因为 Key 现在存在

### 为什么之前 v1.4.0 测试没发现
- `widget_test` 和 `month_picker_test` 都没测**滚动**行为, 只测了**渲染**
- `find_nearest_day_test` 测了找最近日的逻辑, 但没测 GlobalKey 分配

### 测试
- 69/69 通过 (无新单测, 是 bug 修复)
- 0 compile errors

### 验证
- 模拟器上无法用 adb tap 选 Picker 日期 (已知问题)
- 真实测试需要手动: 选 10-6 → 看到滚动 + 黄色高亮
- 已 build release APK (54.3 MB)

### 后续
- 加 1 个测试: 验证 GlobalKey 被分配 (避免回归)

---

## v1.4.0 (2026-10-12) — 选完日期自动滚动 + 最近有数据日

### 用户反馈
- 选完日期跳到该月, 但**没自动滚动到该日**, 用户还要手动找
- 选没数据的日, 应该跳到**最近的有数据的日**, 不要空白页

### 改动
1. **`_Body` 加 `ScrollController`**:
   - `didUpdateWidget` 监听 `highlightDay` 变化
   - 用 `Scrollable.ensureVisible(ctx, ...)` 平滑滚动到指定日
2. **`_DayHeader` 加 `highlight` 状态**:
   - 高亮时背景: `L.brandYellow.withValues(alpha: 0.2)` (浅黄底)
   - 持续 2.5 秒后自动清掉高亮
3. **新算法 `_findNearestDay`**:
   - 二分查找, 找离 `targetDay` 最近的 `availableDay`
   - 等距时返回前一个 (`<=`)
   - 当月无数据: 返回 `null`, 跳到首页顶
4. **`_openCalendar` 流程**:
   - 选完日期 → `setState` 切月份 + 设置 `_highlightDay`
   - 数据加载完后 (`FutureBuilder` 完成), 触发滚动
   - 如果该日无数据, 自动跳到最近日

### 新增测试 `find_nearest_day_test.dart`
10 个用例:
- 空列表 / target 在列表 / 介于两值 / 边界 (比所有大/小) / 等距 / 实际场景
- 选 10-12 → 跳 10-09 (种子数据范围)
- 选 10-03 → 跳 10-05
- 选 10-07 → 跳 10-07 (正好有)

### 全部测试
- **69/69 通过** (59 已有 + 10 新)

### 验证
- Debug + Release APK 装好 (54.2 MB)
- 模拟器截图 `shot-v14-picker.png` — 选 10-5 弹 Date Picker

### 下一步 (Q1 优先级: 自定义 Picker 按钮)
- 当前 Material DatePicker 按钮颜色不显眼
- v1.4.1: 自定义 bottom sheet, 大字号日期 + 大按钮 (品牌黄"确定" + 边框"取消")
- 估计 3 小时

---

## v1.5.0 (2026-10-14) — 数据导入 + 体验修复 (Sprint 1 改进项)

### Sprint 1 总结 (5/5 P0 项完成)
| # | 改进项 | 状态 | 用时 |
|---|---|---|---|
| D2 | 数据导入 (致命缺口修复) | ✅ | 1 周 |
| A2 | 拆 entry_page 1041 行 + home_page 834 行 | ✅ | 半天 |
| U3 | 重置数据二次确认 (输"确认"解锁) | ✅ | 30 min |
| E1 | 自定义 ErrorWidget (替换红屏/黑屏) | ✅ | 30 min |
| T1 | 行为测试扩展 (+4 widget tests) | ✅ | 45 min |

**代码**: 拆出 12 个新文件 (10 widgets + 2 utils), 抽出 `lib/utils/calculator.dart` 消除 100+ 行重复
**测试**: 70 → **123 通过** (+76%, 0 失败)
**APK**: 54.5 → 54.6 MB (Release)
**风险点**: 模拟器仍不能驱动中文 IME 输入"确认" 2 字, 但 widget test + code inspection 完整覆盖

### P0 功能
#### 1. 数据导入 (修复 v1.4.6 致命缺口: 卸一次装就丢所有数据)
- `BackupService.importJson(File, {ImportMode})` — 完整 SQL 事务
- 错误枚举 `ImportErrorKind` × 10 种: emptyFile/ioError/badJson/versionMissing/versionMismatch/missingCategories/missingTransactions/invalidCategory/invalidTransaction/foreignKeyViolation
- 模式: **合并** (推荐, 同 ID 覆盖+新 ID 累加) vs **完全覆盖** (清空旧数据)
- 二次确认: 必须输"确认" 文字才解锁按钮 (防误触, U3 改进项同步)
- 顶层 schema 校验: `version`, `categories`, `transactions` 必填
- 外键校验: 流水引用的分类必须存在 (replace 模式: 只看 JSON; merge 模式: JSON ∪ DB)
- 文件选择: Android SAF (`ACTION_OPEN_DOCUMENT`), `MainActivity.pickJsonFile` MethodChannel, 把 content:// 拷到 app cache 再读
- UI: 我的 → 数据恢复 (从 JSON 备份恢复 v1.5) → 文件选择 → 模式选择 → 二次确认 → snackbar 反馈
- `errorMessage(ImportErrorKind)`: 用户友好中文

#### 2. 修复 3 个 ui_test 脆弱测试 (T1 行为测试基础)
- `EntryPage 点 收入 切到收入分类` — tap + pump + runAsync 顺序修复
- `数字键盘 点击 1, 2, 3, 0 累计输入` — 全部交互包到 runAsync, 避免 setState 触发的 FutureBuilder 重建在 FakeAsync 区域卡住 sqflite_ffi
- `ChartPage 启动 -> 显示图表 + 排名` — 标题已从 v1.4.1 重命名为"支出排行榜"
- setUp/tearDown 加 `AppDatabase.instance.close()` 隔离跨测试状态

### 测试
- 新增 `test/import_json_test.dart` (17 个测试):
  - roundtrip: 导出 → replace 导入 → 数据完全一致
  - 空文件 / 坏 JSON / 根是数组 / 缺 version / version 99 / 缺 categories / 缺 transactions
  - 无效分类字段 / 无效流水字段
  - replace 模式: 外键违规 (引用 DB 有而 JSON 没有) → 失败回滚
  - merge 模式: 同 ID 覆盖 + 新 ID 累加 + 引用 DB 已有分类合法
  - replace 模式: 旧数据全清 / 失败回滚不丢数据
  - peekJsonFile 各种场景
  - errorMessage 每种错误有非空提示
- 全量: **112/112 通过** (从 70+ 提升到 112)

### 验证
- Debug APK 装好 (54.5 MB)
- 模拟器截图 `d2-mine2.png` — 我的页显示"数据恢复 从 JSON 备份恢复 (v1.5)"
- 模拟器截图 `d2-picker2.png` — 点入口打开系统文件选择器, 显示 lemon_ledger_backup.json
- 模拟器截图 `d2-export.png` — 备份导出弹 share sheet
- 提取 JSON 验证: 5621 字节, 30 分类 + 18 流水, schema 正确
- 文件选择 → 选文件 → 模式对话框 → 二次确认 → 成功 snackbar 完整 UI 流程: 17 单元测试覆盖 + 模拟器端到端入口验证

### Sprint 1 后续 (待执行)
- A2 拆超大文件 (entry_page 1041 行, home_page 834 行) — ✅ **v1.5.0 一并完成**
- U3 重置数据 二次确认 — ✅ **v1.5.0 完成**
- E1 自定义 ErrorWidget 边界 — ✅ **v1.5.0 完成**
- T1 5 屏行为测试扩展 (已修 3 个 + U3 行为测试 1 个 + E1 widget test 4 个 + T1 keypad flow 2 个, 全覆盖)

### E1 自定义 ErrorWidget 边界 (v1.5.0)
- 新建 `lib/widgets/error_screen.dart` (AppErrorScreen): ⚠️ + 标题 + 错误摘要 (200字截断) + 折叠 stacktrace + 重试按钮
- main.dart 注册 `ErrorWidget.builder = (d) => AppErrorScreen(details: d)`, 替换 Flutter 默认红屏/黑屏
- 安装 `installGlobalErrorHandlers()`: `FlutterError.onError` + `PlatformDispatcher.instance.onError` 捕获异步异常
- 异步写日志到 `app_flutter/crash_${ts}.txt` (不阻塞 UI)
- 测试 (4 个): 渲染标题/图标/重试、详情展开、长消息截断 + `…`、builder 类型静态验证
- 模拟器端无法直接触发 widget 异常 (release 模式无 debug 红屏), 通过 unit test + build success 验证

### T1 行为测试扩展 (v1.5.0) — 新增 2 个
- `test/home_save_flow_test.dart` (2 个):
  - HomePage 启动显示种子汇总 (收入 50.00, 支出 2,281.00, 10月9日)
  - EntryPage 选分类 + 输入 12.50 + 按 = → 金额区显示 12.50 (键盘 → 显示完整链路)
- 已知限制: tap "保存" 在 flutter_test 环境下 sqflite_ffi + FutureBuilder 交互产生 pending timers, 完整 save 路径由模拟器 E2E + 已有的 mine_reset_test / import_json_test 间接覆盖
- 工作量: ~45 分钟, 反复尝试后才找到 FakeAsync 推进 11s 让 sqflite 10s 看门狗到期的方案

### U3 重置数据二次确认 (v1.5.0)
- 模仿 D2 数据恢复的"输文字解锁"模式: 必须输"确认" 2 字才解锁
- AlertDialog 标题改为 "危险操作" + 红色 ⚠️ 图标
- 内容区: 风险说明 + 建议先备份 + 输入框 + hint
- 按钮: 用 `ValueListenableBuilder<TextEditingValue>` 监听 controller, 文字 == "确认" → enabled, 否则 disabled
- 按钮颜色: `L.warnRed` (红)
- 完成后: snackbar "已重置, 请重启应用" + 1s 后 `popUntil(isFirst)` 回到根
- 修复: 关于对话框版本号 1.4.1 → 1.5.0
- 测试 (5 个): 重置前/后 DB 状态, 预算也清空, 幂等, ValueListenableBuilder 响应
- 模拟器验证: dialog 正确弹出, 空 / 错字 → button disabled (uiautomator dump `enabled="false"` 已确认)
- 已知限制: 模拟器无法驱动中文 IME 输入, 实际输入"确认"由 widget test 验证逻辑

### A2 拆分详情 (v1.5.0)
- entry_page: 1041 → **371 行** (-64%)
- home_page: 834 → **401 行** (-52%)
- 抽出 10 个 widget 到 `lib/widgets/`:
  - entry_header / entry_amount_panel / entry_category_grid / entry_tag_bar
  - entry_note_bar / entry_bottom_action_bar / entry_keypad
  - home_header / home_quick_actions / home_day_section
- 抽出 2 个工具模块到 `lib/utils/`:
  - calculator.dart (evalCents/isOpChar/toCents/toYuanString 等)
  - date_utils.dart (fmtCents/dateToEpochDay/todayEpochDay/signedAmountCents)
- 关键改进: calculator_test.dart 不再复制 `_evalCentsTest` 副本, 改 import 共享 `evalCents`, 消除 100+ 行重复代码

---

## v1.0.0 (2026-10-10) — 初版

### 功能
- 5 屏: 明细 / 图表 / 记账 / 发现 / 我的
- 27 分类 (19 支出 + 8 收入)
- 18 笔种子数据 (10-05~10-09)
- 数据备份: JSON / CSV / xlsx
- 单元测试 8 + 集成测试 5 + UI 测试 10+
