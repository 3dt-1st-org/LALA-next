# P6B 오프라인 테스트 가능한 도슨트 모델-저지 계약 + 비용 가드 — 2026-09-05

## 배경

P6A(정정 head `8f78f7a5`)까지 오프라인 도슨트 평가는 결정적(deterministic)
차원 감사까지만 갖추고 있었고, 모델-저지 스코어링(`docent_qa` LLM judge)은
"의도적으로 미구현"인 외부 게이트였다. P6B는 이걸 **오프라인에서 완전히
테스트 가능한 fail-closed 저지 경계 + 이중 게이트 + 유한 배치 정책**이라는
최소 일관 계약으로 만든 체크포인트다. P6A 동작(40 합성 장소 / 카테고리별
10개 / 정확 KO+EN 페어링 / 80 언어 케이스 / honest-empty / 라이브 클라이언트
금지 / 증거-게이트 감사 / 정리 산출물)은 한 글자도 바꾸지 않았다.

## 정확히 구현된 것

- **엄격한 저지 결과 계약** — `apps/api/app/services/docent_judge.py`(신규):
  정확히 하나의 전체 결정 `PASS`/`REWRITE` + 11개 차원(언어 순수성, 사실
  근거, 로컬 맥락, 페르소나 적합성, 실용 방문 안내, 안전/근거 없는 주장,
  소스 권리 주의, Markdown/TTS 적합성, 날씨 모순, 반복, 내부 점수 누출)
  각각 기계 판독 가능한 상태(`pass`/`flagged`)와 간결한 이유 코드.
  파싱은 엄격 fail-closed: 누락·비정형·중복·알 수 없음·비유한(non-finite)·
  범위 밖·모순된 필드(예: 어떤 차원이 flagged인데 decision=PASS)는 전부
  `REWRITE`로 폐쇄하고 기계 판독 가능한 실패 이유 코드를 남긴다.
  신뢰할 수 없는 페이로드의 차원 결과는 폐기된다.
- **역할 분리 해석** — 저지는 기존 `model_client.resolve("docent_qa")`로
  생성(docent) 역할과 분리해 해석한다(표준 OpenAI 방화벽 포함). 신규
  프로바이더·Azure 경로·raw-key 경로·직접 토큰 경로 없음.
- **라이브 저지 기본 OFF + 이중 게이트** — 프로덕션 호출은 기존 명시적
  라이브-AI 게이트(`LALA_ENABLE_LIVE_AI` + 키 + base-URL 방화벽)와 별도의
  `docent_qa_judge` 옵트인(`LALA_DOCENT_QA_JUDGE`, 기본 False — 기존
  레지스트리 항목, 플래그 코드 무변경)을 모두 요구한다. 라이브 클라이언트는
  이중 게이트 뒤 `build_live_provider` 안에서만 생성되며 `max_retries=0`
  (재시도로 지출이 배가되지 않음). 테스트·오프라인 평가기는 경계에서 페이크
  프로바이더를 주입해 네트워크/유료 호출 0회.
- **유한 배치 정책** — `JudgeBatchPolicy`(순수 데이터, 프로바이더 없이 독립
  단위 테스트 가능): 하드 최대 80 언어 레코드(기존 40장소×KO+EN 로스터,
  상향 불가), 나머지 이전 소량 시퀀셜 카나리, 유한 동시성(≤16), 레코드당
  타임아웃, 레코드당 정확히 1회 호출(자동 재시도 없음), 그리고 비정형 응답·
  반복 프로바이더 실패(타임아웃 포함)·누적 토큰 상한에 도달하면 배치를
  중단하는 stop-loss. 중단 시 미판정 레코드는 명시적으로 skipped 처리 —
  결코 조용한 pass 아님.
- **정리된 영속화만** — 결과 레코드는 정화된 신원(`eval_` 장소 ID + 언어),
  결정, 실패/에러 코드, 차원 상태 + 리덕션된 이유 코드, P6A sanitizer를
  재사용한 리덕션 발췌(동일한 240자 가시적 생략 경로), 집계 카운터만 담는다.
  원시 프로바이더 페이로드·원시 리뷰 텍스트·시크릿·개인정보·정밀 좌표·
  클라우드 식별자는 로그/영속화되지 않는다(모델이 이유 코드에 시크릿을
  실어 보내도 리덕션됨 — 테스트로 증명).
- **보고서의 별도 옵션 게이트** — 오프라인 QA 리포트에 `judge_gate` 섹션
  추가. 기본 `{"status": "NOT_RUN"}` — 결코 `PASS`가 아님.
  `run_docent_eval --judge-fake`는 커밋된 `FakeJudgeProvider`로 전체 저지
  파이프라인을 오프라인 실행(커밋된 fixture 기준 78 판정 / 2 honest-empty
  skip). 저지 게이트는 P6A 결정적 결과나 CLI exit code를 절대 바꾸지 않는다.

