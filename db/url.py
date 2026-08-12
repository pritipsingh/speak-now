"""
Database URL
============
"""

from os import getenv
from urllib.parse import quote


def build_db_url() -> str:
    """Build database URL from environment variables.

    Prefers DATABASE_URL when set (Railway/Render/Fly inject it), normalizing the
    scheme to the psycopg driver agno uses. Falls back to the individual DB_* vars
    used by local Docker Compose.
    """
    url = getenv("DATABASE_URL")
    if url:
        if url.startswith("postgres://"):
            url = "postgresql://" + url[len("postgres://") :]
        if url.startswith("postgresql://"):
            url = "postgresql+psycopg://" + url[len("postgresql://") :]
        return url

    driver = getenv("DB_DRIVER", "postgresql+psycopg")
    user = getenv("DB_USER", "ai")
    password = quote(getenv("DB_PASS", "ai"), safe="")
    host = getenv("DB_HOST", "localhost")
    port = getenv("DB_PORT", "5432")
    database = getenv("DB_DATABASE", "ai")

    return f"{driver}://{user}:{password}@{host}:{port}/{database}"


db_url = build_db_url()
