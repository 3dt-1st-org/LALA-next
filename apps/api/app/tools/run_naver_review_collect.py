"""Naver Search API review/mention collection tool."""

from __future__ import annotations

import argparse
import json
import os

CONFIRM_TEXT = "APPLY_NAVER_REVIEW_COLLECT"
ALLOW_ENV = "ALLOW_NAVER_REVIEW_COLLECT_APPLY"


def main(argv=None):
    p = argparse.ArgumentParser(description="Collect mentions from Naver Search API.")
    p.add_argument("--json", action="store_true")
    p.add_argument("--preview", action="store_true")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--confirm", default="")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--display", type=int, default=5)
    p.add_argument("--connect-timeout", type=int, default=5)
    a = p.parse_args(argv)
    if not a.preview and not a.apply:
        print(json.dumps({"ok": False, "error": "Use --preview or --apply."}))
        return 2
    if a.apply and (a.confirm != CONFIRM_TEXT or os.getenv(ALLOW_ENV) != "1"):
        print(
            json.dumps(
                {"ok": False, "error": f"--apply needs --confirm {CONFIRM_TEXT} and {ALLOW_ENV}=1"}
            )
        )
        return 2
    from contextlib import closing

    import psycopg2

    from apps.api.app.services import naver_search_service

    dsn = os.getenv("DB_DSN")
    if not dsn:
        print(json.dumps({"ok": False, "error": "DB_DSN not set"}))
        return 2
    with closing(psycopg2.connect(dsn, connect_timeout=a.connect_timeout)) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT place_id, name_ko FROM travel.places ORDER BY place_id LIMIT %s", (a.limit,)
            )
            places = cur.fetchall()
    total_c = total_i = 0
    for _pid, name in places:
        if not name or len(name) < 2:
            continue
        results = naver_search_service.collect_mentions_for_place(name, display=a.display)
        total_c += len(results)
        if a.preview:
            for r in results[:2]:
                print(
                    json.dumps(
                        {"place": name[:20], "provider": r.provider, "title": (r.title or "")[:50]},
                        ensure_ascii=False,
                    )
                )
        if a.apply and results:
            with closing(psycopg2.connect(dsn, connect_timeout=a.connect_timeout)) as conn:
                with conn.cursor() as cur:
                    for r in results:
                        cur.execute(
                            "INSERT INTO community.posts (provider, external_key, keyword, title, body, post_url, created_at_source) VALUES (%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (external_key) DO NOTHING",
                            (
                                r.provider,
                                r.external_key,
                                r.keyword,
                                r.title,
                                r.body,
                                r.post_url,
                                r.created_at_source,
                            ),
                        )
                    conn.commit()
                    total_i += len(results)
    print(
        json.dumps(
            {
                "ok": True,
                "mode": "apply" if a.apply else "preview",
                "places": len(places),
                "collected": total_c,
                "inserted": total_i,
            }
        )
    )
    return 0
