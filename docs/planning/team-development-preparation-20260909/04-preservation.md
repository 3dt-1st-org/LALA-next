# 작업물 보존 목록

기준일: 2026-09-09. 이 목록은 무엇을 보존했는지와 무엇이 아직 로컬에만 있는지 구분한다.

후속 준비: 06~11 문서와 proposals의 공통 지침·도구별 진입점 초안을 추가했다. 기존 회의록·PDF·로컬 AGENTS·환경 파일·다른 worktree는 수정하지 않는다. 활성 지침 파일의 실제 적용과 추적 전환은 아직 수행하지 않았으며, 초안의 격리 검증은 [이번 검증 기록](11-validation.md)에 따로 기록한다.

## 1. 코드 체크포인트

| 구분 | 보존 태그 | 대상 SHA |
|---|---|---|
| 시작 로컬 | `snapshot/20260909/local-preparation` | `1dc09a74b9704bc60a2c2fe7567be5e4ae69eb30` |
| 원격 main | `snapshot/20260909/main-preparation` | `9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6` |
| 9/7 후보 | `snapshot/20260909/candidate-preparation` | `8aa184e375f381fa4de0a97bca82ffa3e59ba836` |

세 커밋은 조사 시 이미 기존 원격 브랜치에 있었다. 위 태그는 향후 브랜치 정리와 별개로 찾기 위한 보존 표식이며, 릴리스·운영 승인을 뜻하지 않는다.

준비 문서는 `docs/team-preparation-20260909` 브랜치에 기록한다. 원격 반영 여부와 최종 커밋은 실제 push 후 전달하는 결과를 기준으로 한다. main과 dev는 갱신하지 않는다.

준비 문서의 첫 커밋 `111211dc`와 위 체크포인트 태그 3개는 원격에 보존했다. 이후 사용자가 요청한 병합 완료 원격 브랜치 정리 대상과 별도 복구 태그는 [원격 브랜치 정리](05-remote-branch-cleanup.md)에서 관리한다. 기존 브랜치 이름이 사라져도 보존 태그와 SHA는 남는다.

## 2. worktree와 미저장 파일

15개 등록 worktree를 읽기 전용으로 확인했으며, 추적 중인 코드의 미커밋 변경은 발견하지 못했다.

| 대상 | 조사 결과 | 처리 |
|---|---|---|
| 기존 구현 worktree | HEAD들은 원격 브랜치 또는 main/후보 이력으로 확인 가능 | 기존 브랜치·worktree를 삭제하거나 이동하지 않음 |
| 계정 동기화 worktree의 `progress.md` | 이전 중간 SHA 기준의 진행 기록 | [역사 기록 사본](../../archive/preparation-20260909/account-sync-progress.md.txt) 보존. 현재 상태를 주장하는 근거로 사용하지 않음 |
| 채팅 검증 worktree의 `test_pr201_preflight_probe.py` | 이전 코드의 결함을 재현하던 일회성 probe | [비실행 사본](../../archive/preparation-20260909/pr201-preflight-probe.py.txt) 보존. 제품 테스트로 편입하거나 재실행하지 않음 |
| 시작 폴더의 `_workspace/`, `tmp/` | 사업계획서 중간 텍스트·PDF 렌더·검수 작업 파일 | 로컬 그대로 유지. 공개 Git에 일괄 추가하지 않음 |

원본 두 파일은 다른 worktree에 그대로 남긴다. 사본은 `.txt`로 보관해 테스트 수집과 기능 구현에 섞이지 않도록 한다.

## 3. 문서·PDF 원본

저장소가 공개 상태이므로 회의 원문·개인 일정·서류 준비 내용·시각 자료 전체를 일괄 공개하지 않는다. 아래 파일은 **기존 로컬 위치 그대로 보존**하고 내용 해시를 기록했다. 해시를 기록한 것은 원본의 원격 백업을 완료했다는 뜻이 아니다.

| 원본 | 로컬 위치 | 크기·특성 |
|---|---|---|
| 화면 비교 v3 | `output/pdf/lala-screen-three-way-comparison-v3-20260907.pdf` | 74,034,018 bytes · 41쪽 |
| 화면 비교 v3.1 팀 공유본 | `output/pdf/lala-screen-three-way-comparison-v3-1-team-20260907.pdf` | 74,324,682 bytes · 78쪽 |
| v3 Markdown | `output/local/lala-screen-three-way-comparison-20260907/lala-screen-three-way-comparison-v3-20260907.md` | 원본 이미지·코드 연결 포함 |
| v3.1 Markdown | `output/local/lala-screen-three-way-comparison-20260907/lala-screen-three-way-comparison-v3-1-team-20260907.md` | 역할·구현 인계 설명 포함 |
| 9/8 회의록 | `output/docs/lala-dev-meeting-20260908-minutes.md` | 원문 유지, 공개용 개발 요약은 별도 |
| 9/8 보정 스크립트 | `output/docs/lala-dev-meeting-20260908-corrected-transcript.md` | 대화 원문 성격의 로컬 자료 |
| 9/9 착수 전 조사 | `output/docs/lala-team-development-readiness-audit-20260909.md` | 상세 로컬 근거와 조사 범위 |

SHA-256:

```text
e6da60c13e4328038269a955107fc4c2e159e039133e6b5bcf4f8361a7814284  lala-screen-three-way-comparison-v3-20260907.pdf
965ef362584f461c0825baf41e72e7ec8c7f9a0c807317f71ce95acf8f9a8b3d  lala-screen-three-way-comparison-v3-1-team-20260907.pdf
e0c9d3120c97b7cfb93bbecee0cfc75b5f18b8006b88feda0c9d0fa32e727f7f  lala-screen-three-way-comparison-v3-20260907.md
de3e01c9fde154388fb0e58536630fa5d1e870d8220f12363840bc40daeb021a  lala-screen-three-way-comparison-v3-1-team-20260907.md
677e33a536a181edb01369fa3033c751c0e05d71877e0c9eddebea36213657b0  lala-dev-meeting-20260908-minutes.md
97eea50f78b84bf96a95b80ca9453bdce6abf8b2ca540ecd977845b9ed0ee321  lala-dev-meeting-20260908-corrected-transcript.md
ba320ebfad07cca7e4d19f99fe8e3be3af3881161894ba5f322cc24e61e3b67c  lala-team-development-readiness-audit-20260909.md
```

원본까지 원격 보관하려면 공개 범위와 별도 비공개 보관 위치를 먼저 정해야 한다. 이 작업에서는 저장소 공개 설정을 바꾸거나 노션·다른 저장 서비스에 업로드하지 않는다.

## 4. 이번 검증의 의미

- Git 비교, 원격 SHA 대조, 원본 해시, 문서 링크·공개 정보·커밋 범위를 확인한다.
- 원본 PDF는 재편집·재렌더하지 않았다. 페이지 수·크기·해시로 원본을 식별한다.
- 보존한 과거 probe나 진행 기록에 적힌 테스트 수치는 과거 주장이다. 이번 검증 결과로 재사용하지 않는다.
- 기능 코드와 런타임 설정을 바꾸지 않으므로 새 기능 성공을 주장하지 않는다. 실제 로그인·지도·음성·DB·배포 검증도 수행하지 않는다.
