# LALA-next Copilot 작업 진입점 초안

.github/copilot-instructions.md에 적용할 초안이다. 먼저 저장소 루트 AGENTS.md를 읽고 공통 규칙을 따른다.

현재 문서 입구는 docs/planning/team-development-preparation-20260909/README.md와 03-next-decisions.md다. 현재 작업은 개발 착수 준비이며 기능 구현·화면 숨김·운영 변경으로 확장하지 않는다.

지도는 후보의 언어별 혼합 구성이 기본 방향이다. 후보 8aa184e3를 조건부 통합 기준으로 추천하지만 Draft PR 스택 정리·검증 뒤의 최종 시작 SHA는 아직 미확정이다. 첫 저장 slice에는 기존 Controller 보완을 추천하며 팀 채택 전에는 확정으로 쓰지 않는다.

공용 개발 API를 우선한다. GitHub dev 배포 설정은 확인됐지만 현재 Azure 런타임의 접근·가동·분리 상태는 미검증이다. 과거 단일 Mac·Cloudflare Tunnel·LaunchAgent 절차는 그 운영 환경을 명시적으로 다룰 때만 적용한다.

시크릿·개인정보 비노출, 실제 DB/API 데이터의 정직성, readiness 확인과 역할별 리뷰 원칙은 유지한다. 적용 후 새 Copilot 세션에서 07-common-guidelines.md의 인수 질문을 확인한다.
