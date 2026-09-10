# 코드 기준 비교

조사일: 2026-09-09, 원격·PR·선별 검증 갱신일: 2026-09-10. 원격 브랜치 SHA와 로컬 Git 객체를 대조했다. 기능 표는 코드·커밋 변경 내용에 대한 판정이며, 별도 검증 기록이 없는 행은 실행 성공을 뜻하지 않는다.

후속 선택: 사용자는 main·후보를 비교한 뒤 후보의 혼합 구성을 통합하기로 했다. 2026-09-10에 #187과 #206을 순서대로 병합해 제품 코드 기준을 `e64ed0583749ab0e6a372f48978eee1e8e49a265`로 확정했다. 아래 표는 선택 전 비교 기록이며 최신 결과는 [통합 결과](12-code-integration-result.md)를 따른다.

## 1. 세 가지 기준

| 기준 | SHA | 조사 당시 원격 브랜치 | 의미 |
|---|---|---|---|
| 시작 로컬 | `1dc09a74b9704bc60a2c2fe7567be5e4ae69eb30` | `feature/server-travel-preferences` | 계정 취향 저장과 접근성 수정까지 작업한 선 |
| 원격 main | `9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6` | `main` | 공유 main에 반영된 코드. 운영에 실제 배포된 SHA는 이번에 확인하지 않음 |
| 9/7 보고서 후보 | `8aa184e375f381fa4de0a97bca82ffa3e59ba836` | `fix/weather-unknown-localization-20260907` | 조사 당시 미병합 작업선. 현재 확정 코드의 조상 |
| 확정 제품 코드 | `e64ed0583749ab0e6a372f48978eee1e8e49a265` | `main` | #187·#206 merge commit을 포함한 코드 기준 |

| 비교 | 결과 |
|---|---|
| 로컬과 main | 서로에게 없는 커밋 5개 / 6개 |
| main과 후보 | main은 후보의 조상. 후보 쪽에 70개 커밋 추가(merge commit 포함) |
| 로컬과 후보 | 서로에게 없는 커밋 5개 / 76개 |
| main → 후보 파일 차이 | 201개 파일, 37,868줄 추가 / 1,424줄 삭제. 테스트·생성 코드·문서도 포함 |
| 원격 보존 | 세 SHA 모두 기존 원격 브랜치에서 확인 |

70개 커밋은 70개 기능을 의미하지 않는다. 보완·회귀 테스트·merge가 포함된다. 서로 다른 커밋 ID라고 해서 같은 동작이 다른 쪽에 없다는 뜻도 아니다.

### 후속 재확인: PR 의존 관계와 병합 결과

