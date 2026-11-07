"""SQLite 数据访问层 (W1)。

职责:
    * 建库建表 (schema.sql), 幂等
    * 账本版本 book_version / 全局维度版本 dimension_version
    * 统计缓存 statistic_cache (TTL 2 小时, 主动失效)
    * 一致性读视图: 在同一事务内读取版本与聚合
"""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence

APP_DIR = Path(__file__).resolve().parent
SERVER_DIR = APP_DIR.parent
DEFAULT_DB_PATH = SERVER_DIR / "data" / "account.db"
SCHEMA_PATH = APP_DIR / "schema.sql"

# C83: 缓存 TTL = 2 小时
CACHE_TTL_SECONDS = 2 * 60 * 60

_local = threading.local()
_db_path: Path = DEFAULT_DB_PATH
# 写锁: 序列化写事务, 避免 16 线程并发下 SQLite 写锁竞争导致 database is locked /
# WAL checkpoint 阻塞 (5 万笔批量写入场景)。读路径不受影响。
write_lock = threading.RLock()


def utc_now() -> datetime:
    """审计时间统一存 UTC。"""
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    return utc_now().isoformat(timespec="seconds")


def set_db_path(path: os.PathLike | str) -> None:
    """切换数据库文件 (测试用)。"""
    global _db_path
    _db_path = Path(path)
    _db_path.parent.mkdir(parents=True, exist_ok=True)
    # 关闭旧线程连接
    conn = getattr(_local, "conn", None)
    if conn is not None:
        try:
            conn.close()
        except sqlite3.Error:  # pragma: no cover
            pass
        _local.conn = None


def get_db_path() -> Path:
    return _db_path


def get_conn() -> sqlite3.Connection:
    """每线程一个连接, row_factory=sqlite3.Row。"""
    conn = getattr(_local, "conn", None)
    if conn is None:
        _db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(_db_path), check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        # 并发写入: 等待锁而不是立刻报 database is locked (16 线程批量写入场景)
        conn.execute("PRAGMA busy_timeout = 30000")
        conn.execute("PRAGMA synchronous = NORMAL")
        _local.conn = conn
    return conn


def close_conn() -> None:
    conn = getattr(_local, "conn", None)
    if conn is not None:
        conn.close()
        _local.conn = None


def init_db() -> None:
    """按 schema.sql 建表 (幂等)。"""
    conn = get_conn()
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    conn.executescript(schema)
    conn.execute(
        "INSERT OR IGNORE INTO dimension_version (id, version, updated_at) VALUES (1, 1, ?)",
        (utc_now_iso(),),
    )
    conn.commit()


def reset_db() -> None:
    """删除全部业务表数据 (测试/种子重建用)。"""
    conn = get_conn()
    tables = [
        "statistic_cache",
        "migration_issue",
        "transaction_tag",
        '"transaction"',
        "tag",
        "category",
        "counterparty_split_map",
        "counterparty_merge_map",
        "counterparty_audit",
        "counterparty",
        "book_version",
        "account_book",
    ]
    for t in tables:
        conn.execute(f"DELETE FROM {t}")
    conn.execute("UPDATE dimension_version SET version = 1, updated_at = ?", (utc_now_iso(),))
    conn.commit()


# ---------------------------------------------------------------------
# 账本与版本
# ---------------------------------------------------------------------
def list_books() -> List[sqlite3.Row]:
    return list(get_conn().execute("SELECT * FROM account_book ORDER BY id"))


def get_book(book_id: str) -> Optional[sqlite3.Row]:
    return get_conn().execute("SELECT * FROM account_book WHERE id = ?", (book_id,)).fetchone()


def user_has_book_access(book_id: str, user_id: str) -> bool:
    """成员权限检查。members 为 JSON: [{"user_id":..., "role":...}]。

    若账本未登记任何成员, 视为开放账本 (开发/自建环境默认), 以便本地联调。
    """
    row = get_book(book_id)
    if row is None:
        return False
    try:
        members = json.loads(row["members"] or "[]")
    except json.JSONDecodeError:
        members = []
    if not members:
        return True
    return any(m.get("user_id") == user_id for m in members)


def get_book_version(book_id: str) -> int:
    row = get_conn().execute(
        "SELECT version FROM book_version WHERE book_id = ?", (book_id,)
    ).fetchone()
    if row is None:
        return 1
    return int(row["version"])


def bump_book_version(book_id: str) -> int:
    """交易写入递增账本版本 (C147)。"""
    conn = get_conn()
    conn.execute(
        "INSERT INTO book_version (book_id, version, updated_at) VALUES (?, 1, ?) "
        "ON CONFLICT(book_id) DO UPDATE SET version = version + 1, updated_at = excluded.updated_at",
        (book_id, utc_now_iso()),
    )
    conn.commit()
    return get_book_version(book_id)


def get_dimension_version() -> int:
    row = get_conn().execute("SELECT version FROM dimension_version WHERE id = 1").fetchone()
    return int(row["version"]) if row else 1


def bump_dimension_version() -> int:
    """分类/标签/对象等全局维度变更递增, 用于跨账本缓存失效 (C147)。"""
    conn = get_conn()
    conn.execute(
        "UPDATE dimension_version SET version = version + 1, updated_at = ? WHERE id = 1",
        (utc_now_iso(),),
    )
    conn.commit()
    return get_dimension_version()


