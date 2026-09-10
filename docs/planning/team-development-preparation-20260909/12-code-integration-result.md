# 코드 통합 결과

기준일: 2026-09-10. 후보 코드 선택 뒤 사용자의 별도 지시에 따라 PR 정리, 병합, CI와 자동 API 배포 확인까지 수행했다.

## 확정 기준

| 구분 | SHA·결과 |
|---|---|
| 선택 전 main | `9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6` |
| 선택 후보 | `8aa184e375f381fa4de0a97bca82ffa3e59ba836` |
| PR #187 head / merge | `a955c2a4` / `055bea56` |
| PR #206 head / merge | `8aa184e3` / `e64ed058` |
| 확정 제품 코드 | `e64ed0583749ab0e6a372f48978eee1e8e49a265` |

후보 `8aa184e3`는 확정 제품 코드의 조상이다. #187을 merge commit으로 먼저 병합해 커밋 계보를 보존했고, #206을 새 main으로 retarget한 뒤 두 커밋·세 파일만 남는지 확인했다. #206의 GitHub 합성 merge tree와 후보 head tree도 같았다.

## PR과 검증

- [PR #187](https://github.com/3dt-1st-org/LALA-next/pull/187): 제목·설명을 현재 범위와 배포 경계에 맞게 정리하고 Ready 전환 후 병합.
- [PR #206](https://github.com/3dt-1st-org/LALA-next/pull/206): main retarget, CLEAN 상태와 기존 성공 checks 확인 후 병합.
- [#187 후 main CI](https://github.com/3dt-1st-org/LALA-next/actions/runs/34419870659)와 [API 배포](https://github.com/3dt-1st-org/LALA-next/actions/runs/34420193876) 성공.
- [최종 main CI](https://github.com/3dt-1st-org/LALA-next/actions/runs/34420377285)와 [API 배포](https://github.com/3dt-1st-org/LALA-next/actions/runs/34420615436) 성공.
- 최종 배포 뒤 운영 `/healthz`와 `/readyz`는 HTTP 200이며 ready mode는 DB-backed였다.

CI에는 API tests and safety contracts, Unix wrapper verification, Flutter app analyze and test가 포함된다. EC2 workflow는 API 코드를 배포하며 Flutter 앱 바이너리나 웹 앱을 배포하지 않는다.

## 남은 배포 경계

- `sql/canonical/068_community_chat_durable_controls.sql`은 additive·idempotent지만 자동 EC2 코드 배포에서 적용되지 않는다. 운영 SQL head는 이번에 확인하지 않았다.
- SQL 068을 확인·적용하기 전에는 새 커뮤니티 채팅 내구성 경로의 운영 완료를 주장하지 않는다.
- 개발 전용 API·DB·시험 계정의 현재 가동과 운영 분리는 아직 인수되지 않았다. 운영 API를 개발 환경 주소로 대신 사용하지 않는다.
- Flutter 앱 배포, 실제 기기·지도·Logto·음성 검증은 후속 인수 항목이다.
- 날씨 일정 재계획, Local Signals, 커뮤니티·채팅 코드는 보존했다. 실증 사용자 진입점은 변경하지 않았다.

병합된 PR 브랜치는 연결된 worktree와 복구 근거가 있어 이번 작업에서 삭제하지 않았다. 화면 선별 자료, MVVM 채택, 개발 환경과 역할별 완료 조건이 확정되기 전 상태는 **코드 기준 통합 완료 / 구현 착수 대기**다.
