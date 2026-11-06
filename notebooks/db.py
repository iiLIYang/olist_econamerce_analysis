"""MySQL 连接与 SQL 执行工具，供 notebooks 复用。

凭据从项目根目录的 .env 读取（.env 已 gitignore）：
    DB_HOST / DB_PORT / DB_USER / DB_PASSWORD / DB_NAME
"""
from pathlib import Path
import os
import re
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine, text


def _find_project_root() -> Path:
    root = Path.cwd()
    while not (root / ".env").exists() and root != root.parent:
        root = root.parent
    return root


def _load_env() -> Path:
    root = _find_project_root()
    env_path = root / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    return root


PROJECT_ROOT = _load_env()
SQL_DIR = PROJECT_ROOT / "analysis_code"


def get_engine():
    user = os.getenv("DB_USER", "root")
    password = quote_plus(os.getenv("DB_PASSWORD", ""))
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "3306")
    db = os.getenv("DB_NAME", "olist")
    url = f"mysql+pymysql://{user}:{password}@{host}:{port}/{db}?charset=utf8mb4"
    return create_engine(url, pool_pre_ping=True)


def read_sql(sql: str) -> pd.DataFrame:
    """执行一条 SELECT 并返回 DataFrame。"""
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn)


def _strip_comments(sql: str) -> str:
    """去掉 `--` 和 `#` 行注释（本项目 SQL 里字符串不含这两种符号）。"""
    lines = []
    for line in sql.splitlines():
        line = re.sub(r"--.*$", "", line)
        line = re.sub(r"#.*$", "", line)
        lines.append(line)
    return "\n".join(lines)


def split_statements(sql: str) -> list[str]:
    cleaned = _strip_comments(sql)
    return [stmt.strip() for stmt in cleaned.split(";") if stmt.strip()]


def run_sql_file(path) -> list[pd.DataFrame]:
    """执行一个 .sql 文件里的所有语句，返回其中 SELECT 的结果（按出现顺序）。"""
    path = Path(path)
    engine = get_engine()
    results: list[pd.DataFrame] = []
    with engine.begin() as conn:
        for stmt in split_statements(path.read_text(encoding="utf-8")):
            if stmt.lstrip().lower().startswith(("select", "with")):
                results.append(pd.read_sql(text(stmt), conn))
            else:
                conn.execute(text(stmt))
    return results