2026-09-10 GitHub API로 [#187](https://github.com/3dt-1st-org/LALA-next/pull/187)과 [#206](https://github.com/3dt-1st-org/LALA-next/pull/206)을 다시 확인했다. 조사 당시 둘 다 OPEN·Draft·CLEAN이었다. 이후 제목·설명·배포 경계를 정리하고 다음 순서로 병합했다.

- #187: head `a955c2a4`, base `main`에서 merge commit `055bea56`으로 병합.
- #206: head `8aa184e3`를 새 `main 055bea56`으로 retarget. 두 커밋·세 파일과 CLEAN 상태, 합성 merge tree가 head tree와 같음을 확인한 뒤 merge commit `e64ed058`으로 병합.
- 두 병합 뒤 정확한 main SHA에서 API·Unix wrapper·Flutter CI와 EC2 API 자동 배포가 성공했다.

#206은 처음에는 #187 위의 자식 PR이었으므로 #187을 merge commit 방식으로 먼저 병합해 ancestry를 보존했다. 최종 제품 코드 기준과 운영 확인은 [통합 결과](12-code-integration-result.md)에 기록했다.

### 2026-09-10 선별 재검증

두 SHA를 동일한 저장·계정·API 계약 범위로 검사했다. `main`은 임시 detached worktree, 후보는 정확한 head의 clean worktree를 사용했으며 상속된 DB·클라우드·인증 설정을 배제한 CI 프로필로 API 테스트를 실행했다.

| 기준 | API 선별 검사 | Flutter 선별 검사 | 해석 |
|---|---:|---:|---|
| main `9e312bb4` | 66 통과 | 59 통과 | 기존 저장·복원·목록·계약 기준 통과 |
| 후보 `8aa184e3` | 70 통과 | 63 통과 | 같은 범위와 후보의 계정 토큰 경계 회귀를 포함해 통과 |

API에서는 OpenAPI 계약·호환성, 계획 endpoint·repository, 취향 API를 검사했다. Flutter에서는 cold start 복원, action persistence, 저장 ID 상태, 저장 목록·여행 저장소를 검사했고 후보에는 access-token fencing을 추가했다. 둘 다 Starlette의 향후 의존성 전환 경고 1건이 있었으며 실패는 없었다. 실제 개발 API·Logto·지도·기기 검증은 이 결과에 포함되지 않는다.

## 2. 로컬에만 보이는 5개 커밋

| 로컬 커밋 | 작업 내용 | 이번 대조에서 확인한 내용 |
|---|---|---|
| `9b2d6c04` | 인증 제공사별 scope 정책과 계정 동기화 오류 분류 | 관련 서버 설정과 계정 설정 UI는 후보에서도 유지. 인증 Controller에는 cold-start 복구와 세션별 토큰 응답 차단이 추가됨 |
| `4ec516a7` | 계정 기반 취향 저장, 서버·Flutter 연결, SQL 065 | 핵심 서버 파일 3개, 원격 저장 adapter, SQL 065는 로컬과 main이 동일 |
| `d2bb647a` | 설정·음식점 요청 카드 접근성 | main의 요청 카드에 Semantics와 실제 탭 동작이 연결되어 있음 |
| `0e788465` | 접근성 동작과 화면 탭 동작 일치 | 요청 카드 파일은 로컬과 main이 동일. 설정 화면에는 큰 글씨·구획 제목 등의 후속 개선이 추가됨 |
| `1dc09a74` | secrets baseline 갱신 | 검사 기준 파일의 당시 이력. 다른 코드 기준으로 옮길 때 무조건 덮어쓸 대상이 아님 |

동일성을 확인한 파일:

- `apps/api/app/schemas/preferences.py`
- `apps/api/app/services/travel_preferences_repository.py`
- `apps/api/app/services/travel_preferences_service.py`
- `apps/flutter_app/lib/features/preferences/data/travel_preferences_remote.dart`
- `sql/canonical/065_user_travel_preferences.sql`
- `apps/flutter_app/lib/features/preferences/presentation/restaurant_communication_entry_card.dart`

따라서 5개를 묶어서 다시 cherry-pick하면 이미 반영된 내용과 후속 수정이 겹칠 수 있다. 이번에는 **기존 커밋을 보존하고 재적용하지 않는다.** 모든 파일과 모든 동작이 완전히 동등하다는 결론은 아니다.

추가 PR 이력 조사에서 이 로컬 head가 PR #169로 중간 통합 브랜치에 squash 병합되고, 그 통합 브랜치가 PR #181로 main에 병합된 경로도 확인했다. 원격 브랜치명 정리와 무관하게 원래 커밋은 보존 태그로 찾을 수 있다.

## 3. 흐름별 차이와 첫 실증과의 관계

| 영역 | main까지의 기반 | 후보에서 추가·보완된 코드 | 준비 단계에서의 처리 |
|---|---|---|---|
| 인증·취향 저장 | 계정 취향 저장, cold-start 실패의 게스트 복구 | 계정 전환 중 토큰·저장 응답 차단, 저장 순서 보장, 실패 후 복구와 회귀 테스트 | 첫 실증의 기반으로 검토. 실제 로그인·재로그인·동기화 검수는 별도 |
| 탐색·장소·저장 | 지도·검색·상세·일정·저장 경로 | 검색의 필터 후 빈 결과, 선택 장소를 일정에 고정, 탭 전환 중 덮어쓰기 방지 | 탐색 → 저장 흐름의 인계에 사용 |
| 지도·다국어 | NAVER 지도 기반 | 한국어 NAVER, 방문객 언어 open-vector 분기와 전환·출처 표시 수정 | 현재 코드 사실로 기록. 제공사 최종 선택·변경 승인은 아님 |
| 음식점 요청 카드 | 저장 취향을 보여주는 요청 카드 | 발음·음성 지원, 안전한 표시와 카드 배경 수정 등 | 화면 선별에서 포함 범위를 정하고 번역·가독성 검수 연결 |
| 도슨트 | 화면·재생 Controller, 빈 큐 미니플레이어 수정 | 오프라인 QA 차원·judge 계약, 재생 상태 표현 보완 | 첫 실증의 핵심. 오프라인 QA 존재를 실제 음성 품질 보장으로 취급하지 않음 |
| 날씨·일정 개입 | 날씨·대기질·일정 개입 구조 | 관측 시각, unknown 라벨, 대기질 원인, 추정 운영시간의 표현 보완 | 기본 정보 표시와 자동 일정 재계획을 구분. 후자는 첫 실증에서 미룸 |
| 커뮤니티·채팅 | 게시글·댓글·채팅 관련 경로 | 쓰기 보호, 전달 시 권한 재검증, 중복 전송·재시도 제어, SQL 068 | 코드는 보존하되 첫 실증 범위에 자동 포함하지 않음 |
| 데이터 수집 | 지역·리뷰 수집 기반 | bounded continuation, checkpoint, sweep lineage 등 오프라인 계약 | 이후 데이터 작업 자산으로 보존. 실수집·DB 반영·운영 가동하지 않음 |

후보의 지도 분기는 `apps/flutter_app/lib/lala_map_provider.dart`의 `selectLalaMapProvider`에서 확인했다. 이는 과거 로컬 AGENTS의 카카오 규칙 및 공유 템플릿의 NAVER 단일 규칙과도 구분해야 한다. 이번에는 어느 제공사로 바꾸지 않는다.

## 4. 9/7 보고서를 읽는 법

- 비교 대상은 논리 화면 36개이며, 채택된 실제 캡처는 32개다.
- 실제 캡처는 9/3~9/7의 여러 빌드에서 가져왔다. 후보 `8aa184e3`의 전 화면을 다시 검증한 결과가 아니다.
- S-21·S-51·S-58·S-59는 독립 캡처가 없다. 대응 코드가 있다고 실제 사용자 흐름까지 성공했다고 쓰지 않는다.
- 미래 예상도는 설명용 시안이다. 화면 배치·색상·설정 선택지를 그대로 구현할 승인본이 아니다.
- 보고서가 제안한 전체 기능 검수 우선순위는 9/8 회의의 축소된 첫 실증 범위로 다시 걸러야 한다.

예를 들어 보고서의 상세 예산·혼잡도 설정, 생활권 포함 3갈래 진입, 커뮤니티 검증 과제는 그대로 첫 실증 할 일로 복사하지 않는다. 한국을 여행하는 외국인의 단순한 진입·탐색·저장·도슨트 흐름을 먼저 맞춘다.

## 5. 개발 기준 결정 결과

후보 `8aa184e3`를 통합하는 추천을 채택했다. `main 9e312bb4`는 비교·복구 기준으로 남기고, #187과 #206을 병합한 `main e64ed058`을 제품 코드 기준으로 사용한다. 선택한 혼합 지도와 검색·일정·인증·취향 보완을 포함하며 미룬 기능의 코드·테스트·의존성도 보존한다.

`e64ed058`은 제품 코드 기준의 정확한 SHA다. 여기에 포함된 70개 후속 커밋 전체가 첫 실증 범위라는 뜻은 아니다. 날씨 일정 재계획, Local Signals, 커뮤니티·채팅은 계속 보류 기능으로 분류하고, 실증 사용자 진입점 조정은 후속 구현에서 다룬다.

### 통합 기준 게이트 결과

1. #187을 merge commit으로 병합해 자식 PR의 ancestry를 보존했다.
2. #206을 새 main으로 연결하고 두 커밋·세 파일의 diff와 합성 merge tree를 확인했다.
3. 최종 main `e64ed058`의 API·Unix·Flutter CI와 EC2 API 배포를 통과했다.
4. 운영 `/healthz`·`/readyz`는 HTTP 200과 DB-backed 상태를 반환했다.
5. SQL 068 적용 여부, 공용 개발 API, Flutter 배포·기기 검증은 완료로 간주하지 않는다.

현재 기준 표기는 `제품 코드 e64ed058 / 화면·MVVM·개발 환경 착수 결정 대기`다. 원래 문서 브랜치나 과거 `dev 9989e987`에서 구현을 시작하지 않는다.

## 비교 재현

```bash
git log --left-right --oneline 1dc09a74...9e312bb4
git log --oneline 9e312bb4..8aa184e3
git diff --stat 9e312bb4 8aa184e3
git diff 1dc09a74 9e312bb4 -- apps/api/app/schemas/preferences.py
git show 8aa184e3:apps/flutter_app/lib/lala_map_provider.dart
```

위 명령은 읽기 전용이다. 코드 선택·통합을 수행하지 않는다.
