"""定点十进制金额工具。

C84: 人民币金额两位小数、千分位、规范负数格式, 使用 Decimal。
C87: 百分比统一保留两位小数。
所有金额一律走 Decimal, 禁止 float 参与金额运算。
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Optional

ZERO = Decimal("0")
CENT = Decimal("0.01")
HUNDRED = Decimal("100")


def to_decimal(value) -> Decimal:
    """把任意输入安全地转换为 Decimal (拒绝 float 直转带来的二进制误差)。"""
    if isinstance(value, Decimal):
        return value
    if isinstance(value, int):
        return Decimal(value)
    if isinstance(value, float):
        # float 只允许出现在入口边界, 用 repr 转成最接近的十进制字面量
        return Decimal(repr(value))
    if value is None:
        raise ValueError("金额不能为空")
    text = str(value).strip()
    if not text:
        raise ValueError("金额不能为空")
    try:
        return Decimal(text)
    except InvalidOperation as exc:  # pragma: no cover - 防御性
        raise ValueError(f"非法金额: {text}") from exc


def quantize_money(value: Decimal) -> Decimal:
    """金额统一量化到两位小数, 使用 ROUND_HALF_UP (D06 建议舍入方式)。"""
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def quantize_percent(value: Optional[Decimal]) -> Optional[Decimal]:
    """百分比统一保留两位小数 (C87)。None 表示不可计算, 客户端显示「—」。"""
    if value is None:
        return None
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def money_str(value: Optional[Decimal]) -> Optional[str]:
    """金额 -> 十进制字符串 (单位: 元), 不含千分位 (千分位由展示层处理)。"""
    if value is None:
        return None
    return format(quantize_money(value), "f")


def percent_str(value: Optional[Decimal]) -> Optional[str]:
    """百分比 -> 十进制字符串 (单位: 百分数, 即 70.00 表示 70%)。"""
    if value is None:
        return None
    return format(quantize_percent(value), "f")


def group_money(value: Optional[Decimal]) -> Optional[str]:
    """带千分位的金额展示串, 例如 12345.6 -> '12,345.60'。"""
    if value is None:
        return None
    q = quantize_money(value)
    negative = q < ZERO
    if negative:
        q = -q
    text = format(q, "f")
    int_part, _, frac = text.partition(".")
    sign = "-" if negative else ""
    chunks = []
    while len(int_part) > 3:
        chunks.insert(0, int_part[-3:])
        int_part = int_part[:-3]
    chunks.insert(0, int_part)
    return f"{sign}{','.join(chunks)}.{frac}"


def safe_ratio(numerator: Decimal, denominator: Decimal) -> Optional[Decimal]:
    """占比 = 分子 / 分母 * 100; 分母为 0 返回 None (客户端显示「—」)。"""
    if denominator == ZERO:
        return None
    return numerator / denominator * HUNDRED
