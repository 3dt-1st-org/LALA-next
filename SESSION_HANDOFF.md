# 세션 핸드오프 — 새 세션용 컨텍스트

> 이 파일을 읽고 작업을 이어가세요. 메모(~/.claude/projects/-Users-geondongkim-LALA-next/memory/)도 참조.

## 현재 상태 (2026-07-24)
- **PR #25~49 (25개) merge 완료** — 구조기반 계획(3스트림) + ONMU UI/UX + 커뮤니티 전부 구현.
- main.dart 9,814→43줄. 3-탭 모바일 네비게이션(검색/지도/플랜) + 온보딩 + 커뮤니티(게시판/댓글/좋아요/팔로우/채팅 WebSocket).
- Vercel 배포 완료(lala-next.cloud). SQL 마이그레이션(060/061) 운영 DB 적용 완료(SSM).
- 커뮤니티 API live: `GET /api/v1/community/posts` → 200, `GET /api/v1/community/chat/rooms` → 200.

## 긴급 이슈 — 상태 (2026-07-24 갱신, APK 재빌드+검수 완료)
1. ✅ **카카오맵 정상 렌더링 확인** — 키 해시 등록 완료 후 WebView(`lala-next.cloud/kakao-map-embed.html`)로 지도 타일/도로/건물 정상 표시. (JavaScript 키 `b95e9836f1c3ae06d0a609a9e25566bc` 사용. 참고: 앱 코드는 네이티브 앱키가 아닌 JS 키만 소비함.)
2. ✅ **APK 빌드 명령**(그대로 사용 가능):
   ```bash
   cd apps/flutter_app
   flutter build apk --debug \
     --dart-define=LALA_API_BASE_URL=https://api.lala-next.cloud \
     --dart-define=KAKAO_JAVASCRIPT_KEY=b95e9836f1c3ae06d0a609a9e25566bc \
     --dart-define=LALA_UI_LANGUAGE=ko
   ```
3. ✅ **수원 하드코딩 제거 완료** — `app/dashboard.dart:36` `_bundledStartupPlaces = <LalaPlace>[]` (이미 빈 리스트, 커밋 불필요 — 4개 수정파일은 실제 diff 없음/stat 캐시).
4. ✅ **검색/플랜 탭 빈 화면 아님** — 둘 다 정상 empty-state UI 렌더링 (검색: "최근 검색어가 없습니다"+인기검색어 / 플랜: "아직 만든 플랜이 없어요" + "플랜 만들기" CTA).
5. ✅ **흰 화면 해결** — 114KB 캡쳐(이전 28KB=백지 시그니처). 온보딩 4스텝 + 3탭 전부 정상.
6. ✅ **POI 데이터 복원 완료 (2026-07-24)** — 원인은 데이터 유실이 **아님**. 프로덕션 `travel.places`엔 81행이 있었으나 희소(spars)하여 기기 위치(오산) 반경엔 0건 → "주변에 추천 장소가 없어요". (초기 API 0 응답은 내가 `radius` 대신 정확한 파라미터 `radius_m`을 안 써서 디폴트 1km가 적용된 탓도 있음 — API 자체는 정상.)
   - **로컬 Docker DB(`127.0.0.1:55433`) → 프로덕션 RDS** 로 **additive upsert(ON CONFLICT DO NOTHING)** 복원. S3+SSM 경로 사용(SG 미개방). 절차: [docs/operations/data-restore-local-to-prod.md](docs/operations/data-restore-local-to-prod.md).
   - 결과: places **81→2,546**, weather 374→454, events 115→479, rag 312→2,263, franchise 500→11,712, posts 0→155, mentions 0→168. **기기 오산 반경 3km: 0→3~6건** (노아커피랩/카페포렛/그레이브릭스커피 고덕점 등). 디바이스 검수 완료.
   - 남은 소폭: (a) `economy.card_spending_area_monthly` 로컬 행은 FK(`source_file_id`) 미복원 부모테이블 때문에 스킵 — 단 prod는 systemd 파이프라인으로 매일 최신 3,650행 보유라 영향 없음. (b) `community.posts` DB엔 155행이나 `GET /api/v1/community/posts` 여전히 0 → 표시 상태/공개 필터 의심(별도 조사).

## 작업 스타일 (사용자 요구)
- **prod 레벨**, 묻지 말고 베스트안 추천 후 즉시 구현.
- **구현 먼저 끝까지** → 이후 다듬기.
- **컨트롤러 모드**: 이 세션이 가벼워야 → 서브에이전트(Agent tool)로 무거운 작업 위임.
- **Orca 활용**: 워크트리(작업 가시성) + 브라우저(UI 검수, lala-next.cloud).
- **git 워크플로**: 커밋 자주, push 1~3커밋마다, 목표 달성 시 PR→merge. 작업 끝나면 워크트리 정리.
- **설치 자유롭게** (Java 17, openapi-generator, brew 등 이미 설치됨).

## 키 경로/정보
- 저장소: `/Users/geondongkim/LALA-next` (git, github.com/3dt-1st-org/LALA-next)
- Orca repoId: `b2a3e526-35cb-4add-958f-6eb1b363ca96`
- Android 기기: `R3CX20PCDWY` (adb)
- API: `https://api.lala-next.cloud` (healthz/readyz ok, 커뮤니티 live)
- Web: `https://lala-next.cloud` (Vercel, ONMU UI 배포됨)
- Orca 브라우저 pageId: `4f96b564-20b9-4721-ad60-ec9852bdc5fe`
- 계획서: `~/.claude/plans/declarative-jumping-dream.md`
- 메모: `~/.claude/projects/-Users-geondongkim-LALA-next/memory/` (MEMORY.md 인덱스)
- auth-callback.html 미커밋 변경 보존 (사용자 작업, 건드리지 말 것).

## 남은 작업
1. **카카오 키 해시 등록 후 APK 재빌드 + 스크린샷** (최우선)
2. **UI 점검/개선** (오버플로우, 빈 화면 처리, 모바일 최적화)
3. **Riverpod 상태 이전** (_LalaHomePageState 50상태 → 컨트롤러)
4. **추가 커뮤니티** (추천 피드 pgvector — 옵션)

## 새 세션 시작 명령
```bash
cd /Users/geondongkim/LALA-next && claude "SESSION_HANDOFF.md를 읽고 작업을 이어가. 카카오 키 해시 등록 완료되면 APK 재빌드 + 캡쳐 + UI 분석 진행해."
```
