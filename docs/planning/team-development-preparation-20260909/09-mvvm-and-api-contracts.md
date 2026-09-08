# 장소 상세 → 저장 → 목록: MVVM 비교와 계약

상태: **설계 비교안 작성 / MVVM 선택 미결정**. 제품 코드·공개 API·DB 스키마를 변경하지 않는다. 근거는 main 9e312bb4와 후보 8aa184e3의 Git 객체이며, 현재 문서 브랜치의 코드가 최신 후보라고 가정하지 않는다.

## 1. 기존 구현을 연결해서 읽기

| 경계 | 현재 구현과 이번 대조 |
|---|---|
| 저장 버튼·화면 간 상태 | LocalSignalActionController와 SavedPlaceStore의 장소 ID 집합. 보류 기능과 이름이 겹쳐도 공통 저장·이동 코드를 제거하지 않음 |
| 기기 복원·영속화 | core/persistence/action_preferences.dart가 SavedPlaceStore를 복원·저장. 메모리 반영과 디스크 성공은 다른 단계 |
| 계정 연결 | app/lala_app.dart는 authenticated와 accountSyncStatus.ready를 확인한 뒤 취향·TripLibraryStore를 연결 |
| 원격 저장 | TripLibraryStore → TripLibraryRemote → LalaApiClient → 저장 API → PlanningRepository |
| 목록 표시 | SavedPlacesPage가 저장 ID와 현재 공개 장소 조회를 결합. 조회 결과에 없는 ID를 보존하고 정보 누락 안내 |
| 기본 취향 | TravelPreferencesStore/Remote → /me/preferences → service/repository → SQL 065 |
| 여행별 설정·지난 일정·방문 | TripLibraryStore/Remote → 날짜 기반 계획 API → PlanningRepository → SQL 064·066 |

두 SHA에서 SavedPlaceStore, ActionPreferences, SavedPlacesPage, TripLibraryRemote, 저장 API router·PlanningRepository·planning schema는 동일하다. TripLibraryStore의 후보 변경은 이미 로딩된 경우 호출자 zone에서 새 완료 Future를 반환하도록 보완한 부분이다. 앱 인증 Controller의 후속 변경과 저장소 자체의 변경을 혼동하지 않는다.

대표 근거:

- [후보 TripLibraryStore](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/trip_library/data/trip_library_store.dart)
- [main TripLibraryStore](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/trip_library/data/trip_library_store.dart)
- [후보 저장 목록 화면](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/trip_library/presentation/pages/saved_places_page.dart)
- [후보 API router](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/api/app/routers/v1.py)
- [후보 PlanningRepository](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/api/app/services/planning_repository.py)

## 2. 두 설계안이 공유할 책임

~~~mermaid
flowchart TD
  V[장소 상세와 저장 목록 View] --> M[ViewModel 또는 Controller]
  M --> R[저장 Repository 경계]
  R --> L[기존 기기 저장과 ID 상태]
  R --> T[기존 계정 저장 adapter]
  R --> P[현재 장소 조회 adapter]
  T --> A[Logto 경유 저장 API]
  A --> D[계정별 PlanningRepository]
~~~

설계도이며 구현 완료 구조가 아니다. 초기 Repository adapter는 기존 저장·동기화 경계를 감싸고, 같은 장소 집합을 별도 static store나 provider state에 중복 소유하지 않도록 한다. 영속화·동기화 listener의 소유자는 하나로 정한다.

| 구성 | 책임 | 넣지 않을 책임 |
|---|---|---|
| View | 상태 표시, 저장·해제·재시도·이동 이벤트 전달 | API 호출, 동기화 순서, DB DTO 조립 |
| ViewModel/Controller | 목록 표시 상태, 현재 언어·지역 요청, 이전 응답 무시, 사용자 동작 조율 | BuildContext를 Repository로 전달, 직접 SQL·HTTP |
| Repository | 저장 집합·계정 경계·조회 결합·실패와 재시도 정책 | 위젯·라우터·색상 |
| API·기기 adapter | 통신·직렬화·기기 영속화·기존 저장소 연결 | 화면별 로딩 spinner나 문구 선택 |

