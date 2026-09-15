# 05. 팀 작업과 PM 검수

## 웹·앱 1~5 단계

| 순서 | 공통 | 웹 | 앱 |
|---|---|---|---|
| 1. 개인 local | 최신 main에서 기능 브랜치, 담당 테스트 | 브라우저에서 로컬 Flutter + mock 또는 로컬 API | emulator/simulator에서 mock 또는 로컬 API |
| 2. PR CI·리뷰 | feature push → PR → 필수 CI → 관련 역할 리뷰 | analyze·test·web build | 공통 Flutter 검사 + 변경 플랫폼 compile |
| 3. staging | main merge → 지정 SHA 배포 → smoke | staging URL, 실제 staging API | staging API를 바라보는 서명된 내부 테스트 빌드 |
| 4. PM·팀 검수 | 시험 계정·데이터·버전 고정, 문제면 수정 PR | 로그인·지도·저장·새로고침·권한 거부 | 같은 흐름 + GPS·WebView·음성·복귀·기기별 callback |
| 5. production | 검수 버전 지정 → 운영 승인 → 배포·smoke | 운영 설정으로 빌드한 웹 배포 | 운영 앱 ID·서명 빌드 → 스토어 출시 절차 |

위 흐름은 [기존 배포 전환](03-ci-and-deployment.md) 후 적용된다.
각자의 feature push가 공유 staging DB에 직접 SQL을 실행하거나 자동 운영 배포를 시작하는 구조를 만들지 않는다.

프론트는 화면·상태 개발 때 모든 DB 도구를 설치할 필요가 없다. mock으로 독립 작업하고,
인수된 공유 staging API 또는 동료의 개발 전용 API로 통합한다. PM 검수 중인 staging의 데이터 초기화·배치를 임의 실행하지 않는다.
동시 작업 때문에 검수가 반복해서 깨지면 추가 dev 환경은 그때 검토한다.

## 로컬 앱의 API 주소

| 실행 위치 | 로컬 API 접근 예시 |
|---|---|
| 개발 PC 웹 | `http://127.0.0.1:8080` |
| 같은 Mac의 iOS simulator | 일반적으로 `http://127.0.0.1:8080`, 실제 연결 확인 |
| 표준 Android Emulator | 호스트 loopback 별칭 `http://10.0.2.2:8080` |
| 실제 휴대폰 | 개발 PC의 접근 가능한 LAN 주소 또는 승인된 개발 tunnel |

실제 휴대폰의 `localhost`는 휴대폰 자신이다. LAN 테스트에는 서버 bind·방화벽·OS의 HTTP 정책을 확인한다.
개발용 예외를 운영 앱에 그대로 포함하지 않는다. 웹의 origin/CORS와 앱·Logto callback 등록은 API 주소 변경과 별개다.

## 역할과 인계

| 담당 | PR에 포함할 것 | 함께 리뷰할 상대 |
|---|---|---|
| 백엔드 1명 | API 계약, mock 테스트, 실제 DB query 검사, 환경 설정 영향 | 응답 변경은 프론트, SQL 변경은 DB |
| 프론트 1명 | widget/state 테스트, 빌드, 웹·앱 callback·권한·오류 상태 | API 계약은 백엔드 |
| DB 개발 1명 | schema 변경, seed, 업그레이드·데이터 보존 결과 | query·트랜잭션은 백엔드 |
| 지정 배포 담당 | 환경 인수, migration·배포 순서, release 기록·복구 | 관련 개발자 + PM |
| PM | staging 빌드 기준 시나리오 결과·버그·검수 판정 | 해당 기능 담당 |

배포 담당은 세 명 중 한 명이 겸임할 수 있다. CI 구축·DB migration 적용·스토어 배포의 책임자를 문서에 확정한다.
DB/API/프론트 변경이 작은 하나의 기능이면 통합 PR로 함께 검증해도 된다.
분리 PR이면 먼저 nullable 컬럼·선택 응답 필드처럼 하위 호환되는 변경부터 merge한다.

## PM이 받는 것

- 웹: staging URL과 접근 방법, 테스트 계정 A/B, 테스트 데이터 목록.
- iOS: TestFlight 등 선택한 내부 배포 경로의 초대와 build number.
- Android: 선택한 내부 배포 경로의 초대·설치 링크와 build number.
- 공통: 현재 검수 SHA, 출시 대상 기능, 알려진 제한, 버그 기록 위치.

TestFlight·Android 배포 계정과 서명 접근은 프론트/배포 담당자가 인수한다.
staging 앱은 운영 앱과 함께 설치할 수 있는 별도 앱 식별자·표시 이름·callback을 구성한다.
웹에서 성공한 결과를 실제 iOS/Android 검수 완료로 대신하지 않는다.

