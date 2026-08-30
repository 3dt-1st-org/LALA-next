# LALA 기능 중심 UI 통합 계약

> 문서 버전: 1.0
> 기준일: 2026-08-27 (Asia/Seoul)
> 상태: 구현 전 디자인·동작 계약
> 선행 문서: `docs/product/lala-service-functional-spec.md`

## 목적

이 패킷은 LALA의 기능 정의서와 Stitch A/B 시안을 실제 Flutter 구현으로 연결한다.
구현자가 PNG나 HTML을 OCR로 복제하지 않고, 사용자 흐름·상태·데이터 출처·반응형
규칙을 문서에서 직접 구현할 수 있게 하는 것이 목적이다.

Stitch 산출물은 시각 참고 자료일 뿐 런타임 진실이나 fixture가 아니다. 화면에 보인
혼잡도, 언급 수, 거리, 무료 입장, 이동시간, 출처·신선도는 실제 API 응답이 없으면
표시하지 않는다.

## 핵심 원칙

1. **근거성**: 추천 이유와 출처·신선도는 같은 근거 단위에 결합한다.
2. **방문객 접근성**: 첫 질문 전에 언어를 바꿀 수 있고, 위치 권한 없이도 전국
   지역 선택으로 핵심 기능에 진입할 수 있어야 한다.
3. **회복성**: 실패·거부·데이터 부재 뒤에 사용자가 실행할 다음 행동을 제공한다.
4. **실데이터 정직성**: mock/demo/bundled 장소를 정상 경로에 주입하지 않는다.
5. **상태 공유**: 언어, 지역, 선택 장소, 저장, 일정은 탭을 넘어 하나의 상태로
   동기화한다.

## 문서 구성

| 파일 | 내용 |
| --- | --- |
| `00-product-and-visual-ground-truth.md` | 근거 우선순위, 채택·금지 규칙, 디자인 토큰 원칙 |
| `01-information-architecture-and-flows.md` | 4탭 IA, Mermaid 사용자 흐름, 공통 상태 소유권 |
| `02-screen-contracts.md` | 온보딩·검색·지도·상세·일정·Local Signals 화면 계약 |
| `03-state-and-data-bindings.md` | 상태 행렬, 실제 Flutter/API 필드 바인딩, 부재 처리 |
| `04-responsive-accessibility-and-localization.md` | 모바일·웹 규칙, 접근성, KO/EN/JA/zh 처리 |
| `05-implementation-slices.md` | 구현 순서, 파일 소유권, 테스트·PR 경계 |
| `06-visual-acceptance-matrix.md` | 캡처·실터치·데이터 진실성 수용 기준 |

## 참조 우선순위

충돌할 때 다음 순서로 판정한다.

1. 현재 API/Flutter 계약과 보존 불변량
2. `docs/product/lala-service-functional-spec.md`
3. 이 패킷의 상태·상호작용·데이터 바인딩
4. `docs/planning/lala-mobile-visual-contract-20260728/`
5. Stitch B의 온보딩·검색·일정·상세 개선 방향
6. Stitch A의 지도·Local Signals 정보 구조
7. Stitch의 수치·문구·이미지 예시

## 구현 완료 정의

문서 추가만으로 UI 완료가 아니다. 다음이 모두 있어야 해당 화면을 완료로 판정한다.

- exact-head Flutter 코드와 focused test
- `flutter analyze`, 관련 `flutter test`, 저장소 CI 통과
- 실제 API 데이터 또는 정직한 empty/unavailable 상태
- iPhone 17 Pro와 모바일·데스크톱 웹의 서로 다른 상태 캡처
- 터치로 재현한 상태 전이와 cold relaunch 복원 증거
- 가짜 수치·중복 캡처·VM state injection 부재
