#!/usr/bin/env python3
"""openapi-generator dart-dio 의 known serializer 버그 후처리 패치.

배경: dart-dio(generator 7.12.0) 가 내는 built_value 표준 JSON 역직렬화 코드에서
nested BuiltValue 모델 필드에 대해 `result.<field> = valueDes;` 를 내는데, builder 필드는
`<Type>Builder?` 를 기대해 invalid_assignment 컴파일 에러가 발생한다
(https://github.com/OpenAPITools/openapi-generator/issues/21837, #9082).

본 패치는 **실제 BuiltValue 모델**(`implements Built<X, XBuilder>` 인 클래스) 필드에 한해
`valueDes.toBuilder()` 로 고친다. EnumClass(enum), Date, primitive 등은 원본 대입을 유지.
(generator 버전을 openapitools.json 으로 고정해 출력이 결정론적.)

사용: python3 scripts/patch_dart_dio_serializers.py [model_dir]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# BuiltValue 모델 클래스 정의 매칭: class Foo ... implements Built<Foo, FooBuilder>
BUILT_RE = re.compile(r"class\s+(\w+)\b[^{]*\bimplements\s+Built<")
CAST_RE = re.compile(r"\)\s*as\s+([A-Za-z0-9_<>,\s]+?)\s*;\s*$")
ASSIGN_RE = re.compile(r"^(\s*)result\.(\w+)\s*=\s*valueDes\s*;\s*$")


def collect_built_models(root: Path) -> set[str]:
    """생성된 모델 중 실제 BuiltValue 모델(toBuilder 보유) 이름을 수집한다."""
    models: set[str] = set()
    for p in root.rglob("*.dart"):
        for m in BUILT_RE.finditer(p.read_text(encoding="utf-8")):
            models.add(m.group(1))
    return models


def patch_file(path: Path, built_models: set[str]) -> bool:
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    out: list[str] = []
    last_cast: str | None = None
    changed = False
    for line in lines:
        cast = CAST_RE.search(line)
        if cast:
            last_cast = cast.group(1).strip().split("<")[0].strip()
        assign = ASSIGN_RE.match(line)
        if assign and last_cast in built_models:
            indent, field = assign.group(1), assign.group(2)
            line = f"{indent}result.{field} = valueDes.toBuilder();"
            changed = True
        out.append(line)
    if changed:
        path.write_text("\n".join(out), encoding="utf-8")
    return changed


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "clients/flutter_generated/lib/src/model")
    built_models = collect_built_models(root)
    print(f"detected {len(built_models)} BuiltValue models")
    patched = sum(1 for p in root.rglob("*.dart") if patch_file(p, built_models))
    print(f"patched {patched} files under {root}")


if __name__ == "__main__":
    main()
