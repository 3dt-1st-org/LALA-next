# Logto OAuth 배포 실습 가이드 (운영자용)

PR #12 (Logto 기반 Google·Apple·이메일 로그인)를 운영에 배포하기 위한 **운영자 직접 작업 가이드**. 코드 리뷰 완료(merge-after-fixes). 이 가이드는 워크플로 심층 리뷰 결과를 바탕으로 작성됨.

> 🤖 **나에게 요청하면 도와드릴 수 있는 단계**: Phase C(인프라), Phase D(머지/배포), Phase E(검증)의 자동화 부분. **Phase A/B는 외부 콘솔이라 운영자님이 직접** 진행.

---

## 사전 준비

- [ ] AWS CLI 로그인 완료 (`aws sts get-caller-identity` 응답)
- [ ] Logto Cloud 무료 가입 (https://logto.app) — tenant 생성
- [ ] (선택) Google Cloud Console / Apple Developer 계정 접근 권한

---

## Phase A — Logto Cloud 설정 (운영자 콘솔 작업)

### A1. API Resource 생성
1. Logto 콘솔 → **API Resources** → **Create API Resource**
2. Identifier: `https://<tenant>.logto.app/api` (또는 자체 HTTPS)
3. Name: `LALA API`
4. **값 기록** → `LOGTO_API_AUDIENCE`

### A2. Native Application (iOS/Android)
> Logto의 "Flutter" 프리셋이 바로 이 Native App 타입입니다.
1. **Applications** → **Create Application** → **Native App** (또는 "Flutter" 프리셋)
2. Name: `LALA Native`
3. Redirect URI: `cloud.lalanext.lala://callback` (Sign-in + Post sign-out 모두)
4. **App ID 기록** → `LOGTO_NATIVE_APP_ID`

### A3. Single Page App (Flutter Web)
> 💡 Logto 콘솔에 "Flutter" 프리셋은 Native App 전용입니다. **Flutter Web은 브라우저 SPA이므로 "Single Page App" 타입**으로 생성하세요.
1. **Create Application** → **Single Page App** (또는 SPA)
2. Name: `LALA Web`
3. Redirect URI: `https://lala-next.cloud/auth-callback.html`
4. Post sign-out URI: `https://lala-next.cloud/`
5. **App ID 기록** → `LOGTO_WEB_APP_ID`

### A4. M2M Application (Management API)
1. **Create Application** → **Machine-to-Machine`
2. Name: `LALA Backend`
3. **API Resources** → Logto Management API 접근 권한 부여
4. **App ID + App Secret 기록** → `LOGTO_MANAGEMENT_CLIENT_ID` / `LOGTO_MANAGEMENT_CLIENT_SECRET`
   > 🔒 Secret은 즉시 AWS Secrets Manager로 (A5) — 화면/채팅에 복사 금지

### A5. M2M Secret → AWS Secrets Manager
```bash
aws secretsmanager create-secret --name lala-next/logto-management-client-id \
  --secret-string "<M2M_APP_ID>" --region us-east-1
aws secretsmanager create-secret --name lala-next/logto-management-client-secret \
  --secret-string "<M2M_APP_SECRET>" --region us-east-1
```

### A6. Connectors
1. **Connectors** → **Google**: 안내하는 redirect URI를 **Google Cloud OAuth client**에 등록 (Phase B)
2. **Connectors** → **Apple**: 안내하는 Return URL을 **Apple Developer**에 등록 (Phase B)
3. **Connectors** → **Email**: built-in email service 또는 SMTP

### A7. Sign-in & Account 설정
1. **Sign-in & Account** → **Sign-up and sign-in**
2. **Social sign-in**: Google, Apple 추가
3. **Identifier**: Email address 추가, 방식 = **Email verification code only** (Password 끔, Magic Link 미구현)

### A8. Live Preview 사전 검증
1. **Logto Live** (또는 Preview)에서 Google / Apple / 이메일 각각 1회 로그인 테스트

### A9. Endpoint 기록
- 콘솔 상단의 endpoint: `https://<tenant-id>.logto.app`
- ⚠️ **반드시 소문자**로 기록 → `LOGTO_ENDPOINT` (hostname 대소문자 정규화 미구현, 혼용 시 401)

---

## Phase B — Google/Apple OAuth 클라이언트 (팀원과 협업 또는 운영자)

> 💡 이 부분은 PR #12를 작성한 팀원(RudinP)이 필요 redirect URI/스코프를 가장 잘 알고 있음 — 팀원에게 위임 권장.

### B1. Google Cloud OAuth Client
1. https://console.cloud.google.com → APIs & Services → Credentials
2. OAuth client ID (Web) 생성
3. Authorized redirect URI: Logto Google connector가 안내한 URI (A6)
4. Client ID / Client Secret → Logto Google connector에 입력

### B2. Apple Developer (Sign in with Apple)
1. https://developer.apple.com → Certificates, Identifiers
2. Service ID 생성, Return URL = Logto Apple connector 안내 URI
3. Team ID, Key ID, Sign-in key 발급 → Logto Apple connector에 입력

---

## Phase C — AWS 인프라 적용 (나에게 요청하면 자동 진행 가능)

### C1. RDS 수동 스냅샷 (백업)
```bash
aws rds create-db-snapshot --db-instance-identifier lala-next-db \
  --db-snapshot-identifier lala-pre-logto-$(date +%Y%m%d) --region us-east-1
# Available 상태 대기
aws rds wait db-snapshot-available --db-snapshot-identifier lala-pre-logto-$(date +%Y%m%d)
```

### C2. RDS 스키마 마이그레이션 (005)
> ⚠️ **머지(자동배포)보다 반드시 선행**. deploy.yml은 스키마를 안 건드림.
```bash
# EC2에서 (또는 나에게 요청)
cd /opt/lala-next
# 먼저 main pull (005 파일이 main에 있어야)
RDS_PW=$(aws secretsmanager get-secret-value --secret-id lala-next/rds-master-password \
  --query SecretString --output text | python3 -c "import sys,json;print(json.loads(sys.stdin.read())['password'])")
for f in sql/canonical/000_extensions_and_schemas.sql sql/canonical/005_identity_users.sql; do
  PGPASSWORD="$RDS_PW" psql -h <RDS_ENDPOINT> -U lalaadmin -d lalanext -f "$f" -v ON_ERROR_STOP=1
done
unset RDS_PW
# 검증
.venv/bin/python -m apps.api.app.tools.verify_db_schema --json   # ok=true 확인
```

### C3. EC2 .env 설정 (LOGTO_*)
> 🔒 값은 화면 출력 금지. 파일로 안전 전송(scp+sed) 또는 나에게 요청.
```bash
# /opt/lala-next/.env (0600)에 추가
LOGTO_ENDPOINT=<A9, 소문자>
LOGTO_API_AUDIENCE=<A1>
LOGTO_NATIVE_APP_ID=<A2>
LOGTO_WEB_APP_ID=<A3>
LOGTO_REDIRECT_URI=https://lala-next.cloud/auth-callback.html
LOGTO_POST_LOGOUT_REDIRECT_URI=https://lala-next.cloud/
LOGTO_MANAGEMENT_ENDPOINT=<A9와 동일>
# M2M은 Secrets Manager에서 읽도록 (또는 직접)
LOGTO_MANAGEMENT_CLIENT_ID=<A4>
LOGTO_MANAGEMENT_CLIENT_SECRET=<A4>
LALA_GUEST_ACCESS=true
LALA_PUBLIC_CONTEST_ACCESS=false   # GUEST_ACCESS=true 후 false로 전환
```

---

## Phase D — 머지 + 자동 배포

### D1. 문서 충돌 해소 (팀원 PR rebase)
- 팀원이 `feat(auth)/logto-social-auth` 브랜치를 origin/main에 rebase
- 충돌 2개 문서만 수동 해소 (가이드: 워크플로 리뷰 결과의 conflict_resolution 참조)
  - `aws-deployment-runbook.md`: main 기준 + auth 노트 이식
  - `vercel-deployment.md`: PR 기준 + Cloudflare DNS 표 보존

### D2. PR #12 머지
```bash
gh pr merge 12 --squash   # 팀원이 draft 해제 후
```
→ **자동 배포 트리거** (CI 통과 → deploy.yml → SSM)

### D3. 배포 확인
```bash
gh run list --workflow=deploy.yml --limit 1   # success 확인
curl -s https://api.lala-next.cloud/readyz | python3 -m json.tool
```
**기대 결과**:
- `overall: operational` (또는 db-backed)
- `identity_schema: configured` ✅ (새 체크)
- `jwt_validation: configured` ✅
- `logto_management: configured` ✅
- `guest_access: enabled` ✅

> ❗ `/readyz`가 `identity_schema: degraded`면 Phase C2/C3 누락. deploy.yml은 이를 자동 해소 안 함.

### D4. API 동작 검증
```bash
curl -s https://api.lala-next.cloud/healthz                    # 200
curl -s https://api.lala-next.cloud/readyz                     # 200, 위 기대 결과
curl -s -H "Authorization: Bearer invalid" https://api.lala-next.cloud/api/v1/me   # 401 (정상)
```

---

## Phase E — Flutter Web 배포

```bash
flutter build web --release \
  --dart-define LALA_API_BASE_URL=https://api.lala-next.cloud \
  --dart-define LOGTO_ENDPOINT=<A9> \
  --dart-define LOGTO_API_AUDIENCE=<A1> \
  --dart-define LOGTO_NATIVE_APP_ID=<A2> \
  --dart-define LOGTO_WEB_APP_ID=<A3> \
  --dart-define KAKAO_JAVASCRIPT_KEY=<kakao_js_key>
# Vercel prod 배포
vercel deploy --prod
```
- `https://lala-next.cloud/auth-callback.html` → 200 확인
- 실동작: 로그아웃 상태에서 장소/날씨 오픈 → Google/Apple/이메일 각각 로그인 → `/api/v1/me` 200 → 로그아웃

---

## 롤백

```bash
# API 오류 시 이전 커밋으로 (PREVIOUS_API_SHA 보관 필수)
ssh-like: aws ssm send-command ... "cd /opt/lala-next && git reset --hard <PREVIOUS_SHA> && systemctl restart lala-next"
# 또는 RDS 스냅샷 복원 (Phase C1 스냅샷)
```

---

## 체크리스트 (진행 상태 추적)

- [ ] Phase A1-A9: Logto Cloud 설정 + 값 기록
- [ ] Phase B1-B2: Google/Apple OAuth (팀원 또는 운영자)
- [ ] Phase C1: RDS 스냅샷 백업
- [ ] Phase C2: RDS 005 마이그레이션 + verify_db_schema ok=true
- [ ] Phase C3: EC2 .env (LOGTO_*) 설정
- [ ] Phase D1: 문서 충돌 해소 (팀원 rebase)
- [ ] Phase D2: PR #12 머지 → 자동 배포
- [ ] Phase D3: /readyz identity_schema=configured
- [ ] Phase D4: API 동작 검증
- [ ] Phase E: Flutter Web 배포 + 실동작 확인

---

**관련**: [PR #12 워크플로 리뷰 결과](../devlogs/2026-07-11-deploy-automation.md) · [AWS 런북](aws-deployment-runbook.md) · [팀원 접속 가이드](team-ec2-access.md)
