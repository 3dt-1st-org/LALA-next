from __future__ import annotations

from datetime import datetime


def duration_ms(started_at: datetime, finished_at: datetime) -> int:
    return int((finished_at - started_at).total_seconds() * 1000)


def record_job_run(
    *,
    dsn: str,
    job_name: str,
    status: str,
    started_at: datetime,
    finished_at: datetime,
    duration_ms: int,
    error_message: str | None,
    connect_timeout: int,
) -> None:
    if not dsn:
        return

    import psycopg2

    sql = """
        INSERT INTO ops.job_runs (
            job_name,
            status,
            started_at,
            finished_at,
            duration_ms,
            error_message
        )
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (job_name, status, started_at, finished_at, duration_ms, error_message),
            )
        conn.commit()
