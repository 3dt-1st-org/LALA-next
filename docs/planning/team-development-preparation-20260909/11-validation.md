# 준비안 검증 기록

기준일: 2026-09-09, 추가 검증일: 2026-09-10. 기능 구현·앱 실행 인수와 문서 검수를 구분한다.

## 1. 범위와 기준

출발 문서 커밋은 740a42cc41edc1d43f8e5b8c0600c4ea56db8d28이다. 원격 main 9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6과 후보 8aa184e375f381fa4de0a97bca82ffa3e59ba836의 SHA를 다시 조회했다. 최종 문서 커밋·원격 반영 여부는 실제 commit/push 후 전달하는 결과로 확인한다.

## 2. 실행한 검수

| 검사 | 결과 | 의미 |
|---|---|---|
| 화면 ID·구조 | 36개 카드, 중복·누락 없음 | 최종 채택 화면 36개라는 뜻은 아님 |
| 대표 코드 근거 | 36개 대표 소스의 후보 SHA-256을 과거 색인과 대조, 모두 일치 | 대표 파일 내용 확인. 전 화면 실구동 검증 아님 |
| 문서 링크·고정 SHA 링크 | 상대 링크의 파일 존재와 Git blob 링크의 대상 객체 확인 | 웹·기기 실행 결과 아님 |
| 명령 예시 문법 | Bash 블록 6개, 내장 Python 예시 1개 문법 확인 | 명령 자체를 실행한 API·Flutter 결과 아님 |
| 검증 명세 | T-01~T-17 17개, 중복 없음 | 후속 시험 명세이며 17개 시험 통과가 아님 |
| 공개 범위 | 신규 문서의 개인 절대경로·ARN·클라우드 ID·DSN·키 패턴 검사 통과 | 환경·계정은 논리 정보와 확인 상태만 기록 |
| 원본 보존 | 보존 목록의 회의·조사·Markdown·PDF 7개 해시 일치 | 원격 원본 백업·PDF 재검수 아님 |
| 활성 지침 보존 | 루트 AGENTS, AGENTS.example, Copilot, .gitignore 해시 불변 | 기존 개인 사본을 추적·공개하지 않음 |
| Git diff 문법 | git diff --check 통과 | 문서 이외 제품 변경 여부는 커밋 범위와 함께 확인 |

읽기 전용 환경 조사와 GitHub dev 단서는 [환경표](08-development-environment.md)에 기록했다. 비밀 값은 조회하지 않았고 실제 개발 API·DB 인수는 완료하지 않았다.

### 2026-09-10 추가 조사·검증

| 검사 | 결과 | 의미 |
|---|---|---|
| 원격 SHA | main `9e312bb4`, 후보 `8aa184e3`, dev `9989e987`, 문서 branch `96a587db` 재확인 | 조사 시점 원격 일치. 최종 문서 커밋은 이후 별도 기록 |
| PR 상태·CI | #187·#206 OPEN Draft·CLEAN, 각 head의 API·Unix·Flutter CI 성공 | 리뷰·병합·배포 완료를 뜻하지 않음 |
| main 선별 API | 66 passed, 경고 1 | OpenAPI·계획·취향 계약의 격리 검사 |
| 후보 선별 API | 70 passed, 경고 1 | 같은 범위와 후보 추가 회귀 검사. 실 DB·Logto 검사는 아님 |
| main 선별 Flutter | 59 passed | cold start·저장 persistence·목록·여행 store 격리 검사 |
| 후보 선별 Flutter | 63 passed | 같은 범위와 access-token fencing 포함. 실기기·지도 검사는 아님 |
| GitHub dev 환경 | 변수 12개, 필수 OIDC·구독·resource group·CORS 값 존재, 등록 비밀 2개 중 DB 관리자 비밀 이름 존재, protection rule 0 | 값·권한 유효성과 현재 가동 상태는 미확인 |
| GitHub deployment | 마지막 dev 성공은 2026-06-23, SHA `9989e987`, environment URL 없음 | 현재 후보·API·DB 호환성 근거로 사용 불가 |
| Azure CLI·Resource Graph | enabled 구독 1개이나 GitHub dev 배포 구독과 불일치. 현재 구독에서 LALA 식별 리소스 0개 | 개발 환경 부재가 아니라 접근 불일치로 판정 |
| 공식 지침 재확인 | Codex AGENTS 탐색 순서·새 세션 적용·기본 32 KiB 한도, Flutter의 View·ViewModel·Repository·Service 책임 확인 | 공통 지침 적용 절차와 A안 추천의 외부 기준 |

