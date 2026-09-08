# 원격 브랜치 정리 · 2026-09-09

상태: 삭제 대상 검증 완료. 복구 태그와 이 문서를 먼저 원격에 보존한 뒤 삭제한다.

## 1. 범위와 판정

원격 브랜치 68개와 PR 이력 203개를 확인했다. 삭제 대상은 34개, 보존 대상은 34개다.

- main·dev·현재 준비 브랜치와 열린 PR #187·#206의 head/base는 남긴다.
- main 또는 보존한 9/7 후보에 포함된 커밋은 병합된 것으로 판정한다.
- squash 병합은 현재 브랜치 head가 MERGED PR의 head와 같은지 확인한다.
- 중간 통합 브랜치로 병합된 경우 그 통합 브랜치의 main 병합까지 추적한다.
- PR이 닫혔다는 사실만으로 삭제하지 않는다. 병합 뒤 head가 바뀐 브랜치도 추가 근거 없이는 남긴다.
- 로컬 브랜치·worktree·원본 작업 파일은 삭제하지 않는다. 새 PR 병합·릴리스·운영 배포도 하지 않는다.

각 삭제 대상의 원래 SHA는 `archive/20260909/remote-head-<SHA 앞 12자리>` 태그로 보존한다. 태그의 원격 존재와 commit SHA를 검증한 뒤, 조사한 head가 그대로일 때만 삭제하도록 정확한 SHA 조건을 건다. 중간에 누군가 새 커밋을 올리면 일괄 삭제를 중단한다.

[기계 판독용 전체 SHA·병합 근거](remote-branch-cleanup-manifest.yaml)

## 2. 삭제 대상

| 브랜치 | 원래 SHA | 병합 근거 |
|---|---|---|
| `docs/stitch-runtime-comparison-update` | `d9cb85b9cd2f` | PR #175 → #181 병합; 현재 head 일치 |
| `feature/canonical-screen-audit-and-gaps` | `71c22daa7f1a` | PR #174 → #181 병합; 현재 head 일치 |
| `feature/naver-collection-continuation-20260906` | `ea787e7e1902` | 보존된 9/7 후보의 조상 |
| `feature/profile-and-place-routes` | `6fb342651492` | PR #171 → #181 병합; 현재 head 일치 |
| `feature/round2-broad-product-expansion` | `fbc0ba22e460` | PR #179 → #181 병합; 현재 head 일치 |
| `feature/round2-community-trust` | `32b139749431` | 통합 원본의 조상; PR #180 → #181 |
| `feature/round2-local-signals-authoring` | `f269c4feef2a` | 통합 원본의 조상; PR #180 → #181 |
| `feature/round2-trust-authoring-integration` | `a81194a99d44` | PR #180 → #181 병합; 현재 head 일치 |
| `feature/screen-finalization-and-sync` | `03ae18ace9c9` | PR #173 → #181 병합; 현재 head 일치 |
| `feature/server-travel-preferences` | `1dc09a74b970` | PR #169 → #181 병합; 현재 head 일치 |
| `feature/stitch-functional-gap-expansion` | `88b9a6467ae1` | PR #178 → #181 병합; 현재 head 일치 |
| `feature/trip-library-and-overrides` | `dce728b067d9` | PR #172 → #181 병합; 현재 head 일치 |
| `fix/open-map-attribution-20260906` | `cd8488dd8cf1` | 보존된 9/7 후보의 조상 |
| `fix/restaurant-entry-paint-20260907` | `a955c2a4377d` | 보존된 9/7 후보의 조상 |
| `fix/web-map-smoke-iframe-20260904` | `c567d357e2ca` | PR #182 병합; 현재 head 일치 |
| `geondongkim/feature-community-durability-20260905` | `e2efc276b85b` | 보존된 9/7 후보의 조상 |
| `geondongkim/feature-localized-open-map-provider-20260905` | `8011234acea8` | PR #197 병합; 현재 head 일치 |
| `geondongkim/fix-account-sync-resume-20260905` | `490c6f3d6bdc` | 보존된 9/7 후보의 조상 |
| `geondongkim/fix-ios-flutter-tts-pod-lock-20260905` | `feb47b6336d7` | PR #196 병합; 현재 head 일치 |
| `geondongkim/fix-logto-account-sync` | `fb54d0f28484` | PR #170 → #181 병합; 현재 head 일치 |
| `geondongkim/fix-native-map-locale-transition-20260906` | `f49755e04e23` | PR #200 병합; 현재 head 일치 |
| `geondongkim/fix-place-reason-local-time-20260906` | `705579c05e6b` | 보존된 9/7 후보의 조상 |
| `geondongkim/fix-runtime-evidence-gaps-20260904` | `72a582bea7a5` | PR #183 병합; 현재 head 일치 |
| `geondongkim/fix-runtime-truthfulness-20260905` | `d54a36b85086` | PR #198 병합; 현재 head 일치 |
| `geondongkim/integrate-p4-closing-soon-20260905` | `9aa124723051` | PR #192 병합; 현재 head 일치 |
| `geondongkim/integrate-p6a-offline-qa-20260905` | `e14ae0cac1e8` | PR #194 병합; 현재 head 일치 |
| `geondongkim/integrate-p7-community-hardening-20260905` | `591f8d8374ef` | PR #193 병합; 현재 head 일치 |
| `geondongkim/p4-air-quality-integration-20260905` | `55ea871d715c` | PR #191 병합; 현재 head 일치 |
| `geondongkim/p6b-docent-judge-integration-20260905` | `78e55c1fea7c` | PR #195 병합; 현재 head 일치 |
| `geondongkim/preference-aware-plans-20260905` | `18bc64b64238` | PR #188 병합; 현재 head 일치 |
| `geondongkim/restaurant-communication-20260905` | `81ac1fd32626` | PR #189 병합; 현재 head 일치 |
| `geondongkim/weather-observed-time-20260905` | `4ccc4944f788` | PR #190 병합; 현재 head 일치 |
| `integration/canonical-screen-completion-20260903` | `3299e9a732de` | PR #181 병합; 현재 head 일치 |
| `integration/lala-consolidation-20260805` | `6e9782a3f3dc` | PR #107 병합; 현재 head 일치 |