| 시나리오 | 기대 결과 | 증거 |
|---|---|---|
| 장소 선택 → 로그인 → 저장 → 다시 열기 | 같은 계정에서 저장 유지 | app/API SHA, 테스트 장소 ID, 결과 |
| 계정 A 저장 후 B 로그인 | B의 목록에는 A의 저장 없음 | 비식별 계정 별칭 A/B, 결과 |
| 위치 허용/거부 | 정상 지도 또는 정의된 대체 흐름 | 플랫폼·OS·언어·결과 |
| 언어 변경 | 한국어 NAVER, 지원 외국어 open-vector 지도 정상 | 언어·기기·지도 provider |
| 날씨 조회·갱신 | 실제 관측 시각과 데이터 상태 표시 | 갱신 시각·source·결과 |
| 도슨트 생성·음성 | 출시 설정의 실제 생성·재생, 실패 시 정의된 처리 | cache/live/fallback 구분, 결과 |
| 로그인 callback·만료·로그아웃 | 올바른 환경 복귀, 인증 상태 갱신 | Web/iOS/Android별 결과 |

계정 삭제는 공유 Logto tenant의 별도 제한 검수다. [계정 삭제 정책](02-environments-and-external-apis.md)을 먼저 충족한다.
외부 provider 장애를 재현하는 오류 테스트는 mock으로 수행하고, 실제 호출 성공 기록과 구분한다.

## Release 검수 기록 양식

아래를 release별 비공개 운영 기록에 채운다. 저장소에는 비밀·개인정보를 기록하지 않는다.

| 항목 | 기록 |
|---|---|
| release / 검수 일시 / 담당 | 미입력 |
| API SHA·artifact ID / 웹 SHA | 미입력 |
| iOS·Android build number·소스 SHA | 미입력 |
| DB revision 또는 SQL manifest hash | 미입력 |
| 비밀 값을 제외한 설정 버전·활성 기능 | 미입력 |
| 시나리오별 플랫폼·언어·결과·결함 | 미입력 |
| 실제 외부 연동 / mock / 미검증 항목 | 미입력 |
| PM 판정 / 운영 배포 담당 / 복구 버전 | 미입력 |

새 SHA 또는 검수에 영향을 주는 설정·DB 변경이 들어오면 영향받은 시나리오를 다시 검수한다.

## 다음 구현에 필요한 입력

문서와 PR CI 준비는 아래 값 없이 진행할 수 있다. 실제 staging 연결부터 필요한 정보다.
기존 관리 문서의 전달 경로·설정 이름을 받고, API 키·비밀번호 원문을 채팅에 요청하지 않는다.

| 입력 | 현재 상태·추천 | 필요한 시점 |
|---|---|---|
| staging 클라우드 | 사용자 결정: 이번에는 미정 유지, 공통 구조까지만 정의 | 실제 staging 구현 착수 |
| staging API·웹 주소, DB 자원 분리 범위 | 미확정. 운영 주소로 대체하지 않음 | staging 연결 |
| 서비스 권한·비밀 저장 영역·공개 설정 mapping | 기존 AWS IAM·region·prefix 접근 문서 학습 완료, staging 구성 미인수 | 키 접근·빌드·배포 |
| Logto 앱·API resource 추가 가능 범위 | tenant 1개 전제. 계정 담당 확인 필요 | audience·callback 분리 |
| PM 시험 계정 A/B·QA 장소·초기화 담당 | 별칭·ID만 공개 가능, 자격증명 비공개 | PM 검수 |
| 실제 연동할 AI·Speech·수집 범위와 호출량 | 기능별 한도 미확정 | 유료/실제 연동 검수 |
| 앱 배포 경로·개발자 계정·서명·staging 앱 ID | 미인수 | 내부 테스트 빌드 배포 |
| 운영 release 승인자·배포 담당 | 세 개발자 중 겸임 가능, 지정 필요 | 자동 배포 전환·운영 승격 |
| GitHub 보호 규칙·Vercel Git 연동 설정 | 이번 조사에서 실설정 미조회 | merge gate·배포 전환 |

클라우드 제공자를 선택할 때 기존 runtime·배포 도구의 호환성을 검증한다.
특히 과거 Azure `dev` 설정과 현재 AWS Secrets Manager 전용 runtime은 그대로 호환된다고 가정하지 않는다.
제공자 선택과 실제 리소스 구성은 후속 작업이며 이번 산출물의 완료 조건이 아니다.