[Flutter 공식 아키텍처 안내](https://docs.flutter.dev/app-architecture/guide)의 View·ViewModel·Repository·Service 책임 분리를 현재 코드에 맞춰 적용한 안이다. MVVM을 특정 상태 관리 패키지의 사용 여부로 판정하지 않는다.

## 3. 동일한 예제로 비교할 두 안

| 기준 | A: 기존 Controller 보완 | B: Riverpod 점진 도입 |
|---|---|---|
| UI 상태 연결 | 주입한 Repository를 사용하는 ChangeNotifier/ValueListenable 기반 Controller | Repository provider와 목록 AsyncNotifier/상태 provider를 통한 주입·구독 |
| 기존 저장소 연결 | adapter가 기존 store를 감싸고 Controller가 구독·해제 | provider가 같은 adapter를 제공하고 lifecycle에서 구독·해제 |
| 변경 범위 | 상세·목록의 조회와 상태 처리부터 이동 | 해당 예제부터 provider/Consumer 적용. 다른 화면은 기존 구조 유지 |
| 학습 부담 | 현재 패턴 활용. lifecycle·주입 규칙을 문서로 통일해야 함 | 팀이 provider lifecycle·override·비동기 상태를 익혀야 함 |
| 독립 테스트 | fake Repository와 Controller 상태 전이 검증 | ProviderContainer/override와 fake Repository로 같은 시나리오 검증 |
| 계정 전환 | 계정 epoch·요청 epoch를 저장 정책과 함께 유지 | provider 재생성만으로 안전하다고 가정하지 않고 같은 epoch·취소 경계 유지 |
| 공존 | 기존 auth·docent Controller 유지 | 기존 Controller를 adapter로 연결, 전 화면 동시 이관 안 함 |
| 비용 판단 | 실제 이동할 책임·파일·테스트 목록으로 비교 | 같은 목록과 추가 provider 학습·공존 비용으로 비교 |

이는 설계 비교이지 두 구현을 작성하거나 새 패키지를 설치하는 작업이 아니다. 양쪽 모두 현재 lockfile의 Riverpod 2.6.1을 사실로 기록하며 버전 업그레이드를 끼워 넣지 않는다.

선택 절차: 프론트가 상세·목록의 동일 상태 전이와 예상 변경 범위를 제시 → 백엔드가 API·오류 의미 확인 → 기술 리드가 상태 소유권·계정 전환·검증 가능성을 검토 → 팀이 A/B와 선택 이유·첫 적용 범위·공통 파일 리뷰 담당을 기록한다. 합의 전에는 추천 표시를 선택으로 취급하지 않는다.

## 4. 공통 내부 계약 제안

아래 이름은 설계상의 역할명이며 아직 공개 Dart 타입이나 API가 아니다.

| 입출력 | 최소 의미 |
|---|---|
| observeSavedPlaces | 장소 ID 집합과 현재 장소 표시 정보, 조회 상태를 구독 |
| setSaved(placeId, saved) | toggle 호출 횟수 대신 의도한 최종 상태를 전달 |
| retryProjection | 현재 언어·지역의 장소 정보만 재조회 |
| retryAccountSync | 계정 연결·기기 보존 정책에 따라 원격 동기화를 재시도 |
| state | loading / empty / ready / error와 보존된 ID·누락 장소·작업 오류 |
| durability | 메모리 반영·기기 쓰기 성공/실패를 원격 저장 상태와 별도로 표현할 요구 |
| account sync | 기존 localOnly / syncing / synced / conflict / error와 연결 |

메모리 집합이 바뀌었다고 디스크 저장 성공을 단정하지 않는다. 목록 조회 실패가 저장 목록 삭제를 뜻하지 않는다. 기본 취향·이번 여행·방문 상태를 저장 장소 집합과 합치지 않는다.

## 5. 기존 API 계약 카드

모든 경로의 접두어는 /api/v1이다. 계정 저장은 Logto 사용자 인증과 issuer·subject 범위에 묶이며 이메일을 새 저장키로 쓰지 않는다.

### C-01 저장 목록 조회

- 요청: GET /me/saved-places. body 없음.
- 성공: HTTP 200, success envelope의 data.items. 각 항목은 place_id, source, nullable saved_at.
- 정상 부재: items가 빈 배열. 인증 실패나 DB 실패를 빈 성공으로 바꾸지 않는다.
- 화면 연결: 목록 비어 있음과 장소 정보 조회 실패를 분리한다.

### C-02 저장·해제

- 요청: PUT /me/saved-places/{place_id}, 선택 body의 source. 현재 Flutter adapter는 source를 db로 전달한다.
- 해제: DELETE /me/saved-places/{place_id}.
- 성공: HTTP 200, data의 place_id·saved·changed. 같은 최종 상태를 반복 요청하면 changed=false가 가능하다.
- 기존 서버 기본 source는 public_mvp_snapshot이다. 이는 provenance 필드 기본값이며 저장 API가 DB 없이 동작한다는 뜻이 아니다.
- 서버는 (issuer, subject, place_id) 범위로 삽입·삭제한다. PUT/DELETE 재호출은 중복 행을 만들지 않는다.
- 화면 연결: 기기 변경·원격 승인·동기화 실패를 구분하고 사용자 의도를 보존한다.

### C-03 인증·오류

- provider 로그인과 /me 계정 동기화는 별도다. 이름·이메일이 보이는 것만으로 LALA 저장 연결 성공이라고 판단하지 않는다.
- 기존 Logto gate는 USER_AUTH_REQUIRED(401), 잘못된 클라이언트 인증 경로는 UNAUTHORIZED(401)를 사용한다. 유효성 검사 오류는 422 경로를 확인한다.
- 네트워크 실패·잘못된 envelope는 adapter의 실패로 다룬다. PlanningRepositoryUnavailable의 구체적인 HTTP/envelope 매핑은 이 저장 흐름에서 별도 인수 검증할 공백이다. 임의의 503 계약을 추가하지 않는다.
- GET /me와 GET /me/preferences도 사용자 provision을 통해 DB 쓰기를 수행할 수 있다. 준비 단계의 읽기 전용 smoke로 실계정 호출하지 않는다.

### C-04 기본 취향·여행별 설정과의 구분

- 기본 취향은 GET/PUT /me/preferences. PUT은 expected_revision과 preferences를 사용한다.
- 여행별 설정은 GET/PUT/DELETE /me/plans/{plan_date}/preferences. PUT은 expected_revision과 override를 사용한다.
- 현재 계획 식별자는 plan_date다. 새로운 tripId 경로를 있다고 가정하지 않는다.
- 409 충돌과 서버 revision을 보존한다. saved_at·updated_at 기록은 충돌 제어를 대체하지 않는다.
- 저장 장소 PUT/DELETE에는 현재 expected_revision이 없다. 취향 계약을 그대로 복사해 저장 API의 필수 필드로 적지 않는다.
- SQL 064·065·066의 파일 존재는 대상 DB에 적용됐다는 증거가 아니다. 보류 기능 SQL 067·068과 적용 필요성을 각각 검토한다.

## 6. 구조 선택 전에 남길 검증 공백

| ID | 정적 검토에서 확인한 지점 | 구현 전에 확인할 내용 |
|---|---|---|
| R-01 | SavedPlacesPage는 지역·언어 기반 getPlaces 결과와 저장 ID를 결합 | 현재 조회에 없는 저장 ID를 유지하고 재조회 가능한지 |
| R-02 | 계정 연결 시 remoteSaved와 localSaved의 합집합 복원 | 해제 요청 실패 후 재시도에서 해제 의도가 사라지거나 저장이 복원되는지 |
| R-03 | 저장 쓰기 queue가 remote를 캡처하고 실행 시 epoch를 읽음 | 대기 작업 중 로그아웃·A→B 전환에서 이전 계정 작업·상태가 넘어오는지 |
| R-04 | SavedPlaceStore 변경과 ActionPreferences 쓰기는 별도 | 기기 쓰기 실패를 성공 문구로 감추지 않는지 |
| R-05 | 기본 취향 저장과 추천 요청 payload는 다른 경계 | 실제 plan_preference_context allowlist와 검색·지도 요청에 무엇이 전달되는지 |

R-02·R-03은 소스에서 도출한 검증 후보이며 이번에 재현한 버그 확정이나 수정 완료가 아니다. 양쪽 MVVM 안에 같은 시험을 적용하고, 실패하면 별도 수정 항목으로 기록한다. 동의·로그아웃 후 데이터 보존 정책 자체는 Q-04에서 팀이 결정한다.

## 7. 첫 예제 인계 묶음

프론트는 S-12·S-23의 상태·이벤트와 A/B 설계, 백엔드는 C-01~C-04 계약, 기술 리드는 기기·계정 상태 소유권과 DB 준비, PM은 저장 후 다시 찾는 행동의 성공 기준을 확인한다.

변경이 필요할 때만 API schema → OpenAPI → Dart 생성물·수동 adapter → UI → DB 호환성 순서로 영향 목록을 만든다. 계약을 설명하기 위해 코드 생성·마이그레이션·기존 저장 기능 재구현을 수행하지 않는다.