## 3. 남기는 브랜치

| 브랜치 | 유지 이유 |
|---|---|
| `6059535` | 병합 근거 부족; 추가 판단 전 보존 |
| `chore/logto-rebased-on-main` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/general-openai-docent-mainline` | PR 종료는 확인되나 병합 아님 |
| `codex/lala-local-signals-spec` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/lala-terraform-iac` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/pr-a-data-ingest` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/pr-b-review-mentions` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/pr-c-review-scoring` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/pr-d-rag-review-chunks` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/pr-e-docent-qa-tooling` | 병합 근거 부족; 추가 판단 전 보존 |
| `codex/pr-f-ui-polish` | 병합 근거 부족; 추가 판단 전 보존 |
| `design/ui-ux-improvement-proposal` | 병합 근거 부족; 추가 판단 전 보존 |
| `dev` | main/dev/열린 PR/현재 준비 브랜치 |
| `docs/team-preparation-20260909` | main/dev/열린 PR/현재 준비 브랜치 |
| `feature/round2-plan-resilience-visit-conversion` | 병합 근거 부족; 추가 판단 전 보존 |
| `feature/round2-visitor-access` | 병합 근거 부족; 추가 판단 전 보존 |
| `fix/logto-session-profile` | 병합 근거 부족; 추가 판단 전 보존 |
| `fix/weather-unknown-localization-20260907` | main/dev/열린 PR/현재 준비 브랜치 |
| `geondongkim/feature-lala-onboarding-language-entry-20260827` | PR 종료는 확인되나 병합 아님 |
| `geondongkim/feature-lala-search-region-context-20260827` | PR 종료는 확인되나 병합 아님 |
| `geondongkim/feature-round2-docent-polish` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/feature-round2-signals-community` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/fix-runtime-plan-search-20260904` | main/dev/열린 PR/현재 준비 브랜치 |
| `geondongkim/lala-cleanroom-program` | 병합 당시 head와 현재 head 다름 |
| `geondongkim/lala-plan-review-ingestion` | 병합 당시 head와 현재 head 다름 |
| `geondongkim/lala-review-ingestion-foundation` | 병합 당시 head와 현재 head 다름 |
| `geondongkim/lala-zai-implementation` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/p4-closing-soon-20260905` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/p4-distinct-air-quality-20260905` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/p6-docent-judge-contract-20260905` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/p6-offline-qa-foundation-20260905` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/p7-community-write-guards-20260905` | 병합 근거 부족; 추가 판단 전 보존 |
| `geondongkim/p7-feed-epoch-20260905` | 병합 근거 부족; 추가 판단 전 보존 |
| `main` | main/dev/열린 PR/현재 준비 브랜치 |

위의 “병합 근거 부족”은 반드시 미반영 기능이 있다는 결론이 아니다. 현재 커밋을 안전하게 삭제할 근거가 충분하지 않아 보존한다는 의미다.

특히 `lala-cleanroom-program`, `lala-plan-review-ingestion`, `lala-review-ingestion-foundation`은 과거 MERGED PR이 있지만 현재 원격 head가 해당 PR의 head와 다르다. 예전 PR 상태만 보고 삭제하지 않는다.

## 4. 복구 방법

예: 삭제 대상인 `feature/server-travel-preferences`의 원래 head를 새 로컬 작업 브랜치로 복구하려면 다음 보존 태그를 사용한다.

```bash
git fetch origin refs/tags/archive/20260909/remote-head-1dc09a74b970:refs/tags/archive/20260909/remote-head-1dc09a74b970
git switch -c feature/restore-server-travel-preferences archive/20260909/remote-head-1dc09a74b970
```

위 명령은 복구가 필요할 때 실행할 예시이며 이번 정리에서 실행하지 않는다. 다른 브랜치는 manifest의 `recoveryTag`와 `sha`를 사용한다. 원래 원격 브랜치명을 다시 만들지는 필요에 따라 별도로 결정한다.

## 5. 실행 결과

- 원격 삭제: 아직 실행 전.
- 삭제 전 복구 자료: 원래 SHA·판정 근거·복구 태그 이름을 기록.
- 완료 후 원격 목록, 열린 PR, main/dev/head 보존을 재검증하고 이 절을 갱신한다.
