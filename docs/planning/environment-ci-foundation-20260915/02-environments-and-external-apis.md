# 02. 환경·외부 API·키 정책

이 문서는 목표 정책이다. 현재 구현 여부는 [현황](01-current-state.md)에 표시했다.
사용자 결정에 따라 클라우드는 미정으로 두고 공통 구조만 정의한다.
현재 코드의 AWS 접근법은 기존 구현 설명이며 staging 제공자 선택을 의미하지 않는다.

## 환경과 runtime profile

| 항목 | Local | PR CI | Staging | Production |
|---|---|---|---|---|
| 용도 | 개인 기능 개발 | 변경 자동 검사 | PM·팀 통합 검수 | 사용자 서비스 |
| API·DB | 로컬 FastAPI·개인 Docker DB | 테스트 프로세스·일회용 PostgreSQL | 독립 API·별도 DB·DB 사용자 | 운영 API·운영 DB |
| profile | 명시 `local` | `ci` | API `api`, 배치 `worker` | API `api`, 배치 `worker` |
| DB 데이터 | 공개·합성 개발 seed | 재현 가능한 fixture/seed | QA 데이터 + 제한된 실제 수집 | 실제 서비스 데이터 |
| 비밀 | 필요한 개발 값만 로컬 비공개 파일 | 테스트 값만 주입 | staging 전용 저장 영역·서비스 권한 | 운영 전용 저장 영역·서비스 권한 |
| 외부 호출 | 단위 테스트 mock, 수동 통합은 선택 live | 서비스 provider 호출 mock | 출시할 연동은 실제/sandbox 검수 | 출시 기능의 실제 연동 |
| 정적 snapshot | 격리 테스트에서만 선택 사용 | fallback 자체 테스트에서만 사용 | 정상 검수에서는 `false` | 정상 운영에서는 `false` |

`ci`는 비밀 조회 방식을 제한한다. HTTP 호출을 자동으로 전부 차단하는 방화벽은 아니다.
테스트가 사용하는 HTTP client와 외부 SDK를 mock하고, 예상하지 않은 외부 요청은 테스트 실패로 처리한다.
패키지 다운로드 같은 CI 준비 통신과 서비스 API 호출을 구분한다.

환경 구분은 DB·서비스 권한·비밀 저장 영역·빌드 설정·배포 대상이 함께 맞아야 성립한다.
staging이 운영 비밀을 조회하거나 운영 DB에 연결할 수 없게 한다. 이름을 다르게 짓는 것만으로 권한이 분리되지는 않는다.
현재 `api`·`worker`는 클라우드 위치와 무관하게 AWS Secrets Manager를 요구한다.
다른 비밀 저장소를 선택하면 해당 adapter·인증·검증을 구현해야 하며, 설정 이름만 바꿔 호환된다고 가정하지 않는다.

## LALA 기능별 실제와 mock

| 기능과 코드 | Local / PR CI | Staging | Production |
|---|---|---|---|
| [장소·저장](../../../apps/api/app/services/places_service.py) | 단위 테스트 repository mock, 통합 테스트 실제 로컬 DB | 실제 staging DB에서 저장·재조회 | 운영 DB |
| [한국어 NAVER 지도](../../../apps/flutter_app/lib/lala_map_provider.dart) | widget은 fake, 화면 수동 검수는 개발 허용 origin의 실제 지도 | 실제 지도 + staging origin·WebView 조건 확인 | 운영 등록값 |
| 같은 파일의 OpenFreeMap 지도 | bridge 테스트는 fake, 실제 타일 표시 검사는 네트워크 필요 | en/ja/zh 언어별 실제 타일·선택·이동 | 실제 타일. 키가 없어도 외부 의존성임 |
| [날씨·미세먼지](../../../apps/api/app/services/weather_service.py) | DB fixture와 HTTP mock, 수동 검수만 개발 키 | 실제 관측값·갱신·수집 시각 확인 | DB cache + 실제 기상청·AirKorea 호출 |
| [도슨트 AI](../../../apps/api/app/services/docent_service.py) | unit mock 또는 rule-based 경로. 수동 live는 별도 실행 | live 출시 시 실제 생성 소량 검수, 실패·fallback도 확인 | 출시 설정에 맞는 live 또는 명시적 rule-based |
| [Azure Speech](../../../apps/api/app/services/speech_service.py) | HTTP mock. off이면 서버 음성 API는 미설정 오류 | 음성 출시 시 실제 생성·재생·기기별 검수 | 실제 Speech. 기기 TTS 대체는 별도 경로 |
| [Logto 로그인](../../../apps/flutter_app/lib/auth/logto_auth_gateway.dart) | 인증 mock/JWT fixture. callback 검수는 실제 Logto | 실제 로그인·로그아웃·만료·사용자 A/B 분리 | 실제 Logto |
| [Logto 계정 삭제](../../../apps/api/app/services/logto_management.py) | Management client mock | 공유 tenant의 운영 사용자 삭제 경로 차단 후 폐기용 계정만 제한 검수 | 실제 계정·세션·grant 삭제 |
| [TourAPI 수집](../../../apps/api/app/tools/run_tour_api_ingest.py), KOPIS·Naver Search 등 | fixture/plan. 실제 preview는 명시적 수동 검수 | 지역·건수 제한 실제 수집, staging에만 저장 | 예약 수집·중복 처리·재시도·호출량 관리 |
| [카카오/NAVER Directions](../../../apps/api/app/services/travel_time_service.py) | 현재 실제 연동 미구현, 추정 도보 시간 테스트 | 미구현 상태 유지. 키 유무로 live 완료 판정 불가 | 현재 추정값 경로. 실제 Directions는 별도 기능 구현 |

