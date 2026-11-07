"""小猪记账 · 记账统计模块 服务端 (W1 数据层 + W2 计算与接口)。

模块划分:
    db.py       SQLite 连接、建表、版本管理、缓存读写
    models.py   Pydantic 请求/响应模型
    filters.py  统一条件解析器 (生成规范化查询键与 SQL 谓词)
    calc.py     聚合计算核心 (Decimal 定点十进制)
    errors.py   统一错误契约 (400/403/409/503)
    routers/    7 个统计/明细接口
"""

__version__ = "0.9.0"
