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
uv run pytest apps/api/tests/test_docent_judge.py -p no:cacheprovider        # 93 passed
uv run pytest apps/api/tests -p no:cacheprovider                              # 전체 녹색
uv run python -m apps.api.app.tools.run_docent_eval                           # judge_gate=NOT_RUN passed=True
uv run python -m apps.api.app.tools.run_docent_eval --judge-fake              # judge_gate=PASS (78 judged / 2 skipped_no_script)
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

오프라인 페이크의 `PASS`는 모델 품질에 대한 어떤 주장도 아니다. 라이브
`PASS`조차 좁은 구조화 판정일 뿐, 광역 사실 관계·콘텐츠 안전·소스 권리·
프로덕션 준비 증명이 아니다 — 그 판단은 위 외부 게이트 소관이다.