**mock, cache, off는 서로 다르다.** mock은 가짜 응답을 주입하는 테스트 구현이고,
cache는 저장된 데이터를 재사용하며, off는 기능을 실행하지 않는 설정이다.
로컬 서버의 키를 비웠다고 실제 날씨가 mock 날씨로 자동 바뀌지는 않는다.
`LALA_ENABLE_LIVE_AI=false`, `LALA_ENABLE_LIVE_SPEECH=false`는 기존 설정이고,
앞선 대화의 `LALA_WEATHER_MODE`·`LALA_DOCENT_MODE` 등은 아직 구현되지 않은 제안이다.

예를 들어 PM의 '장소 검색 → 지도 선택 → 로그인 → 저장 → 다시 열기' 검수는
실제 staging DB·지도·Logto를 연결한다. 도슨트 기능까지 검수한다면 실제 AI·Speech 경로의 결과도 별도로 남긴다.
정상 cache hit는 서비스 검증에 유효하지만 신규 AI 생성·음성 호출을 검증한 증거는 아니다.

## 키 접근법: 문서와 코드의 적용 순서

1. [runtime contract](../../operations/aws-secrets-manager-runtime-contract.md)와 [registry](../../../apps/api/app/core/runtime_secrets.py)에서 논리 이름·profile을 확인한다.
2. [team handoff](../../operations/aws-secrets-manager-team-handoff.md)에서 역할·준비·공개 빌드 경로를 확인한다.
3. 대상 환경의 승인된 서비스 역할·비밀 저장 영역·공개 설정 mapping을 담당자에게 받는다. 현재 AWS 도구에서는 IAM·region·prefix에 해당한다. 값 전체를 다시 요구하지 않는다.
4. 실제 접근 시에는 이름과 `found/missing/denied/unavailable/invalid`만 기록한다. 읽기 권한 부족을 키 부재로 단정하지 않는다.

| 실행 주체 | 현재 코드의 실제 접근법 |
|---|---|
| API·worker | registry에 등록된 비밀은 AWS Secrets Manager에서만 조회. 프로세스 비밀 값·dotenv·Azure Key Vault로 대체하지 않음 |
| CI 테스트 | 명시한 테스트 환경값만 읽음. AWS·dotenv 사용 없음 |
| Local API | 명시 `local`에서 `LALA_LOCAL_ENV_FILE` 또는 `.env.local`·`.env` 로딩. 프로세스 값 우선, AWS는 `LALA_LOCAL_USE_AWS_SECRETS` opt-in. legacy Key Vault 호환 경로 존재 |
| Flutter build wrapper | 공개 allowlist만 자식 Flutter에 전달. 현재 프로세스 값 우선, 지도 값이 없을 때만 지정 SSM mapping → Secrets Manager → 신뢰된 로컬 파일 |

[flutter_with_build_env.sh](../../../scripts/unix/flutter_with_build_env.sh)의
`--source-env`는 로컬 fallback 입력을 지정한다. 그 옵션만으로 AWS 조회나 상속된 설정을 차단하지 않는다.
일부 shell helper는 dotenv를 `source`하므로 신뢰된 파일만 사용한다.
현재 AWS wrapper로 staging 빌드를 연결할 때는 `--api-base-url`, 승인 `--region`·`--prefix`, 플랫폼별 Logto callback을 명시한다.
기본 API 주소는 운영이며, 기본 prefix도 staging용으로 간주할 수 없다.

