# P6A 오프라인 도슨트 QA 파운데이션 (40 places / 80 cases) — 2026-09-05

## 배경

Draft #187 head(`4111feb5`)까지의 오프라인 도슨트 평가는 35개 장소 / 70개 언어
케이스였고, Lane C 산출물의 결정적(deterministic) QA 차원 중 소스 귀속·로컬
맥락·반복 검사는 증거 없이 "전부 not-applicable"로만 집계되었으며
`dimension_flags` 스키마는 not-applicable 개수를 버렸다. P6A는 이걸 정확히
**커밋된 40/80 파운데이션 + 기계 검증 가능한 정직한 차원 회계**로 만든
최소 체크포인트다.

## 정확한 상태 (이 변경 이후)

- **오프라인 40/80 재현 가능.**
  `apps/api/tests/fixtures/docent_eval_places.json` = 정확히 40개 합성
  `eval_` 장소(4개 카테고리 각 10개, honest-empty 1개 포함, 전 지역 맥락 유지).
  모든 장소가 정확히 `["ko","en"]` → 정확히 80개 언어 케이스.
- `docent_eval.evaluate_docent` 가 `total_places == 40`,
  `total_language_cases == 80`(언어별 분해 포함)을 노출·검증하고,
  KO+EN 정확 페어링이 깨진 fixture는 실패시킨다. 장소 수를 스크립트 수로
  치환하지 않는다(별도 필드).
- **결정적 차원 강화** — `apps/api/app/services/docent_qa_dimensions.py`(신규):
  레코드 내 이미 존재하는 증거(스크립트 텍스트, 소스 라벨, 그라운딩 메타,
  precheck issue_tags)만으로 source attribution / local context / language
  purity / usefulness / safety / repetition (+ grounding / advertising leakage /
  hallucination)를 감사. 판정은 pass / flagged / not_applicable 뿐.
  증거가 부족하면 명시적으로 `not_applicable`(이유 코드 포함) — 결코 조용한
  pass 아님.
- **반복 검사**: 문장 정규화 후 정확 중복 + 토큰 윈도우(4어절, 축약 길이
  ≥12자) 구두 반복. 짧은/흔한 표현("네.", "좋습니다.", "Yes.")은 축약 길이
  바닥(문장 ≥10자)으로 인해 절대 오탐 없음. 스캔은 20,000자로 선형 바운드 +
  결정적. 적대적 테스트 포함(중복 문장 감지, 입자 무시, 문장 간 구두 반복,
  경계 밖 중복 미감지).
- **Sanitizer/리포트 스키마**: 모든 차원이 pass/flagged/not_applicable
  3개 카운트를 유지(마크다운 표 포함). 정리 산출물은 판정/이유 코드와
  리덕션된 짧은 발췌만 담고, 원본 스크립트·리뷰·PII·좌표·프롬프트·토큰·
  시크릿·클라우드 식별자는 절대 포함하지 않는다.
- **오프라인 가드 유지**: `offline_openai_guard` 하에서 라이브 OpenAI 클라이언트
  생성 0회 미검출 시 리포트 실패. honest-empty는 `DOCENT_CONTEXT_REQUIRED`
  정직 미생성 경로 유지.

## 남아있는 별도 외부 게이트 (이 체크포인트 범위 아님)

1. 유료 라이브 생성 (Lane C runner, 상한 관리).
2. 모델-저지 스코어링 (`docent_qa` LLM judge — P6A에서 의도적으로 미구현).
3. 음성 재생/온디바이스 스피치 QA (V4-B/V7).
4. 수동 인간 루브릭 QA (`docs/operations/docent-quality-manual-qa-strategy.md`).

## 검증

```bash
uv run pytest apps/api/tests -p no:cacheprovider          # 전체 녹색
uv run python -m apps.api.app.tools.run_docent_eval        # places=40 language_cases=80 ... passed=True
uv run ruff check apps/api && uv run ruff format --check apps/api
uv run pre-commit run --all-files
git diff --check
```

- 평가 리포트 차원 회계(커밋된 fixture): 78개 생성 케이스 pass,
  2개 honest-empty 언어 케이스 not_applicable, flagged 0 (전 차원).
- 변경 파일: fixture(+5 레코드), `docent_eval.py`, `docent_qa_dimensions.py`(신규),
  `run_docent_eval.py`, `sanitize_docent_qa_report.py`, 테스트 2건,
  `docs/planning/v4-docent-qa-framework.md`, 이 devlog.
- 미변경: `docent_service.py`, `docent_quality_qa.py`, Flutter/생성 클라이언트,
  feature flags, secrets baseline, 마이그레이션.
