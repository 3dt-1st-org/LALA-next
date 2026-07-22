#!/usr/bin/env bash
# FastAPI OpenAPI 스펙에서 Dart(dio) 클라이언트를 자동 생성한다.
# SSOT: openapi.json 이 유일 원천 → clients/flutter_generated/ 에 dart-dio 패키지 생성.
#
# 사용: bash scripts/generate_dart_client.sh [openapi.json 경로]
#   (경로 생략 시 artifacts/openapi/lala-next-openapi.json 사용, 없으면 in-process export)
#
# 요구: Java 17+ (JAVA_HOME 미설정 시 /usr/libexec/java_home -v 17 사용), Node/npx.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  [ -n "$JAVA_HOME" ] && export JAVA_HOME
fi
export PATH="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}/bin:${PATH}"

SPEC="${1:-$REPO_ROOT/artifacts/openapi/lala-next-openapi.json}"
OUT="$REPO_ROOT/clients/flutter_generated"

if [ ! -f "$SPEC" ]; then
  echo ">> OpenAPI 스펙이 없어 in-process export: $SPEC"
  bash "$REPO_ROOT/scripts/unix/export_openapi.sh" --in-process --output "$SPEC"
fi

echo ">> dart-dio 클라이언트 생성: $SPEC -> $OUT"
npx --yes "@openapitools/openapi-generator-cli" generate \
  -i "$SPEC" \
  -g dart-dio \
  -o "$OUT" \
  --additional-properties packageName=lala_next_flutter_client_generated,pubName=lala_next_flutter_client_generated,nullSafety=true,dateLibrary=core \
  --skip-validate-spec

echo ">> dart pub get + build_runner (built_value serializer .g.dart 생성)"
( cd "$OUT" && dart pub get && dart run build_runner build --delete-conflicting-outputs )

echo ">> 완료. 생성물: $OUT"
echo ">> 참고: openapi-generator dart-dio 의 known serializer 버그(nested model -> XBuilder?"
echo "   invalid_assignment) 로 현재 생성 코드에 컴파일 에러가 잔존한다. B1.3 PoC / B4 전환 전에"
echo "   생성기 수정 또는 툴 전환(swagger_dart_code_generator 등)이 필요."
echo "   clients/flutter_generated/ 는 .gitignore 처리(재생성 가능)."
