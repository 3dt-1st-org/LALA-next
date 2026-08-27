# 03. 상태와 데이터 바인딩

## 1. 공통 상태 행렬

| 상태 | 사용자 문구 | 기본 action | 데이터 표시 |
| --- | --- | --- | --- |
| initial | 화면 목적에 맞는 시작 상태 | 입력·선택 | 없음 |
| loading | `불러오는 중` | 취소가 필요한 긴 작업만 제공 | 이전값을 새 값처럼 표시 금지 |
| loaded | 실제 데이터 | 주요 기능 action | source/freshness 규칙 적용 |
| empty | `조건에 맞는 결과가 없어요` | 조건·지역 변경 | 예시 item 금지 |
| stale | `마지막 확인 데이터를 보여드려요` | 새로고침 | 마지막 시각 필수 |
| network_error | `연결하지 못했어요` | 재시도 | 값 부재를 empty로 위장 금지 |
| unavailable | `현재 확인할 수 없어요` | 대체 경로 | `-`, `0`, 랜덤값 금지 |
| disabled | 기능 비활성 이유 | 텍스트 등 대체 기능 | 활성 control처럼 표현 금지 |
| permission_denied | 권한 없이 가능한 경로 안내 | 재시도·직접 선택 | 좌표 추정 금지 |
| auth_required | 로그인 시 가능한 action 설명 | 로그인·취소 | 탐색 상태 보존 |

## 2. 실제 모델 바인딩

| UI 의미 | 현재 모델·필드 | 소비 코드 | 부재 처리 |
| --- | --- | --- | --- |
| 장소 identity | `LalaPlace.placeId` | `SelectedPlaceStore` | ID 없으면 선택 action 금지 |
| 장소명 | `nameKo`, `nameEn`, `name` | `placeDisplayName` | 선택 언어 fallback 규칙 적용 |
| 장소 category | `LalaPlace.category` | category badge/pin | unknown은 중립 treatment |
| 거리 | `LalaPlace.distanceM` | rail/detail | 좌표 기준임을 유지, route 시간으로 표현 금지 |
| 장소 이유 | `LalaPlace.reason` | rail/dock/detail | null이면 이유 영역 숨김 |
| dataset 출처 | `LalaPlacesResponse.source` | rail/dock | 빈 값이면 source chip 숨김 |
| dataset 신선도 | `LalaPlacesResponse.dataAsOf` | dock/detail | parse 불가·null이면 숨김 |
| upstream 출처 | `LalaPlace.upstreamSource` | 상세 메타 | 의미 label을 확인한 경우만 표시 |
| 장소 이미지 | `LalaPlace.imageUrl` | place image | 검증 실패 시 category fallback |
| 날씨 값 | `LalaWeather.temp`, `icon`, `outdoorStatus` | map/weather/plan | envelope error면 unavailable |
| 날씨 기준 시각 | `LalaWeather.recordTime` | weather/detail | null이면 시각 문구 숨김 |
| 날씨 출처 | `LalaWeather.source` | weather/detail | 빈 값이면 출처 문구 숨김 |
| 미세먼지 | `dust.pm10`, `pm25`, grade fields | weather/plan | 값·등급 개별 부재 처리 |
| 일정 슬롯 | `LalaDailyPlan.slots` | plan | 슬롯 없음은 unavailable reason |
| 이동시간 | `travelTimeFromPreviousMinutes` | plan | 항상 estimated badge |
| 운영시간 | `estimatedOpeningHours` | plan | 항상 estimated badge |
| 슬롯 상황 | `forecastWindow`, `airQualityBad`, `closureState` | plan | optional projection 그대로 처리 |
| 개입 비교 | `originalSlot`, `alternativeSlot`, `reason` | recovery UI | 둘 중 하나 없으면 비교 금지 |
| 도슨트 텍스트 | `LalaDocentScript.script` | tour script card | error 시 retry/텍스트 없음 상태 |
| 도슨트 생성 시각 | `generatedAt` | docent meta | 값이 있을 때만 표시 |
| 저장 상태 | `SavedPlaceStore` | map/search/detail/plan | 인증 실패 시 원상 복구 |
| 집계 mention | `mentionCount`, `organicMentionCount` | Local Signals | 실제 값만 표시 |
| 집계 score | `sentimentScore`, `reviewQualityScore` | Local Signals | null이면 숨김 |
| 집계 신선도 | `lastRefreshedAt ?? computedAt` | section header | null이면 `시점 미확인` |

## 3. 아직 필요한 계약 보강

다음 UI는 현재 필드만으로 완전한 의미를 만들기 어렵다. 구현자가 client에서 값을
추론하지 말고 API 계약 보강을 먼저 검토한다.

| 요구 | 부족한 계약 | 임시 UI |
| --- | --- | --- |
| 검색 인기순 | 서버 정렬 기준·query echo | control 숨김 또는 disabled |
| 실제 이동 수단·경로 | routing provider 결과·관측 시각 | `예상 이동시간`, 수단 미확인 |
| 실제 운영시간 | authoritative hours/source | category 추정임을 명시 |
| 이미지 권리 | rights/license/verified timestamp | 이미지 출처 주장 금지 |
| Local Signals 표본 의미 | score denominator/quality basis | score 숨김 가능 |
| 확장 언어 콘텐츠 | JA/zh 전용 서버 콘텐츠 | EN fallback 고지 |

## 4. 요청·경쟁 상태

- 지도 bounds, 검색어, 지역, 언어가 바뀔 때 request generation id를 증가시킨다.
- 응답이 도착했을 때 generation id와 현재 context가 다르면 결과를 폐기한다.
- 새 요청이 실패해도 이전 성공 결과를 현재 요청 결과처럼 표시하지 않는다. 보존할
  경우 stale 상태와 이전 context를 명시한다.
- 선택 장소가 새 결과 배열에 없다는 이유만으로 즉시 해제하지 않는다. region 변경,
  사용자 명시 해제, canonical ID 유효성 중 하나가 확인될 때 해제한다.

## 5. 분석·개인정보 경계

- Local Signals와 analytics에 정밀 좌표, raw review, author, external URL을 전달하지
  않는다.
- UI telemetry는 화면·action·canonical ID의 필요한 최소 집합만 사용한다.
- 내부 score와 reason 상세는 사용자 요청 시 표시하되 formula·moderation threshold는
  노출하지 않는다.
- 로그에 auth token, env 값, provider payload, raw AI response를 남기지 않는다.
