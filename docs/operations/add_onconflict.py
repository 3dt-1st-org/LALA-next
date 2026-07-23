#!/usr/bin/env python3
"""pg_dump --column-inserts 결과의 각 INSERT 문 종료 ';' 앞에
' ON CONFLICT DO NOTHING' 을 붙여 additive upsert 덤프로 변환.

사용:
    python3 add_onconflict.py < dump_raw.sql > dump_upsert.sql

동기: --rows-per-insert=N 다중행 INSERT는 "기존 행과의 충돌"만 잡히고
"같은 배치 내 중복 unique-key"는 ON CONFLICT 가 못 잡는다. 따라서 적재 시
ON_ERROR_STOP=0 으로 해당 배치만 스킵하고 계속 진행하는 것을 권장.
"""

import sys

_SINGLE_QUOTE = "'"
_DOUBLE_QUOTE_ESC = "''"
_STATEMENT_END = ";"
_INSERT_PREFIX = "INSERT INTO"
_CONFLICT_CLAUSE = " ON CONFLICT DO NOTHING"


def transform(stdin: str) -> str:
    """각 INSERT 문에 ON CONFLICT DO NOTHING 을 부착해 반환한다."""
    output: list[str] = []
    current: list[str] = []
    in_single_quote = False
    index = 0
    length = len(stdin)

    while index < length:
        char = stdin[index]
        if char == _SINGLE_QUOTE:
            if in_single_quote and index + 1 < length and stdin[index + 1] == _SINGLE_QUOTE:
                current.append(_DOUBLE_QUOTE_ESC)
                index += 2
                continue
            in_single_quote = not in_single_quote
            current.append(char)
            index += 1
            continue
        if char == _STATEMENT_END and not in_single_quote:
            statement = "".join(current)
            stripped = statement.lstrip().upper()
            suffix = _CONFLICT_CLAUSE if stripped.startswith(_INSERT_PREFIX) else ""
            output.append(statement + suffix)
            output.append(_STATEMENT_END)
            current = []
            index += 1
            continue
        current.append(char)
        index += 1

    output.append("".join(current))
    return "".join(output)


def main() -> None:
    sys.stdout.write(transform(sys.stdin.read()))


if __name__ == "__main__":
    main()
