#!/usr/bin/env python3
"""pg_dump --column-inserts 결과의 각 INSERT 문 종료 ';' 앞에
' ON CONFLICT DO NOTHING' 을 붙여 additive upsert 덤프로 변환.
사용: python3 add_onconflict.py < dump_raw.sql > dump_upsert.sql
동기: --rows-per-insert=N 다중행 INSERT는 "기존 행과의 충돌"만 잡히고
"같은 배치 내 중복 unique-key"는 ON CONFLICT가 못 잡음 → load 시 ON_ERROR_STOP=0 권장.
"""
import sys

inp = sys.stdin.read()
out, stmt, in_sq, i, n = [], [], False, 0, len(inp)
while i < n:
    ch = inp[i]
    if ch == "'":
        if in_sq and i + 1 < n and inp[i + 1] == "'":
            stmt.append("''"); i += 2; continue
        in_sq = not in_sq; stmt.append(ch); i += 1; continue
    if ch == ";" and not in_sq:
        s = "".join(stmt)
        out.append(s + (" ON CONFLICT DO NOTHING" if s.lstrip().upper().startswith("INSERT INTO") else ""))
        out.append(";"); stmt = []; i += 1; continue
    stmt.append(ch); i += 1
out.append("".join(stmt))
sys.stdout.write("".join(out))