| 분류 | 예시 이름 | 전달 대상 |
|---|---|---|
| 공개 클라이언트 설정 | `LALA_API_BASE_URL`, `LALA_BUILD_SHA`, `NAVER_MAP_CLIENT_ID`, `LALA_OPEN_MAP_STYLE_URL`, Logto endpoint·audience·Web/Native App ID·redirect | 프론트 빌드. 지도 허용 origin·플랫폼 등록 필요 |
| 서버 비밀 | `DB_DSN`, `OPENAI_API_KEY`, `AZURE_SPEECH_KEY`, `NAVER_CLIENT_SECRET`, `PUBLIC_DATA_SERVICE_KEY`, `KOPIS_API_KEY`, `KAKAO_REST_API_KEY`, Logto Management credentials | 해당 API·worker·migration 역할 |
| 서버 전환 인증값 | `API_BEARER_TOKEN`, `IOS_API_KEY` | 필요한 서버/테스트 도구만. 팀 배포 앱에 내장하지 않음 |

Naver Search의 `NAVER_CLIENT_ID`·`NAVER_CLIENT_SECRET`과 지도용 `NAVER_MAP_CLIENT_ID`를 구분한다.
배포 CI의 SSM Run Command 권한, 개발 빌드의 Parameter Store 조회, 서버의 Secrets Manager 조회도 각각 다른 권한이다.
[secret sync helper](../../../scripts/unix/sync_aws_secrets_manager.sh)는 원격 값을 다운로드하는 도구가 아니라
신뢰된 로컬 입력의 이름·존재를 확인하고, `--apply --confirm SYNC_AWS_SECRETS`일 때 원격에 쓰는 도구다.
문서 작업에 이 동기화나 실제 비밀 조회는 필요하지 않다.

## Logto tenant 1개 제약

tenant를 공유하면 사용자·세션·connector 설정도 공유될 수 있다. 앱 ID만 달리한다고 사용자 저장소가 나뉘는 것은 아니다.
허용되는 범위에서 Web/Native 앱과 API resource audience를 환경별로 분리하고 callback을 정확히 등록한다.
추가 등록 허용 범위는 계정 담당자가 확인하며, 확인 전에는 요금제 기능을 가정하지 않는다.

- 서로 다른 audience가 가능하면 staging 토큰을 production이 거부하는지 테스트한다.
- audience도 공유해야 한다면 앱 ID 차이만으로 토큰이 격리되지 않는다. staging 접근 제한·시험 계정 정책과 추가 검증을 구현 항목으로 남긴다.
- staging DB는 독립시킨다. 공용 tenant에서는 시험 계정 A/B를 사용하고 운영 계정으로 삭제 테스트를 하지 않는다.
- staging의 Management 호출은 서버에서 차단하는 정책을 추가한다. UI 숨김만으로 처리하지 않는다. 현재 환경별 차단 설정은 구현되어 있지 않다.
- Management 키를 생략하는 것만으로 삭제 요청 전체가 무해해진다고 가정하지 않는다. 로컬 DB 상태 변경 순서와 실패 복구도 테스트한다.
- 실제 삭제 검수는 차단 정책·대상 제한이 구현된 뒤, 지정한 폐기용 계정만 사용한다. 그전 결과는 'mock 검증 / 실제 삭제 미검증'이다.

과거 [Logto 배포 가이드](../../operations/logto-deploy-guide.md)의 provider 콘솔 절차는 참고 자료다.
그 문서의 Management API 주소를 LALA API audience 예시로 재사용하지 않는다.
현재 [빌드 검증 코드](../../../scripts/unix/_flutter_public_build_config.sh)는 그 audience 혼용을 거부한다.

## Dry-run은 명령별로 확인

| 명령 모드 | 실제 외부 API | DB 쓰기 |
|---|---|---|
| canonical SQL·dev reset 기본 plan | 없음 | 없음 |
| TourAPI 기본 plan | 없음 | 없음 |
| TourAPI `--preview` | 있음 | 없음 |
| 장소 AI 보강 `--dry-run-ai` | **실제 OpenAI 호출** | 없음. 입력 DB 읽기는 있음 |
| 수집·AI 보강 `--apply` | 있음 | 있음 |

따라서 'dry-run = 비용·네트워크가 항상 없음'으로 해석하지 않는다.
근거: [AI 명령](../../../apps/api/app/tools/enrich_place_ai_columns.py), [TourAPI 명령](../../../apps/api/app/tools/run_tour_api_ingest.py).
