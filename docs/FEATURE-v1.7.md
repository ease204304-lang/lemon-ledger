# 小猪记账 v1.7.0 — 功能说明书 (U1.9 标签 + 图表升级)

> **当前版本**: v1.7.0 (build 25) · 2026-10-16 · 小猪记账
> **包名**: `com.lemonledger.lemon_ledger`
> **APK**: `D:\DSH\Account\app\build\app\outputs\flutter-apk\app-release.apk` (54.9 MB)
> **前一个版本**: [v1.6.4 功能说明书](FEATURE-v1.6.md) (10-15)
> **Flutter**: 3.47.7 / Dart 3.13.5 / Android SDK 36 / JDK 17

---

## 本版本 (v1.7.0) 改动

### 1. 标签系统重做 (U1.9)

**用户反馈**:
> "对于标签的写入。 点开单一类别，比如"零食"，标签支持自定义，自定义后成为标签放在下方。标签按使用频次由前到后排序。"

**实现**:

#### 1.1 标签按**使用频次**排序 (改 `TagService.recent`)
- **改前** (v1.2.2): `orderBy: 'last_used_at DESC'` — 最近用过优先
- **改后** (v1.7.0): `orderBy: 'use_count DESC, last_used_at DESC'` — 频次优先, 同频次按最近

#### 1.2 标签 ↔ 分类 关联 (新)
- 新 API: `TagService.byCategory(categoryId, {limit: 8})`
- 实现: 取全局 top 50 标签, 再用 `tx.note LIKE '%tag%' AND category_id = ?` 反推该分类的标签
- **优点**: 不改 DB schema, 完全兼容 v4 数据库
- **局限**: 改备注后关联可能失效 (v1.8 加 `tag.category_id` 列解决)

#### 1.3 选分类时自动刷新标签
- 记帐页: `onSelect: (c) { setState(_selected = c); _loadTags(); }`
- 选"餐饮" → 标签行显示餐饮相关的标签 (如 星巴克, 麦当劳, 奶茶)
- 取消选 → 标签行显示全局 top 5

#### 1.4 标签行 UI 增强
- 每个 chip 显示 **使用次数** (use_count ≥ 3 显示 `×N` 徽标, 黄色)
- 末尾加 **"全部 >"** 入口 → 跳到 `TagManagerPage`

### 2. 标签管理页 (新页面)

**入口**: 记帐页标签行 "全部 >" / 图表页排行行点击

**布局** (1080×2340):
```
┌──────────────────────────────────────┐
│ ← 返回    餐饮 · 标签          [+] │ ← AppBar + 新建按钮
├──────────────────────────────────────┤
│ 🔍 搜索标签 (按使用频次排序)         │ ← 搜索框
├──────────────────────────────────────┤
│  [周黑鸭]  [奶茶]  [咖啡]            │ ← 标签云 (Wrap)
│  [星巴克×3]  [麦当劳×2]  [地铁]      │   按 use_count DESC
│                                      │   大小/颜色按频次 (1-2 白, 3-5 浅黄, 6+ 黄加粗)
└──────────────────────────────────────┘
```

**功能**:
- 标签云: 大小/颜色按使用频次
- 点 chip: 提示"标签 X 已用过 N 次"
- 长按 chip: 删除标签 (带确认, 只删标签不删流水)
- 右上 `+`: 弹出"新建标签"对话框, 输入名称保存
- 搜索: 模糊搜 (按 use_count)
- 模式: 全部标签 / 某分类的标签 (标题带分类名)

### 3. 图表页升级

**用户反馈**:
> "点击"图表"展示的界面，支持点击具体一笔记录 对应成为类别的数据统计，下方列出的是 按标签的排序 (按时间和按金额)，以及按标签的饼状图分析。"

**v1.7.0 实现 (部分)**:
- ✅ 图表页排行行**可点击** → 跳到该分类的 `TagManagerPage`
- ⏳ "按时间/按金额的标签排序 + 标签饼状图" → 移到 v1.8 (需要 tag↔tx 关联表 + 新的 chart 子页)

---

## 涉及文件 (v1.7.0 改动)

| 文件 | 改动 |
|---|---|
| `lib/data/tag_service.dart` | recent 排序改 use_count; 新增 byCategory |
| `lib/screens/tag_manager_page.dart` | **新文件** (标签管理页) |
| `lib/screens/entry_page.dart` | _loadTags 按分类; 标签行加 "全部" 入口; onSelect 联动 |
| `lib/screens/chart_page.dart` | _RankingRow 加 InkWell/onTap |
| `lib/screens/mine_page.dart` | 版本号 v1.7.0 (2 处) |
| `android/.../AndroidManifest.xml` | label "小猪记账 v1.7" |
| `pubspec.yaml` | 1.7.0+25 |
| `app/VERSION.md` | 加 v1.7.0 changelog |

## 验证

- ✅ **127/127 tests pass** (含 13 个测试文件)
- ✅ **analyze 0 errors**
- ✅ Release APK 构建成功 (54.9 MB)
- ✅ 模拟器 6 屏 e2e 截图 (`docs/screenshots/v1.7.0/`)

## 已知限制

| 限制 | 原因 | 计划 |
|---|---|---|
| TagManagerPage 在 swiftshader 模拟器上 tap 不响应 (但 widget test 全过) | 软件渲染的 hit-test 限制 | 真机正常; v1.7.1 改进 |
| 标签↔分类关联靠 LIKE 反推 | 兼容现有 DB | v1.8 加 `tag.category_id` |
| "按标签排序 + 饼状图" 未实现 | 需要新数据模型 | v1.8 |

## v1.7.0 截图

`D:\DSH\Account\docs\screenshots\v1.7.0\` (6 张):

- `01-home.png` — 首页
- `02-chart.png` — 图表 (排行行可点击, v1.7.0 新)
- `03-entry.png` — 记帐 (标签行加 "全部" 入口, v1.7.0 新)
- `04-discover.png` — 发现
- `05-mine.png` — 我的 (版本 v1.7.0)
- `06-mine-bottom.png` — 我的 底部 (关于 "小猪记账 v1.7.0")
