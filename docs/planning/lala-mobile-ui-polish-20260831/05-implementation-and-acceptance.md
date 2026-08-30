# 05. 구현·수용

## 구현 단위

1. palette/theme/tokens
2. S1 travel rows + quick language popup + S2 language rows
3. region sheet pending/confirm truth model
4. search header/chips/result evidence hierarchy
5. focused tests, full Flutter gates, web runtime captures

## 자동 검증

- `flutter analyze`
- 온보딩·지역·검색 focused tests
- `flutter test`
- `git diff --check`
- 저장소 pre-commit

## 시각 수용 행렬

| ID | 화면 | 필수 상태 | 판정 |
| --- | --- | --- | --- |
| P-01 | 온보딩 | initial/selected | tonal icon, vivid selected border, CTA 상태 |
| P-02 | 언어 메뉴 | EN 또는 JA 선택 | 흰 메뉴, 선택 행 blue soft, check |
| P-03 | 검색 | 실제 loaded | 사진/이유/카테고리/지역/거리/근거 분리 |
| P-04 | 지역 | open/row pending | 현재 지역과 목록 필터 구분, CTA 고정 |
| P-05 | 지역 | apply | 시트 닫힘 후 검색 지역 label·API config 갱신 |

## 실패 조건

- `전체 지역 보기`가 현재 선택 지역처럼 check 처리됨.
- 행 탭만으로 API 지역이 즉시 변경됨.
- source/freshness를 실제 응답 없이 표시함.
- `인기순`을 실제 계약 없이 노출함.
- 회색 surface가 화면 대부분을 차지하거나 category가 한 색조로만 보임.
- 393×852에서 CTA, 하단 navigation, 마지막 목록 행이 겹침.
