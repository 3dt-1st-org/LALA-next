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
# 후행 cast 캡처. dart-dio 7.12 는 nullable 필드에 `as Foo?;` 를 내므로
# 후행 `?` 는 제거해서 모델명과 비교한다( CP1: 이 `?` 처리가 빠지면
# PlanPreferenceContext? 등 nested 모델이 패치되지 않고 invalid_assignment 잔존).
CAST_RE = re.compile(r"\)\s+as\s+([A-Za-z0-9_<>,\s]+?)\s*\??\s*;\s*$")
ASSIGN_RE = re.compile(r"^(\s*)result\.(\w+)\s*=\s*valueDes(?:\.toBuilder\(\))?\s*;\s*$")
# dart-dio 7.12 버그: 정수 enum 기본값을 `const E._(E.number30)` 형태로 내서
# String name 파라미터에 enum 상수를 넘긴다(const_constructor_param_type_mismatch).
# built_value 가 생성하는 실제 name 문자열('number30')로 바로잡는다.
INT_ENUM_DEFAULT_RE = re.compile(r"(const\s+\w+Enum\._\()\w+\.(number\d+)(\))")


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
            last_cast = cast.group(1).strip().split("<")[0].removesuffix("?").strip()
        assign = ASSIGN_RE.match(line)
        if assign and last_cast is not None:
            indent, field = assign.group(1), assign.group(2)
            # BuiltValue 모델 필드는 toBuilder 필수(generator 누락 버그 #21837),
            # 반대로 scalar/enum/Date 등은 원본 대입을 유지해야 한다 — dart-dio 가
            # anyOf nullable 필드에 대해 scalar 에도 toBuilder 를 과다 생성하는
            # 버그를 되돌린다(스크립트 문서화 동작: "primitive 는 원본 대입 유지").
            desired = (
                f"{indent}result.{field} = valueDes.toBuilder();"
                if last_cast in built_models
                else f"{indent}result.{field} = valueDes;"
            )
            if line != desired:
                line = desired
                changed = True
        fixed = INT_ENUM_DEFAULT_RE.sub(r"\1'\2'\3", line)
        if fixed != line:
            line = fixed
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
