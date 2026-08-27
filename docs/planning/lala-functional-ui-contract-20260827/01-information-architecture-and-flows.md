# 01. 정보 구조와 사용자 흐름

## 1. 최종 정보 구조

```text
앱 시작
├─ 언어 선택(항상 접근 가능)
├─ 여행 유형
├─ 위치 사용 또는 전국 지역 직접 선택
└─ 완료 상태·언어·지역 cold-start 복원

메인 하단 탭
├─ 검색
├─ 지도
├─ 일정
└─ 로컬 신호

공통 overlay / secondary surface
├─ 전국 지역 선택 sheet
├─ 장소 상세·도슨트 sheet
├─ 날씨 상세 sheet
├─ 설정·계정 sheet
└─ 로그인 필요 dialog
```

커뮤니티는 현재 라우트와 화면이 있지만 이 4탭 계약에 억지로 끼우지 않는다.
Local Signals의 집계형 정보와 사용자 커뮤니티 게시물을 같은 카드로 섞지 않는다.

## 2. 최초 진입과 회복 흐름

```mermaid
flowchart TD
    A[앱 시작] --> B{저장된 온보딩 완료?}
    B -- 예 --> C[언어·지역·선택 상태 복원]
    C --> D[지도 또는 마지막 안전 탭]
    B -- 아니오 --> E[언어 즉시 선택]
    E --> F[여행 유형 선택]
    F --> G{위치 사용?}
    G -- 허용 --> H[권한 요청]
    H --> I{좌표 획득?}
    I -- 예 --> J[현재 위치 지역 context]
    I -- 일시 거부 --> K[재시도·지역 직접 선택·나중에]
    I -- 영구 거부 --> L[설정 열기·지역 직접 선택·나중에]
    G -- 직접 선택 --> M[시도·시군구 검색/최근 선택]
    K --> M
    L --> M
    J --> N[온보딩 완료]
    M --> N
    N --> D
```

## 3. 장소 탐색과 공통 선택 상태

```mermaid
flowchart LR
    A[검색 결과] --> S[SelectedPlaceStore]
    B[지도 pin] --> S
    C[추천 rail] --> S
    D[Local Signals 장소 보기] --> S
    S --> E[지도 pin 강조]
    S --> F[추천 rail 위치 동기화]
    S --> G[장소 상세 sheet]
    S --> H[날씨·도슨트·저장 action]
    H --> I[일정 context]
```

모든 이동은 `canonical_place_id`로 연결한다. 표시 이름이나 배열 index를 identity로
사용하지 않는다. 탭 이동 뒤에도 선택 장소를 유지하되, 새 region context에 속하지
않으면 사용자에게 보존/해제 이유를 알리고 안전하게 해제한다.

## 4. 일정 개입과 undo

```mermaid
stateDiagram-v2
    [*] --> PlanLoaded
    PlanLoaded --> InterventionAvailable: 날씨·대기질·휴무 변화
    InterventionAvailable --> Compare: 대체 보기
    Compare --> PlanLoaded: 기존 일정 유지
    Compare --> Applied: 대체 적용
    Applied --> PlanLoaded: Undo
    InterventionAvailable --> Unavailable: 유효한 대체 후보 없음
    Unavailable --> PlanLoaded: 닫기
```

`reason`, `trigger_type`, `trigger_factors`, `original_slot`,
`alternative_slot`이 없으면 비교 UI를 발명하지 않는다. 적용은 명시적 사용자 action
뒤에만 수행하고, 성공 후 undo snackbar를 제공한다.

## 5. 저장·인증 회복

```mermaid
flowchart LR
    A[저장 아이콘] --> B{인증됨?}
    B -- 예 --> C[멱등 save/unsave]
    C --> D[SavedPlaceStore 갱신]
    D --> E[지도·검색·상세·일정 동기화]
    B -- 아니오 --> F[로그인 필요 안내]
    F --> G{로그인 진행?}
    G -- 예 --> H[Logto SDK]
    H --> I[원래 장소·action 복원]
    I --> C
    G -- 아니오 --> J[탐색 상태 유지]
```

## 6. 공통 상태 소유권

| 상태 | SSOT | 소비 화면 |
| --- | --- | --- |
| 언어 | `OnboardingState.languageListenable` | 전 화면 |
| 지역 | `RegionContextStore` | 검색·지도·일정·Signals |
| 선택 장소 | `SelectedPlaceStore` | 검색·지도·상세·Signals |
| 저장 장소 | `SavedPlaceStore` + `ActionPreferences` | 지도·검색·상세·일정 |
| 일정 context | `PlanContextStore` | 지도·일정 |
| 방문 상태 | `SlotVisitStore` | 일정·전환 측정 |

화면 내부 duplicate state는 애니메이션·입력 초안처럼 일시적인 UI 상태에만 허용한다.
