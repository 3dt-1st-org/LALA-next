# LALA 모바일 UI 컬러·신뢰성 개선 계약

이 문서는 생성 시안의 시각적 장점을 현재 앱의 실제 데이터·복구 동작 위에 적용하는
구현 계약이다. 시안 이미지는 방향 참고 자료이며 런타임 데이터나 픽셀 복제의 근거가
아니다.

## 문서 순서

1. `00-visual-ground-truth.md` — 색상·타입·표면 원칙
2. `01-flows-and-state-truth.md` — 온보딩·언어·지역 흐름
3. `02-screen-contracts.md` — 화면별 와이어프레임과 치수
4. `03-data-and-component-bindings.md` — 실제 상태와 컴포넌트 연결
5. `04-responsive-accessibility-localization.md` — 반응형·접근성·다국어
6. `05-implementation-and-acceptance.md` — 구현 단위와 검증 행렬

## 비목표

- 실제 인기도 지표가 없는데 `인기순`을 제공하지 않는다.
- 출처·신선도·지역을 시안 문구나 fixture로 채우지 않는다.
- 지도 공급자 이관, API 계약, 추천 알고리즘은 이 작업에서 변경하지 않는다.
- 회색을 없애는 대신 의미 없는 장식색을 늘리지 않는다.
