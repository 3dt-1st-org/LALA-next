# Devlog - 2026-07-11 배포 자동화 + 보안 정리

수동 배포(git pull + pip install + systemctl restart)를 GitHub Actions 자동 배포로 전환.
과정에서 SSH IP 제한 이슈를 만나 AWS SSM으로 전환. 비밀번호 회전 + public repo 민감값 정리 포함.

런북(`docs/operations/aws-deployment-runbook.md`)과 동일하게 비밀번호/DSN/라이브 자격증명 값은 생략.

## 목표

- main 브랜치 push(또는 PR 머지) 시 EC2 자동 배포 — 수동 SSH 작업 제거
- 배포 전 CI 테스트 통과 보장, health check로 장애 감지
- 비밀번호 평문(public git history 노출) 회전 + 민감값 마스킹

## 작업 기록

### 1. RDS 마스터 비밀번호 회전 (보안 긴급)

**배경**: `aws-deployment-runbook.md`에 RDS 비밀번호 평문(`LalaNext2024!`)이 public repo에 노출. 회전만이 진정한 해결(git history 제거 불가).

**절차**:
1. `aws secretsmanager get-random-password`로 32자 URL-safe 비밀번호 생성 (DB DSN에서 안전하도록 `/@" \?&=%#` 제외)
2. `aws rds modify-db-instance --apply-immediately` — RDS 적용 (10초 내 완료)
3. `aws secretsmanager put-secret-value` — Secrets Manager 갱신
4. EC2 `.env`의 `DB_DSN` 갱신 + FastAPI 재시작
5. `/readyz`로 `db-backed` 유지 확인

### 2. 트러블슈팅: 회전 중 ssh 환경변수 미전달로 일시 장애

**증상**: 회전 후 `/readyz`가 `degraded`로 전락 (db=degraded).

**원인**: `ssh -i key ec2-user@host "sed ... ${NEW_DSN} ..."` 에서 `${NEW_DSN}`을 **로컬 셸 변수**로 넣었으나, ssh는 원격 프로세스에 환경변수를 전달하지 않음 → EC2에서 빈 값으로 확장 → `DB_DSN=postgresql://lalaadmin:@:5432/lalanext` (비밀번호 없음).

**복구**: 파일로 안전 전송 방식 사용 — 로컬에서 `DB_DSN=...` 파일 작성 → `scp` → EC2에서 `sed`로 `.env` 갱신 → 파일 삭제. 30초 내 `db-backed` 복구.

**교훈 (런북 §7 반영)**: ssh 원격 명령에 비밀값을 환경변수로 전달 금지. 파일 전송(scp+sed) 또는 EC2에서 Secrets Manager 직접 조회 사용.

### 3. 배포 자동화 시도 1: GitHub Actions SSH (실패)

**설계**: `.github/workflows/deploy.yml` — CI 통과 시 `appleboy/ssh-action`으로 EC2 SSH 배포.
배포 전용 키(`~/.ssh/lala-next-deploy`) 생성, EC2 authorized_keys 등록, GitHub Secrets(`EC2_SSH_KEY`/`EC2_HOST`/`EC2_USER`) 저장.

**실패**: `dial tcp ***:22: i/o timeout`.

**원인 분석**:
- EC2 보안그룹 SSH(22)가 사용자 IP `121.166.35.242/32` 1개만 허용
- GitHub Actions runner IP 대역: **7,216개** (`https://api.github.com/meta` actions)
- 보안그룹 규칙 60개 제한 → 전부 추가 불가
- 즉 **GitHub Actions → EC2 직접 SSH 방식은 구조적으로 불가**

### 4. 배포 자동화 시도 2: AWS SSM Run Command (전환 중)

**전환 이유**: SSM은 포트 22 없이 IAM 인증으로 명령 실행. GitHub IP 변동 무관, 보안 강력.

**진행**:
1. EC2 IAM 역할(`lala-next-ec2-backup-role`)에 `AmazonSSMManagedInstanceCore` 정책 연결
2. Amazon Linux 2023은 SSM 에이전트 기본 탑재 → 130초 내 `Online` 등록
3. `aws ssm send-command` 동작 확인 (root로 실행)
4. GitHub Actions용 IAM 자격증명 — deploy 전용 사용자(`lala-next-deploy`, ssm:SendCommand 최소 권한) 생성 진행 중
5. `deploy.yml`을 SSM 방식으로 전환 예정

**SSM 설계 이점**:
- 포트 노출 없음 (아웃바운드 443만)
- IAM 인증 (장기 SSH 키 대신)
- 감사 로그 (CloudTrail)
- Private 서브넷도 가능 (VPC 엔드포인트)

### 5. 트러블슈팅: SSM 배포 3연속 실패 → 3개 원인 직렬 해결

OIDC 역할 가정은 1회차부터 성공했지만, SSM 명령 실행 단계에서 연쇄 에러:

1. **`ssm:GetCommandInvocation` AccessDenied** — 인라인 정책의 Resource를 `arn:...:command/*`로 좁혔으나 실제 API는 account-level 리소스 요구 → Resource `*`로 완화 (GetCommandInvocation은 민감 데이터 없는 조회).

2. **`fatal: detected dubious ownership in repository at '/opt/lala-next'`** — SSM AWS-RunShellScript가 기본 **root**로 실행되어, ec2-user 소유의 `/opt/lala-next`에서 git 2.35.2+ 보안 검증(다른 소유자 디렉토리 거부)이 발동.
   - 해결: SSM 파라미터 `runAs=ec2-user` 추가 (root 회피 + 소유자 일치) + `git config --global --add safe.directory` 이중 안전장치.

**교훈**: GitHub Actions OIDC → SSM 파이프라인은 권한(3단계: 역할 가정 / SendCommand / GetCommandInvocation)과 실행 컨텍스트(root vs 소유자)를 각각 검증해야.

## 포트폴리오 관점 (학습/성과)

- **클라우드 네트워크 보안 vs 자동화 충돌**: 보안그룹 IP 제한(모범 사례)이 GitHub Actions 배포를 차단. SSM으로 "포트 없는 자동화" 달성 — 최신 AWS 권장 패턴.
- **비밀 관리 라이프사이클**: 평문 노출 → 회전 → Secrets Manager 중앙화 → 마스킹. public repo에서 민감값을 다루는 실무 경험.
- **점진적 자동화**: 수동 → SSH 자동화 시도(실패) → SSM(성공). 실패 원인을 구조적(GitHub IP 7216개)으로 진단하고 대안 설계.

## 팀원 공통 주의사항

- **런북 민감값**: public repo이므로 계정ID/리소스ID/엔드포인트는 placeholder, 비밀번호는 Secrets Manager 조회만.
- **배포**: main 머지 시 자동 배포(SSM). 배포 로그는 GitHub Actions + `aws ssm get-command-invocation`.
- **RDS 비밀번호 회전**: 런북 §7 절차 준수. ssh 환경변수 전달 금지.
