# 记账统计模块 验收测试 (T01–T34)

小猪记账 · 记账统计模块的验收测试执行器。基于《测试与验收清单》T01–T34
用例与「性能验收」sheet，通过 httpx 直连真实 HTTP 服务执行。

---

## 1. 目录结构

```
acceptance/
├── README.md              本文档
├── harness.py             HTTP 客户端 / 断言工具 / 结果对象 / 证据落盘
├── fixtures.py            账本、分类、标签、对象、交易的造数夹具
├── test_cases.py          T01–T34，每条一个可独立执行的测试函数
├── run_all.py             执行器：汇总 + 逐条明细 (JSON + Markdown)
├── report_writer.py       渲染 docs/验收测试报告-v1.11.0.md
└── performance/
    ├── dataset.py         5 万笔基准数据集生成器（含参考聚合，用于对账）
    └── perf_runner.py     性能采样（冷/热缓存分层 P95）
```

## 2. 运行环境

| 项 | 值 |
|---|---|
| Python | `D:\UserFiles\eavon.cai\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe` |
| 依赖 | httpx / fastapi / uvicorn / pydantic（运行时已内置） |
| 服务端 | 默认 `http://127.0.0.1:8000`（`server/` 目录启动的 FastAPI 服务） |

环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ACCOUNT_API_BASE` | `http://127.0.0.1:8000` | 服务端地址 |
| `ACCOUNT_API_TIMEOUT` | `60` | 单请求超时秒数 |
| `ACCOUNT_PERF_DEVICE` | 未记录 | 性能验收设备标识 |
| `ACCOUNT_PERF_NETWORK` | 未记录 | 网络条件标识 |
| `ACCOUNT_PERF_DEPLOY` | 本地开发服务 | 部署形态标识 |

## 3. 快速开始

### 3.1 启动服务端（先行）

```powershell
cd D:\DSH\Account\server
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### 3.2 执行全部用例

```powershell
cd D:\DSH\Account\acceptance
python run_all.py --base-url http://127.0.0.1:8000 --write-report
```

执行器会：

1. 轮询 `/openapi.json`、`/docs` 等待服务端就绪（默认 60s，可用 `--wait` 调整）。
2. 按 T01 → T34 顺序逐条执行，每条用例独立造账本，互不干扰。
3. 把每条用例的 JSON 响应落盘到 `docs/acceptance-evidence/<用例号>/`。
4. 汇总到 `docs/acceptance-evidence/acceptance-results.{json,md}`。
5. `--write-report` 时再回填 T33（发布签核，依赖全局汇总），并渲染正式报告。

### 3.3 常用参数

```powershell
# 只跑指定用例
python run_all.py --only T01,T06,T30

# 跳过性能用例（快速回归）
python run_all.py --skip-perf

# 服务端未就绪时（全部用例标记 BLOCKED 并说明原因）
python run_all.py --wait 0

# 只输出 JSON，不打印明细
python run_all.py --json-only
```

### 3.4 单独执行性能验收（T14 / C140）

```powershell
cd D:\DSH\Account\acceptance\performance
python perf_runner.py 50000
```

会生成 5 万笔基准数据集（`docs/acceptance-evidence/performance/dataset.json`，
含参考聚合用于对账），然后对 5 个模块分别采样冷/热缓存分层 P95，
输出 `docs/acceptance-evidence/performance/perf-report.json`。

## 4. 单条用例结果结构

`test_cases.py` 中每个函数返回 `harness.TestResult`：

```python
{
  "id":         "T01",
  "level":      "P0",
  "name":       "正结余",
  "result":     "PASS" | "FAIL" | "BLOCKED",
  "actual":     {...},   # 实测值（响应关键字段）
  "expected":   {...},   # 预期值（来自测试清单）
  "evidence":   ["docs/acceptance-evidence/T01/summary.json", ...],
  "reason":     "",      # FAIL 写差异；BLOCKED 写阻塞原因
  "duration_ms": 12.3,
  "d_rule":     "",      # 关联未决规则 D0x（用于报告加注）
}
```

## 5. 判定口径

### 5.1 级别与门槛

- **P0 功能门槛**（20 条）：`T01 T02 T03 T04 T06 T07 T08 T09 T10 T11 T12 T15 T19 T23 T24 T26 T27 T30 T32 T33`
  —— 必须全部 PASS 才发布。
- **P1/P2**：其余 14 条。P1 未过提交评审，P2 记录处置。
- **C140 性能门槛**：T14 + 「性能验收」sheet。

### 5.2 PASS / FAIL / BLOCKED

| 结果 | 判定 |
|---|---|
| PASS | 所有断言成立，证据已落盘 |
| FAIL | 断言不成立，`reason` 写明**具体差异**（期望值 vs 实测值） |
| BLOCKED | 缺特性 / 需环境 / 依赖未冻结，`reason` 写明**阻塞原因** |

金额比较全部走 `Decimal`（`harness.amt` / `harness.pct`），避免浮点误差；
响应中的金额必须为十进制字符串（C84），出现 `float` 视为 FAIL。

### 5.3 未决规则 D01–D08

按 **PRD v0.9 建议口径**执行（用户已确认）。报告中对受
**D02 / D05 / D06 / D07** 影响的用例加注「按 PRD v0.9 建议口径，待最终确认」，
由 `harness.D_RULE_CASES` 映射驱动。

| 规则 | 建议口径 | 影响用例 |
|---|---|---|
| D02 | 指定项全失效时恢复该侧全部并提示，保留历史金额和可穿透历史桶 | T24 |
| D05 | 高置信自动合并，低置信人工确认；迁移前留来源映射，按账本校验收支与笔数 | T17, T18 |
| D06 | 周一为周起点；月末/闰日截到可用日期；日均按区间自然日；稳定并列键；百分比约定舍入 | T02, T10, T11, T13, T20, T22, T34 |
| D07 | 保留原值和来源，迁移输出异常清册及差额 | T30, T32 |

## 6. 目录约定（不越界）

本目录只写：

- `acceptance/**` —— 测试代码与性能脚本
- `docs/acceptance-evidence/**` —— JSON 证据
- `docs/screenshots/acceptance/**` —— 截图证据
- `docs/验收测试报告-v1.11.0.md` —— 正式报告

**不修改** `app/`（Flutter 客户端）与 `server/`（服务端实现），
所有数据均通过 HTTP API 写入。

## 7. 证据说明

| 类型 | 落盘位置 | 适用用例 |
|---|---|---|
| JSON 响应 | `docs/acceptance-evidence/<用例号>/*.json` | 全部非 UI 用例 |
| 性能原始数据 | `docs/acceptance-evidence/performance/*.json` | T14 |
| 截图 | `docs/screenshots/acceptance/` | UI 交互类用例 |

截图采集使用 `D:\07.DevWorkspace\android-sdk\platform-tools\adb.exe`，
模拟器 AVD `lemon_test`：

```powershell
adb -s emulator-5554 shell screencap -p /sdcard/acceptance_T01.png
adb -s emulator-5554 pull /sdcard/acceptance_T01.png docs/screenshots/acceptance/
```
