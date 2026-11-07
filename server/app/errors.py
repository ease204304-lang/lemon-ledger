"""统一错误契约 (TECH 03 表 3)。

    400 INVALID_FILTER    日期逆序、未来日期、维度类型不符、SELECTED 未传 ID
    403 BOOK_FORBIDDEN    当前用户无该账本权限
    409 SNAPSHOT_STALE    请求版本已过期且无法读取该版本
    503 STATS_UNAVAILABLE 统计暂不可用 (返回可排查的请求标识, 允许重试)

错误响应体统一为:
    {
      "error": {
        "code": "INVALID_FILTER",
        "message": "...",
        "field": "start_date",
        "reason": "...",
        "request_id": "req_..."
      }
    }
"""

from __future__ import annotations

import uuid
from typing import Any, Dict, Optional

from fastapi import Request
from fastapi.responses import JSONResponse


def new_request_id() -> str:
    """生成可排查的请求标识 (TECH 03: 503 返回可供排查的请求标识)。"""
    return "req_" + uuid.uuid4().hex[:16]


class ApiError(Exception):
    """业务错误基类。"""

    status_code: int = 400
    code: str = "INVALID_FILTER"

    def __init__(
        self,
        message: str,
        *,
        field: Optional[str] = None,
        reason: Optional[str] = None,
        code: Optional[str] = None,
        status_code: Optional[int] = None,
        extra: Optional[Dict[str, Any]] = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.field = field
        self.reason = reason
        if code:
            self.code = code
        if status_code:
            self.status_code = status_code
        self.extra = extra or {}


class InvalidFilter(ApiError):
    """400 INVALID_FILTER。"""

    status_code = 400
    code = "INVALID_FILTER"


class BookForbidden(ApiError):
    """403 BOOK_FORBIDDEN —— 当前用户无该账本权限。"""

    status_code = 403
    code = "BOOK_FORBIDDEN"


class SnapshotStale(ApiError):
    """409 SNAPSHOT_STALE —— 请求版本已过期且无法读取该版本。"""

    status_code = 409
    code = "SNAPSHOT_STALE"


class StatsUnavailable(ApiError):
    """503 统计暂不可用 —— 临时聚合失败, 客户端允许重试。"""

    status_code = 503
    code = "STATS_UNAVAILABLE"


def error_body(exc: ApiError, request_id: str) -> Dict[str, Any]:
    body: Dict[str, Any] = {
        "error": {
            "code": exc.code,
            "message": exc.message,
            "request_id": request_id,
        }
    }
    if exc.field:
        body["error"]["field"] = exc.field
    if exc.reason:
        body["error"]["reason"] = exc.reason
    if exc.extra:
        body["error"].update(exc.extra)
    return body


async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    request_id = getattr(request.state, "request_id", None) or new_request_id()
    return JSONResponse(
        status_code=exc.status_code,
        content=error_body(exc, request_id),
        headers={"X-Request-Id": request_id},
    )


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    """未捕获异常统一转成 503 统计暂不可用, 避免 500 泄漏堆栈。"""
    request_id = getattr(request.state, "request_id", None) or new_request_id()
    return JSONResponse(
        status_code=503,
        content={
            "error": {
                "code": "STATS_UNAVAILABLE",
                "message": "统计暂不可用，请稍后重试。",
                "reason": type(exc).__name__,
                "request_id": request_id,
            }
        },
        headers={"X-Request-Id": request_id},
    )
