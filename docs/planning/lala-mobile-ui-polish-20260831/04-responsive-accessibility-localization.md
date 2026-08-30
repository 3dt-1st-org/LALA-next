# 04. 반응형·접근성·다국어

## 반응형

- 기준 모바일 393×852, 추가 검증 320×568, 402×874, 1280×900.
- 고정 CTA는 `SafeArea`와 함께 배치하고 지역 목록의 마지막 행이 가려지지 않는다.
- 일본어·중국어 긴 검색 placeholder는 한 줄 ellipsis로 처리한다.
- 온보딩 5개 언어 행은 본문만 스크롤하며 CTA는 유지한다.

## 접근성

- 모든 tap target은 최소 44×44dp.
- 선택 상태는 `Semantics(selected: true)`와 check 아이콘을 함께 제공한다.
- `전체 지역 보기`는 `ChoiceChip`의 목록 필터로만 읽힌다.
- 지역 행의 label은 `지역명, 광역명, 선택됨/선택 안 됨`을 전달한다.
- 비활성 CTA는 disabled semantics를 보존한다.
- 텍스트와 배경은 일반 텍스트 4.5:1, 큰 텍스트 3:1 이상을 목표로 한다.

## 현지화

- KO, EN, JA, zh-Hans, zh-Hant 다섯 locale을 유지한다.
- UI 문구는 `lalaCopyMulti`를 사용한다.
- 지역 정적 데이터가 KO/EN만 있을 때 JA/ZH는 EN label로 정직하게 fallback한다.
- 언어 메뉴의 endonym은 의도적으로 각 언어 표기를 혼합하는 유일한 화면 요소다.