def current_snapshot_version(book_id: str) -> int:
    """账本快照版本 = 账本版本 * 1000 + 维度版本。

    维度版本放进同一个键, 可避免跨账本共享维度变更导致的缓存遗漏。
    """
    return get_book_version(book_id) * 1000 + get_dimension_version()


def resolve_snapshot_version(book_id: str, requested: Optional[int]) -> int:
    """校验客户端携带的 snapshot_version。

    - 未携带 -> 使用当前版本
    - 携带且等于当前 -> 通过
    - 携带但落后 -> 检查缓存中是否仍可读取该版本:
        * 可读 -> 通过 (旧版本结果仍可服务, 与 TECH 04 读取语义一致)
        * 不可读 -> 409 SNAPSHOT_STALE
    - 携带但超前 (不可能发生) -> 409
    """
    current = current_snapshot_version(book_id)
    if requested is None:
        return current
    requested = int(requested)
    if requested == current:
        return current
    if requested > current:
        raise_snapshot_stale(book_id, requested, current)
    # 落后版本: 若缓存里仍存在该版本的结果, 允许读取
    row = get_conn().execute(
        "SELECT 1 FROM statistic_cache WHERE book_id = ? AND version = ? LIMIT 1",
        (book_id, requested),
    ).fetchone()
    if row is None:
        raise_snapshot_stale(book_id, requested, current)
    return requested


def raise_snapshot_stale(book_id: str, requested: int, current: int) -> None:
    from .errors import SnapshotStale

    raise SnapshotStale(
        "快照版本已过期，请刷新统计视图或从第一页重查明细。",
        field="snapshot_version",
        reason=f"requested={requested}, current={current}",
        extra={"snapshot_version": current, "requested_version": requested},
    )


# ---------------------------------------------------------------------
# 缓存 (C81/C82/C83)
# ---------------------------------------------------------------------
def cache_key(book_id: str, query_key: str, version: int) -> str:
    return f"{book_id}|{version}|{query_key}"


def read_cache(book_id: str, query_key: str, version: int) -> Optional[Dict[str, Any]]:
    row = get_conn().execute(
        "SELECT payload FROM statistic_cache WHERE cache_key = ? AND expires_at > ?",
        (cache_key(book_id, query_key, version), utc_now_iso()),
    ).fetchone()
    if row is None:
        return None
    try:
        return json.loads(row["payload"])
    except json.JSONDecodeError:  # pragma: no cover
        return None


def write_cache(book_id: str, query_key: str, version: int, payload: Any) -> None:
    now = utc_now()
    expires = now + timedelta(seconds=CACHE_TTL_SECONDS)
    conn = get_conn()
    conn.execute(
        "INSERT INTO statistic_cache "
        "(cache_key, book_id, version, query_key, payload, created_at, expires_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(cache_key) DO UPDATE SET payload = excluded.payload, "
        "created_at = excluded.created_at, expires_at = excluded.expires_at",
        (
            cache_key(book_id, query_key, version),
            book_id,
            version,
            query_key,
            json.dumps(payload, ensure_ascii=False),
            now.isoformat(timespec="seconds"),
            expires.isoformat(timespec="seconds"),
        ),
    )
    conn.commit()


def invalidate_cache(book_id: Optional[str] = None) -> int:
    """主动失效: 交易变更按账本失效, 全局维度变更按全部账本失效。"""
    conn = get_conn()
    if book_id:
        cur = conn.execute("DELETE FROM statistic_cache WHERE book_id = ?", (book_id,))
    else:
        cur = conn.execute("DELETE FROM statistic_cache")
    conn.commit()
    return cur.rowcount


def purge_expired_cache() -> int:
    conn = get_conn()
    cur = conn.execute("DELETE FROM statistic_cache WHERE expires_at <= ?", (utc_now_iso(),))
    conn.commit()
    return cur.rowcount


# ---------------------------------------------------------------------
# 迁移异常清册 (D07)
# ---------------------------------------------------------------------
def record_issue(
    issue_type: str,
    entity: str,
    entity_id: str,
    detail: Optional[Dict[str, Any]] = None,
    book_id: Optional[str] = None,
    original_value: Optional[str] = None,
) -> None:
    import uuid

    conn = get_conn()
    conn.execute(
        "INSERT INTO migration_issue "
        "(id, issue_type, book_id, entity, entity_id, detail, original_value, status, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)",
        (
            "iss_" + uuid.uuid4().hex[:12],
            issue_type,
            book_id,
            entity,
            entity_id,
            json.dumps(detail or {}, ensure_ascii=False),
            original_value,
            utc_now_iso(),
        ),
    )
    conn.commit()


def list_issues(status: Optional[str] = None) -> List[sqlite3.Row]:
    if status:
        return list(
            get_conn().execute(
                "SELECT * FROM migration_issue WHERE status = ? ORDER BY issue_type, entity_id",
                (status,),
            )
        )
    return list(
        get_conn().execute("SELECT * FROM migration_issue ORDER BY issue_type, entity_id")
    )


def exec_many(sql: str, rows: Sequence[Sequence[Any]]) -> None:
    conn = get_conn()
    conn.executemany(sql, rows)
    conn.commit()


def fetch_all(sql: str, params: Iterable[Any] = ()) -> List[sqlite3.Row]:
    return list(get_conn().execute(sql, tuple(params)).fetchall())


def fetch_one(sql: str, params: Iterable[Any] = ()) -> Optional[sqlite3.Row]:
    return get_conn().execute(sql, tuple(params)).fetchone()
