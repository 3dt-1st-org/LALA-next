"""scripts/patch_dart_dio_serializers.py 단위 계약(CP1 검증 정정 D1).

실제 generator/openapi-generator·Java·네트워크 없이, 패치 스크립트의 5가지
변환 규칙과 멱등성(2회차 실행 무변경)을 tmp_path 픽스처로 직접 검증한다.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = ROOT / "scripts" / "patch_dart_dio_serializers.py"

# 실제 dart-dio 7.12 출력 형태를 재현한 최소 픽스처(case 블록별 스코프):
# - (5) cast 없는 대입 → 그대로(가장 먼저 등장해야 last_cast 오염이 없다).
# - (1) nullable nested cast + raw 대입 → toBuilder 필요.
# - (2) scalar anyOf cast + 과다 toBuilder → 원본 대입 복원.
# - (3) non-nullable nested cast + raw 대입 → toBuilder 필요.
# - (4) 정수 enum 기본값 const E._(E.number30) → 'number30'.
FIXTURE = """\
class PlanPreferenceContext
    implements Built<PlanPreferenceContext, PlanPreferenceContextBuilder> {
  int get placeholder;
}

class Coordinate implements Built<Coordinate, CoordinateBuilder> {
  int get placeholder;
}

void deserializeVariants(DailyPlanRequestBuilder result) {
  // (5) cast 없는 대입(conv) → 변경 금지.
  result.existingValue = valueDes;
  switch (key) {
    case r'preference_context':
      // (1) nullable nested cast + raw assign → toBuilder().
      final valueDes = serializers.deserialize(
        value,
        specifiedType: const FullType.nullable(PlanPreferenceContext),
      ) as PlanPreferenceContext?;
      if (valueDes == null) continue;
      result.preferenceContext = valueDes;
      break;
    case r'recommendation_reason':
      // (2) scalar anyOf cast + generator 과다 toBuilder → plain assignment.
      final valueDes = serializers.deserialize(
        value,
        specifiedType: const FullType.nullable(String),
      ) as String?;
      if (valueDes == null) continue;
      result.recommendationReason = valueDes.toBuilder();
      break;
    case r'center':
      // (3) non-nullable nested cast + raw assign → toBuilder().
      final valueDes = serializers.deserialize(
        value,
        specifiedType: const FullType(Coordinate),
      ) as Coordinate;
      result.center = valueDes;
      break;
  }
}

class PlanPreferenceContextMaxOneWayMinutesEnum extends EnumClass {
  const PlanPreferenceContextMaxOneWayMinutesEnum._(String name) : super(name);
}

void defaults(PlanPreferenceContextBuilder b) => b
    // (4) 정수 enum 기본값 버그(실제 generator 출력은 한 줄).
    ..maxOneWayMinutes = const PlanPreferenceContextMaxOneWayMinutesEnum._(PlanPreferenceContextMaxOneWayMinutesEnum.number30);
"""


def _load_patch_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("patch_dart_dio_serializers", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _patched_content(tmp_path: Path, module: ModuleType) -> str:
    model_dir = tmp_path / "model"
    model_dir.mkdir()
    fixture = model_dir / "daily_plan_request.dart"
    fixture.write_text(FIXTURE, encoding="utf-8")
    built_models = module.collect_built_models(model_dir)
    assert "PlanPreferenceContext" in built_models
    assert "Coordinate" in built_models
    changed = module.patch_file(fixture, built_models)
    assert changed is True
    return fixture.read_text(encoding="utf-8")


def test_patch_rules_and_idempotence(tmp_path: Path) -> None:
    module = _load_patch_module()
    content = _patched_content(tmp_path, module)

    # (1) nullable nested cast → toBuilder (과거 `?` suffix 로 누락되던 경로).
    assert "result.preferenceContext = valueDes.toBuilder();" in content
    # (2) scalar cast + 과다 toBuilder → 원본 대입 복원.
    assert "result.recommendationReason = valueDes;" in content
    assert "result.recommendationReason = valueDes.toBuilder();" not in content
    # (3) non-nullable nested cast → toBuilder.
    assert "result.center = valueDes.toBuilder();" in content
    # (4) 정수 enum 기본값 → 생성된 name 문자열 리터럴(한 줄 형태만 해당).
    assert "const PlanPreferenceContextMaxOneWayMinutesEnum._('number30')" in content
    assert "PlanPreferenceContextMaxOneWayMinutesEnum.number30);" not in content
    # (5) cast 없는 대입은 그대로.
    assert "result.existingValue = valueDes;" in content

    # 멱등성: 같은 입력에 2회차 패치는 무변경.
    fixture = tmp_path / "model" / "daily_plan_request.dart"
    built_models = module.collect_built_models(tmp_path / "model")
    assert module.patch_file(fixture, built_models) is False
    assert fixture.read_text(encoding="utf-8") == content
