# 小猪记账 v1.8.0 — 功能说明书 (U1.9 收尾: 标签统计 + 饼图)

> **当前版本**: v1.8.0 (build 26) · 2026-10-18 · 小猪记账
> **包名**: `com.lemonledger.lemon_ledger`
> **APK**: `D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk` (55.2 MB)
> **前一个版本**: [v1.7.0 功能说明书](FEATURE-v1.7.md) (10-16)
> **Flutter**: 3.47.7 / Dart 3.13.5 / Android SDK 36 / JDK 17

---

## 本版本 (v1.8.0) 改动

### 1. 标签统计体系 (U1.9 收尾, 完整闭环)

**用户原始需求**:
> "下方列出的是 **按标签的排序 (按时间和按金额)**，以及**按标签的饼状图分析**"

**v1.7.0 实现**: 标签按频次排序 + 选分类联动 + TagManagerPage
**v1.8.0 实现**: 图表页 "标签" 视图 = 饼图 + 按金额/按时间 排序 + 排名

#### 1.1 数据库 schema v5

- 新表 `tx_tag (tx_id TEXT, tag_name TEXT, PRIMARY KEY(tx_id, tag_name))` + 索引 `idx_tx_tag_name`
- `tag` 加 `category_id TEXT` 列 (记录最近一次使用的分类)
- **onCreate (新装) 与 onUpgrade v4→v5 (升级) 共用 `_backfillTagsFromTxs`**: 从种子流水备注回填 11 个演示标签 (餐饮/交通/停车费/单车/充电/咖啡/信托/日用/孩子/旅行/医疗)
- **v1.8.0 修复**: 升级路径之前只回填已有 tag → 升级用户看不到饼图。修复后升级也跑 seed backfill

#### 1.2 TagService 新 API

```dart
syncForTx(Tx tx)             // 保存流水时同步关联
                            //   1. 整笔备注 addOrBump
                            //   2. 命中已有标签 → tx_tag 关联 + bump 频次
                            //   3. 整笔备注 → tx_tag 关联行
statsByTag(type, from, to, {sortBy})  // 周期内按标签聚合
                            //   SELECT tt.tag_name, SUM(x.amount_cents) AS s,
                            //          COUNT(*) AS n, MAX(x.epoch_day)
                            //   FROM tx_tag tt JOIN tx x ON x.id = tt.tx_id
                            //   WHERE x.type=? AND x.epoch_day BETWEEN ? AND ?
                            //   GROUP BY tt.tag_name
                            //   ORDER BY 金额 DESC | 最近使用 DESC
byCategory(categoryId)       // 改用 tx_tag 精确查询 (不走 LIKE 反推)
remove(name)                 // 删标签 + 清理 tx_tag 关联
```

#### 1.3 记帐页 _TagRow 接入 build (v1.7.0 漏写修复)

- 之前 `_TagRow` 是死代码, v1.8.0 接入到 `_EntryPageState.build` 的 Column (位置: 模块一 之后, EntryShortNote 之前)
- 高度 32px, 显示标签 chips + 末尾 "全部 ›" 入口
- 点击 chip → 追加到备注 (空格衔接)
- "全部 ›" → 跳到 TagManagerPage

### 2. 图表页 分类/标签 二级视图

- Header 右上角饼图 icon: 点击切换 分类↔标签 视图
- 饼图 icon 选中时填充 + 品牌黄; 未选中时 outline + 文字黑
- Row2 右侧加 `分类|标签` 切换 chips
- 标签视图内容 (`_TagStatsCard`):
  - 标题 "标签分析" + "N 个标签" 计数
  - 排序切换: 按金额 (深底白字) / 按时间 (透明底灰字)
  - **饼图** (150x150, fl_chart PieChart): top 6 标签 + 其他 灰色; 占比 ≥12% 中心徽标百分比
  - **图例**: 色点 + 标签名 + 百分比
  - **排名列表**: 序号 / 色点 / 名称 / 时间模式: 最近使用日期 / 笔数 / 金额 / 进度条
- 标签视图空态: "本周期暂无标签数据 / (记账时填写备注即可生成标签)"

### 3. 验证

- ✅ `flutter analyze`: 0 errors
- ✅ `flutter test`: **151/151 通过** (127 旧 + 24 新)
- ✅ Release APK: 55.2 MB
- ✅ 模拟器 e2e: 6 屏截图 (`docs/screenshots/v1.8.0/`)

## 涉及文件 (v1.8.0 改动)

| 文件 | 改动 |
|---|---|
| `lib/data/database.dart` | schema v5 + 升级 + 种子回填 |
| `lib/data/tag_service.dart` | Tag 加 category_id; 新增 syncForTx / statsByTag |
| `lib/screens/entry_page.dart` | 接入 _TagRow (v1.7.0 漏写) |
| `lib/screens/chart_page.dart` | ChartView enum + _ViewToggle + _TagStatsCard |
| `lib/screens/tag_manager_page.dart` | try/catch 防 tearDown 竞态 |
| `lib/screens/mine_page.dart` | 版本号 v1.8.0 |
| `android/.../AndroidManifest.xml` | label "小猪记账 v1.8" |
| `pubspec.yaml` | 1.8.0+26 |
| `test/tag_stats_test.dart` | **新, 18 用例** |
| `test/tag_view_widget_test.dart` | **新, 6 用例** |

## 已知限制

| 限制 | 原因 | 计划 |
|---|---|---|
| swiftshader 模拟器上, TagManagerPage 跳转偶发 hit-test 失效 | 软件渲染 + fl_chart 触摸区域干扰 | 真机正常; v1.8.1 加键盘可关 fl_chart 触摸 |
| 种子标签不含 "收入" 类 | 与记帐页类型 chip 同名会混淆 | 用户可在备注里自由创建 "收入" 标签 |
| tag↔tx 关联仍存 tx_tag 表 (无 tag.category_id 索引) | 数据量小, 全表扫可接受 | v1.9 加 |

## v1.8.0 截图

`D:\DSH\Account\docs\screenshots\v1.8.0\` (6 张):

- `01-home.png` — 首页
- `02-chart-category.png` — 图表 (分类视图, baseline)
- **`03-chart-tag-pie.png`** — 图表 标签视图 (饼图 + 排名, v1.8.0 新)
- **`04-entry-tag-row.png`** — 记帐 (标签行接入 build, v1.8.0 修)
- `05-mine.png` — 我的 (版本 v1.8.0)
- `06-mine-bottom.png` — 我的 底部 (关于 "小猪记账 v1.8.0")
