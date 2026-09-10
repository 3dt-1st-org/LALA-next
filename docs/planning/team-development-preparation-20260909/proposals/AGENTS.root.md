# LALA-next 공통 작업 지침

이 파일은 저장소 루트에 적용할 공유 초안이다. proposals 안에서는 자동 적용되지 않는다. 적용 후 개인 설정과 섞지 않고 Git으로 관리한다.

## 현재 작업과 문서 입구

저장소 루트 기준 docs/planning/team-development-preparation-20260909/README.md와 03-next-decisions.md를 먼저 읽는다. 현재 단계는 준비 문서 작성과 합의이며 기능 구현, MVVM 전환, 화면 숨김, 병합, 배포는 별도 지시가 필요하다.

역사적 비교 기준은 main 9e312bb4와 후보 8aa184e3다. #187과 #206은 순서대로 병합됐으며 현재 제품 코드 기준은 main e64ed058이다. 원래 docs/team-preparation-20260909 브랜치는 보존용이며 개발 시작점이 아니다.

첫 실증은 한국 방문 외국인의 진입·탐색·상세·저장·도슨트 흐름이다. 화면 선별 PDF와 온보딩 질문안은 수령 대기다. 상세 화면 범위를 임의 확정하지 않는다. 날씨에 따른 일정 재계획, Local Signals, 커뮤니티·채팅의 코드와 테스트는 보존한다. 실증 진입점 숨김은 후속 구현에서 다룬다.

## 기술·제품 기준

- 지도 방향은 현재 main의 한국어 NAVER, en·ja·zh-Hans·zh-Hant open-vector다. 기존 지도·위치의 web/native/stub 분기와 출처 표시를 보존한다.
- 인증은 lib/auth의 Logto SDK 경유다. 직접 토큰 관리로 대체하지 않는다.
- 색상·배치는 새로 구성할 수 있다. 서비스 일관성, 접근성, 데이터 출처와 ColorScheme.fromSeed를 유지한다.
- LALA_BUILD_SHA를 유지하고 앱·API의 기준 SHA를 기록한다.
- 장소 상세 → 저장 → 목록의 첫 slice에는 Repository + 주입형 ChangeNotifier ViewModel 방식의 기존 Controller 보완을 추천한다. 팀 채택 전에는 확정으로 쓰지 않으며 Riverpod을 제거하거나 일괄 전환하지 않는다.
- View는 표시·입력, ViewModel/Controller는 화면 상태·비동기 순서, Repository는 데이터 정책, 서비스·adapter는 통신·영속화를 담당한다.
- 취향·여행 설정의 expected_revision을 보존한다. timestamp를 충돌 제어의 자동 대체물로 취급하지 않는다.
- API 변경은 서버 스키마·OpenAPI 수동 보완·Dart 생성 패키지·수동 adapter·DB 호환성을 함께 검토한다. 생성 코드와 adapter를 중복이라고 삭제하지 않는다.

## 개발과 검증

공용 개발 API 우선이다. docs/planning/team-development-preparation-20260909/08-development-environment.md에서 주소·접근·앱/API 조합을 확인한다. GitHub dev 배포 설정은 있으나 현재 Azure 런타임 접근·가동·분리 상태는 미검증이다. 기술 리드가 올바른 배포 구독의 읽기 권한 또는 비밀 없는 현재 상태 보고서를 제공하기 전에는 개발 환경 인수가 끝났다고 쓰지 않는다. 운영 API 기본값을 개발 주소로 대신 쓰지 않는다.

운영 비밀 없는 단위·계약 검사는 CI 프로필로 실행한다. 상속된 DB·클라우드·인증 값을 배제하는 환경표의 명령을 사용한다. Flutter/Dart는 확정된 SDK와 lockfile 기준을 확인한다.

검사만 할 때 formatter의 쓰기 모드를 사용하지 않는다. pre-commit은 파일을 수정할 수 있으므로 최초 uv run pre-commit install 후 작업 범위를 확인하고 실행한다. SDK가 없어 건너뛴 검사는 통과가 아니다. 문서만 바꾸면 링크·근거·공개 범위·pre-commit을 검수하고 앱 실행 성공을 주장하지 않는다.

DB 쓰기, 실수집, 유료 AI·음성, 배포·릴리스는 해당 작업 범위의 명시적 지시에 따라 수행한다. 환경 파일 전체를 출력·공유하지 않고 시크릿 값·정밀 위치·개인 정보를 커밋하지 않는다. fixture는 단위·격리 검사에만 쓰고 정상 서비스의 실제 DB/API 데이터를 대체하지 않는다.

## 협업·보존

- 브랜치 이름에 codex를 넣지 않는다. feature/·fix/·docs/·chore/를 사용하며 사용자가 정확한 이름을 주면 따른다.
- main에 직접 커밋하지 않는다. 허용된 작업 브랜치에서 conventional commit을 사용하고 작은 단위로 검수·커밋·푸시한다. 병합·배포는 별도 작업이다.
- 변경 전 Git 상태·README·관련 코드·worktree를 확인한다. 기존 dirty 파일과 원본·복구 태그를 보존한다.
- 라우터·테마는 프론트, API·OpenAPI는 백엔드, 공유 상태·SQL·환경은 기술 리드가 관련 역할과 리뷰한다. 상세 인계는 10-role-handoff-and-acceptance.md를 따른다.
- 과거 UI·운영 문서는 날짜·SHA·환경·대체 관계를 확인한다. 과거 파란색, 개인 이미지, 단일 Mac 운영을 모든 작업의 필수 조건으로 적용하지 않는다.
- 노션 조회·수정은 사용자의 별도 요청을 따른다. 회의 원문·개인 일정·대형 PDF는 공개 저장소에 복제하지 않는다.
- 확인 사실·제안·미결정, 문서 검수·코드 테스트·실기기 검증을 구분해 보고한다.
