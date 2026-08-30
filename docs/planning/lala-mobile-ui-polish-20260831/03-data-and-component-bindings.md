# 03. 데이터·컴포넌트 바인딩

| UI | 소스 | 금지 |
| --- | --- | --- |
| S1 문구 언어 | `OnboardingState.language` | 유형 선택으로 사용자 override 덮기 |
| S2 미리 선택 | S1에서 확정된 language | 무조건 KO/EN으로 초기화 |
| 현재 탐색 지역 | `RegionContextStore.current` 또는 공개 기본값 | province filter를 현재 지역으로 표시 |
| 지역 행 check | `ManualLocationOption.id == pending/active regionId` | `all` chip check를 지역 선택으로 읽히게 함 |
| 검색 장소 | `LalaPlacesResponse.places` | fixture/demo 카드 정상 경로 |
| 추천 이유 | `LalaPlace.reason` | 생성 시안 문구 |
| 출처 | response `source` | 장소별 source와 합성 |
| 신선도 | response `dataAsOf`, place freshness | 현재 시각 발명 |

## 컴포넌트 변경

- `LalaVisualColors`: vivid multi-accent palette SSOT.
- `OnboardingLanguageMenu`: menu style 및 선택 행 전용 위젯.
- `ManualLocationSheet`: `activeRegionId`, `activeRegionLabel`, pending 선택, confirm CTA.
- `ManualLocationTile`: `selected` 상태와 check affordance.
- `SearchPage`: active region을 sheet에 전달; 카테고리색·카드 근거 계층 사용.

`ManualLocationSheet`의 새 입력은 optional로 두어 기존 호출자와 테스트를 깨지 않으며,
지역 context가 있는 호출자는 실제 값을 전달한다.