## 검증

```bash
uv run pytest apps/api/tests/test_docent_judge.py -p no:cacheprovider        # 109 passed (정정 후)
uv run pytest apps/api/tests -p no:cacheprovider                              # 전체 녹색
uv run python -m apps.api.app.tools.run_docent_eval                           # judge_gate=NOT_RUN passed=True
uv run python -m apps.api.app.tools.run_docent_eval --judge-fake              # judge_gate=SIMULATED (시뮬레이션 전용 표식)
uv run ruff check apps/api && uv run ruff format --check apps/api
uv run pre-commit run --all-files
git diff --check
```

- 변경 파일: `apps/api/app/services/docent_judge.py`(신규),
  `apps/api/tests/test_docent_judge.py`(신규, 93 테스트),
  `apps/api/app/tools/run_docent_eval.py`(판독 전용 추가: `judge_gate` 섹션 +
  `--judge-fake`), `docs/planning/v4-docent-qa-framework.md`(§8 + 소유 파일
  표), 이 devlog.
- 미변경: `docent_service.py`, `docent_quality_qa.py`, `docent_eval.py`,
  `docent_qa_dimensions.py`, `ai_service.py`, `run_docent_quality_qa.py`,
  feature flags, schemas/openapi, Flutter, 마이그레이션, 시크릿 baseline.
  P6A 테스트 2건(`test_docent_eval_harness.py`, `test_docent_qa_dimensions.py`)은
  무변경 그대로 녹색.

## 남아있는 별도 외부 게이트 (이 체크포인트에서 실행되지 않음)

1. **유료 카나리** — 이중 게이트 ON 상태에서 배포된 API 대상 유료 라이브
   저지 카나리 실행(stop-loss 하에서).
2. **실제 40장소/80스크립트 재생성** — 합성 로스터가 아닌 실제 프로덕션
   도슨트 스크립트(Lane C) 재생성 후 저지.
3. **수동 인간 QA** — 루브릭 기반 수동 검토(`docent-quality-manual-qa-strategy.md`).
4. **소스 권리 검토** — 라벨 존재 프록시를 넘어선 사용 가능성 검증.
5. **온디바이스 오디오 QA** — 음성 재생/스피치 QA(V4-B/V7).
6. **프로덕션 런타임 연결** — 저지 게이트의 프로덕션 런타임/라우팅 연결
   (현재 소비자는 오프라인 리포트 게이트뿐).

## 범위 정직성

오프라인 페이크 실행은 `SIMULATED`(`OFFLINE_FAKE`)로 명시 표시된다 — 시뮬레이션이므로
모델 품질에 대한 어떤 주장도 아니다. 라이브 `PASS`조차 좁은 구조화 판정일 뿐, 광역
사실 관계·콘텐츠 안전·소스 권리·프로덕션 준비 증명이 아니다 — 그 판단은 위 외부
게이트 소관이다.

## 정정 (2026-09-05, 독립 검증 verdict 반영)

독립 검증(`CORRECTION_REQUIRED`, head `0f3807fc` 대상)이 재현한 6개 결함을 후속
정정 커밋으로 반영했다(검증이 유지한다고 확인한 이중 게이트·재시도 금지·동시성
상한·stop-loss 순서·타임아웃 경계 표현·기본 CLI NOT_RUN은 그대로):

1. **honest-empty 사전-제출 스킵 (지출 결함)** — 기존 구현은 executor 제출
   *이후*에 빈 스크립트를 검사해, 카나리/나머지 어디에서든 빈 레코드가
   프로바이더 호출을 소비했다(배포 fixture의 honest-empty 쌍도 78회가 아닌
   80회 호출). 카나리와 나머지 웨이브 모두에서 제출 전에 분류·기록하고
   절대 제출하지 않도록 수정 — 프로바이더 호출 수 = 판정 가능 레코드 수.
   비-마지막 카나리 위치의 빈 레코드, 나머지 웨이브 내 다수 빈 레코드,
   fixture-형태 80-로스터(78 호출) 회귀 테스트 추가.
2. **통합 게이트의 조용한 PASS (게이트 결함)** — stop-loss 임계 밖의 프로바이더
   에러/타임아웃이 섞여 있어도 `PASS`가 나오던 것을 수정: 판정 가능한 in-cap
   레코드 전원이 유효 `PASS`이고 프로바이더 실패·타임아웃·미완료 outcome·
   halted 스킵·cap 탈락이 전혀 없을 때만 `PASS`. 혼합 PASS+에러는 명시적
   `INCOMPLETE`. honest-empty 스킵은 명시적이며 중립. 우선순위
   `REWRITE` > `HALTED` > `INCOMPLETE` > `PASS` > `NO_VERDICTS`.
