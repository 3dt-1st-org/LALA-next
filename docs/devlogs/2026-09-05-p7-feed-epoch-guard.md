# P7 커뮤니티 피드 stale-response epoch guard — 2026-09-05

## 배경

S-40 피드 레이스: `_loadMore()`가 날린 페이지 요청이 풀 리로드(당겨서 새로고침,
작성 복귀, 재시도)보다 늦게 도착하면, 이미 교체된 리스트에 옛 페이지 행을 붙이거나
옛 에러로 재시도 행/전체 에러 화면을 되살렸다. 풀 리로드 두 개가 겹쳐도 먼저 시작한
요청의 늦은 결과가 최신 결과를 덮어썼다. 타이머·취소 가능한 의존성 없이, 페이지가
소유하는 단조 증가 요청 세대(generation) 하나로 닫는 최소 수정이다.

## 정확한 동작

- `CommunityFeedPage` 상태에 `_feedGeneration`(단조 증가 int) 추가.
- 모든 풀 `_load`는 진입 시 세대를 먼저 전진시킨다(`++_feedGeneration`). 응답
  성공/에러 양쪽 모두 `generation != _feedGeneration`이면 `mounted` 검사와 함께
  완전히 무시된다.
- `_loadMore`는 시작 시점의 세대와 `offset = _posts.length`를 캡처한다. 풀 리로드가
  세대를 앞서면 늦은 성공(행 추가)도 늦은 실패(재시도 행)도 모두 버린다.
- 풀 리로드 시작 시 pagination 플래그를 일관되게 정리한다: 기존
  `_loadMoreFailed = false`에 `_isLoadingMore = false`를 추가 — 진행 중이던
  stale load-more가 바닥 스피너를 남기지 않는다(`_onScroll`의 재진입 방지도
  최신 세대에서 정상 동작).
- 공개 API, 로딩/에러/빈/재시도 문구, 인증 동작, 페이지네이션 의미(20개 페이지,
  `_hasMore = posts.length < total`), 클라이언트 소유권(`_ownsClient`)은 불변.

## 테스트

`community_feed_epoch_guard_test.dart` — Completer로 요청 완료 순서를 정확히
제어하는 결정적 위젯 테스트 4개:

1. load-more 진행 중 풀 리프레시가 교체 데이터로 완료 → 옛 load-more가 늦게
   성공: stale 행 부재 + 스피너/재시도 행 부재.
2. 같은 순서로 옛 load-more가 늦게 실패: stale 재시도 행/에러 문구 부재.
3. 풀 로드 두 개가 역순 완료: 최신 세대만 반영 — (a) 최신 에러가 옛 성공을,
   (b) 최신 성공이 옛 에러를 이긴다.
4. 기존 페이지네이션 재시도·리프레시 동작은 `community_surface_states_test.dart`
   등 기존 테스트가 그대로 통과(요청 오프셋 시퀀스도 검증).

## 검증

- `flutter test test/features/community/` — 56 passed.
- `flutter analyze` — 이슈 0.
- `flutter test`(전체) — 1129 passed.
- `uv run pre-commit run --all-files`, `git diff --check` — 통과.