API 검사는 `LALA_RUNTIME_PROFILE=ci`, `AWS_EC2_METADATA_DISABLED=true`를 사용하고 상속된 DB·클라우드·인증 값을 제외했다. main 임시 worktree는 검사 후 제거했으며 후보 worktree와 문서 checkout에 추적 변경을 남기지 않았다. Flutter 의존성 해석은 lockfile을 바꾸지 않았다.

## 3. 격리된 새 세션 시험

공통 AGENTS 초안을 임시 Git 폴더의 루트에 놓고 준비 문서를 복사했다. 사용자 config를 배제한 ephemeral Codex CLI 새 세션을 read-only로 실행했고 종료 코드는 0이었다. 지정 문서 읽기·검색만 수행했는지 도구 명령도 확인했다. 모델·계정 비밀·도구 원문·로컬 절대경로는 이 공개 기록에 넣지 않는다.

2026-09-10 갱신된 공통 AGENTS 초안으로 같은 시험을 다시 실행했고 종료 코드는 0이었다. 다음 9개 응답을 직접 검토했으며 모두 의도와 일치했다.

1. 작업 범위는 준비와 인계이며 제품 구현·숨김·배포를 수행하지 않음.
2. 후보는 조건부 통합 추천이며 #187→#206 정리·최종 SHA 승인 전에는 문서 브랜치를 구현 기준으로 쓰지 않음.
3. ko NAVER·방문객 언어 open-vector 방향과 플랫폼 분기·출처 보존.
4. 공용 개발 API 우선, GitHub 설정 존재, Azure 배포 구독 접근 불일치와 실환경 인수 미완료를 구분.
5. 장소 저장 예제의 Repository + 주입형 ChangeNotifier ViewModel 추천과 팀 채택 대기를 구분하고 Riverpod 일괄 전환을 하지 않음.
6. 보류 기능의 코드·테스트 보존과 진입점 숨김의 후속 처리.
7. 임시 초안 시험을 원본 루트·팀 도구 적용 완료로 보고하지 않음.
8. 활성화할 5파일과 개인 원본 보존·도구별 새 세션 검증을 식별.
9. 기술 리드의 환경·PR 스택 처리와 각 역할의 자료·결정·리뷰 수락이 남았음을 인식.

이 시험은 초안의 내용 전달을 확인한다. 실제 사용자 설정과 충돌할 가능성, Claude·Copilot 적용, 실제 팀원 새 clone의 환경을 검증한 것은 아니다. 해당 확인은 [공통 지침 적용 절차](07-common-guidelines.md)에 남긴다.

## 4. 이번에 실행하지 않은 검증

- 최종 선별 PDF·온보딩 질문안 대조: 자료 수령 전.
- 실제 앱·브라우저·기기·지도·음성·Logto 로그인 검증: 미실행.
- 실제 개발 API·DB 연결·분리·시험 계정 인수: GitHub 구성만 확인, Azure 배포 구독 접근 불일치로 runtime은 미확인.
- 활성 루트 AGENTS·Claude·Copilot 적용: 미수행. 공통 지침 초안만 작성.
- 제품 전체 test suite·실환경 통합 검증: 선별 단위·계약 검사만 실행.
- workflow 실행·PR 병합·배포·DB 적용·비밀 값 조회: 미수행.

## 5. 커밋 전 검사

작업 문서만 명시해 첫 pre-commit을 실행했다. Detect secrets가 README의 기존 항목 줄 번호를 44에서 52로 갱신하면서 재실행을 요구했다. baseline의 차이를 구조로 비교했으며 변경은 해당 줄 번호와 생성 시각뿐이다. 새 비밀 항목·fingerprint·검사 규칙 변경은 없다. 문서 위치 이동에 따른 검사 메타데이터로 함께 보존한다.

baseline을 포함한 16개 변경 파일의 pre-commit 재검사가 종료 코드 0으로 통과했다. Detect secrets·공백·파일 끝·충돌 표식·파일 크기 검사는 passed이며 Python·YAML·TOML 대상이 없는 hook은 skipped다. 새 비밀 항목은 추가하지 않았다.

2026-09-10에는 갱신한 Markdown 10개를 명시해 pre-commit을 실행했고 첫 실행부터 종료 코드 0이었다. Detect secrets·공백·파일 끝·충돌 표식·파일 크기 검사가 통과했으며 자동 수정과 secrets baseline 변경은 없었다. 15개 준비 Markdown의 상대 링크·표 열 수 검사, 36개 화면 카드·T-01~T-17 유지, 공통 AGENTS 초안 5,247 bytes, `git diff --check`도 통과했다.

앱·API·SQL·workflow·활성 지침 변경은 커밋에 섞지 않는다. 원래 미추적 _workspace/·tmp/와 Git 제외 output/의 원본·검수 자료도 포함하지 않는다.