3. **cap 탈락 fail-closed (게이트 결함)** — `dropped_by_cap > 0`이면 결코
   `PASS`가 아니라 `INCOMPLETE`. 기존 테스트가 위반 동작(85→80에서 PASS)을
   단언하고 있어 `INCOMPLETE` 기대로 교체.
4. **페이크 실행 SIMULATED 표식 (정직성 결함)** — `--judge-fake` 리포트가 실제
   저지 실행과 스키마상 구분 불가능했던 것을 수정: 최상위 `status: SIMULATED`,
   `provider: OFFLINE_FAKE`, `simulated: true`, 실제 집계는
   `simulated_result` 아래 중첩. CLI 요약도 `judge_gate=SIMULATED`. 최상위
   상태가 실제 게이트 `PASS`와 절대 같지 않으므로 페이크 실행이 실제
   모델-저지 승인 게이트를 충족하는 일은 없다. 기본 호출은 정확히
   `{"status": "NOT_RUN"}` 그대로.
5. **프로바이더 입력 정화/한계 (프롬프트 결함)** — 프롬프트가 원시 place_id,
   비정상 언어/카테고리, 비정화 스크립트(시크릿·좌표·이메일 포함)를 그대로
   실어 보내던 것을 수정: 원시 내부 place id는 미포함, 언어/카테고리는
   화이트리스트 라벨(벗어나면 `unknown`), 스크립트는 4000자 한계 적용 *전에*
   P6A 리덕션. 모든 공개 직렬화 경로(`JudgeResult.to_public_dict` 포함)가
   모델 작성 이유를 정화/생략.
6. **역방향 모순 fail-closed (계약 결함)** — 모든 차원이 `pass`인 `REWRITE`는
   근거가 없으므로 `PASS`+flagged와 동일한 안정 코드
   `contradictory_decision`으로 폐쇄. 양방향 테스트 추가.
   - 추천 항목도 반영: 프로바이더가 보고한 음수 토큰 사용량을 ≥0으로
     클램프(무효 타입은 0 처리)해 stop-loss 회계를 임의로 줄일 수 없게 함.
   - 타임아웃 표현은 정확히 유지: 배치 대기 타임아웃은 이미 실행 중인 호출을
     종료하지 않으며(스레드 생존), 라이브 클라이언트 자체 타임아웃이 권위적.

정정 후 테스트 109개(93 → 109), 전체 API 스위트 2181 passed, ruff/format/
pre-commit/git diff --check 모두 녹색.

## 최종 정정 (2026-09-05, 재검증 verdict 반영 — 공개 신원 직렬화)

재검증(수정 head `0cdcef94` 대상)은 6개 결함 중 5개 수정을 확인하고 남은
하나의 구현 가능한 결함을 지적했다: `JudgeRecordOutcome.to_public_dict`
(및 그 안에 outcome을 중첩하는 `JudgeBatchRun.summarize`)이 원시 내부
place_id(UUID형 포함)와 비제한 언어 문자열(10,000자 포함)을 그대로 내보낸
것. 단일 직렬화 초크 포인트에서 공개 신원 투영(projection)으로 수정했다:

- **place_id**: 확립된 `eval_` 네임스페이스의 엄격한 안전 신원(소문자 ASCII
  글자/숫자/언더스코어/하이픈, ≤64자)만 오프라인 추적성을 위해 유지.
  그 외 모든 신원(내부형·UUID형·안전하지 않은 문자셋·과장)은 상수 정직
  리덕션 마커 `internal_redacted`로 대체 — 원시 값도, 가역값도, 원시
  해시도 아님.
- **language**: 현행 40/80 저지 계약의 `ko`/`en`만 화이트리스트; 그 외
  또는 과장 값은 경계 리터럴 `unknown`.
- 원시 신원은 배치 회계(`_has_outcome`)를 위한 메모리 내 필드에만 존재;
  모든 공개/리포트 직렬화는 안전 투영을 통과.
- 회귀 테스트: 허용 `eval_` 신원 유지(outcome+summary), UUID형 신원
  리덕션, 과장(105자)·안전하지 않은 문자셋·비ASCII `eval_` 신원 리덕션,
  10,000자 언어 → `unknown`, 64자 경계 정확 분할.

게이트/타임아웃/페이크 시맨틱·`.secrets.baseline`·기타 파일은 무변경.
최종 정정 후 저지 테스트 114개(109 → 114), 전체 API 스위트 녹색.
