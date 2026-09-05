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
  pass 아님. **grounding은 증거-게이트**: `grounding_count` 증거가 없으면
  `not_applicable`, 명시적 0/무효 값은 `flagged`, pass는 양수 증거일 때만.
  오프라인 harness는 각 fixture의 `grounding_anchors` 개수를 언어 케이스
  기록으로 결정적으로 전달하므로 78개 생성 케이스의 grounding pass는 전부
  양수 앵커 증거에 뿌리내린다(정정 반영).
- **범위 정직성**: 각 오프라인 감사는 자기 이름의 좁은 대리 지표만 증명한다 —
  `safety` = 시크릿류 부재, `hallucination` = 원시 점수 누출 부재,
  `source_attribution` = 정상 라벨 존재. 정규식 비-매칭이 광역 콘텐츠 안전·
  사실 관계·소스 권리를 증명하지 않는다; 그 판단은 아래 외부 게이트 소관.
- **반복 검사**: 문장 정규화 후 정확 중복 + 토큰 윈도우(4어절, 축약 길이
  ≥12자) 구두 반복. 짧은/흔한 표현("네.", "좋습니다.", "Yes.")은 축약 길이
  바닥(문장 ≥10자)으로 인해 절대 오탐 없음. 스캔은 20,000자로 선형 바운드 +
  결정적. 적대적 테스트 포함(중복 문장 감지, 입자 무시, 문장 간 구두 반복,
  경계 밖 중복 미감지).
- **Sanitizer/리포트 스키마**: 모든 차원이 pass/flagged/not_applicable
  3개 카운트를 유지(마크다운 표 포함). 정리 산출물은 판정/이유 코드와
  **눈에 보이게 생략 표시된 리덕션 발췌**(스크립트당 최대 첫 240자, 짧은
  스크립트도 최소 1자 이상 항상 생략 — 바이트 단위 전체 스크립트와 절대
  동일하지 않음)만 담는다. 발췌와 수동 메모에서 시크릿류·좌표 쌍·이메일·
  전화번호는 `[redacted]` 처리. 단, 정리 산출물이 원본 텍스트 0자를 담는
  것은 아니다(리덕션된 발췌는 남음). 원본 실행 리포트는 기존대로
  gitignored `output/local/` 에만 존재(정정 반영).
- **오프라인 가드 유지**: `offline_openai_guard` 하에서 라이브 OpenAI 클라이언트
  생성 0회 미검출 시 리포트 실패. honest-empty는 `DOCENT_CONTEXT_REQUIRED`
  정직 미생성 경로 유지.

## 남아있는 별도 외부 게이트 (이 체크포인트 범위 아님)

1. 유료 라이브 생성 (Lane C runner, 상한 관리).
2. 모델-저지 스코어링 (`docent_qa` LLM judge — P6A에서 의도적으로 미구현),
   원시 점수 프록시를 넘어선 광역 사실-환각 검토 포함.
3. 시크릿 누출 프록시를 넘어선 광역 콘텐츠 안전 검토 (수동/모델 게이트).
4. 라벨 존재 프록시를 넘어선 소스 권리/사용 가능성 검증 (수동 게이트).
5. 음성 재생/온디바이스 스피치 QA (V4-B/V7).
6. 수동 인간 루브릭 QA (`docs/operations/docent-quality-manual-qa-strategy.md`).

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

## 정정 (2026-09-05, 독립 검증 verdict 반영)

독립 검증(`CORRECTION_REQUIRED`, head `15ed04ca` 대상)이 지적한 두 실제
결함을 후속 정정 커밋으로 반영했다(40/80·카테고리 균형·honest-empty·
라이브 클라이언트 금지·반복 검사·비관련 코드는 모두 유지):

1. **Grounding 조용한 pass (계약 결함)** — `audit_grounding`이
   `grounding_count` 부재 시 `pass`를 내던 동작을 `not_applicable`
   (`no_grounding_metadata`)로 교정. 오프라인 harness가 fixture의
   `grounding_anchors` 개수를 언어 케이스 기록에 전달해 78개 생성
   grounding pass를 양수 앵커 증거로 뒷받침(없으면 N/A, 명시적 0이면
   FLAGGED). 부재-증거 PASS를 못박던 테스트는 N/A 기대로 교체.
2. **정리 산출물 경계 (정직성 갭)** — `script_excerpt`가 짧은 스크립트에서
   전체와 바이트 동일해지던 문제를 가시적 생략 표시로 해결(항상 1자 이상
   생략 + " ..." 접미). 발췌/수동 메모에 좌표 쌍·이메일·전화번호 리덕션
   추가("PM10 30, PM2.5 12" 등 템플릿 텍스트는 비-매칭 유지). 적대적
   테스트 추가(짧은 전체-동일 방지, 좌표/이메일/전화/수동 메모).
3. **범위 표현 정직화** — 위 본문/기획 문서의 광역 안전·사실 관계·소스
   권리 주장 문구와 "원본 텍스트 절대 미포함" 표현을 좁은 프록시 범위와
   "리덕션 발췌 잔존" 명시로 교정.
