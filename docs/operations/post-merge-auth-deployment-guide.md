# 로그인 기능 운영 배포 및 실동작 확인

이 문서는 로그인 PR을 `main`에 병합한 뒤 처음 배포하는 운영자를 위한 순서표다.
현재 지원 범위는 Google, Apple, 이메일 인증코드 로그인이다. 이메일 링크를
클릭해 로그인하는 Magic Link는 구현하지 않았다.

명령에 나오는 `<...>` 값은 AWS, Vercel, Cloudflare, Logto 콘솔에서 확인한다.
비밀번호, 토큰, DSN, Apple signing key를 Git이나 터미널 기록에 남기지 않는다.

## 1. 배포에 필요한 접근 권한을 준비한다

다음 항목에 접근할 수 있어야 한다.

- GitHub 저장소의 `main` 브랜치
- AWS EC2 SSH key, RDS 정보, Secrets Manager 읽기 권한
- Logto Console
- Google Cloud Console과 Apple Developer
- Vercel의 LALA Flutter 프로젝트
- Cloudflare DNS는 이번 배포에서 변경하지 않는다

EC2, RDS, Vercel 프로젝트를 찾지 못하면 배포를 시작하지 않는다. 저장소에
운영 리소스 ID를 새로 기록하지 않는다.

## 2. 현재 운영 버전을 기록하고 RDS를 백업한다

EC2에 접속해 현재 API commit을 기록한다.

```bash
ssh -i "<EC2_SSH_KEY>" "<EC2_USER>@<EC2_HOST>"
cd /opt/lala-next
git rev-parse HEAD
sudo systemctl status lala-next --no-pager
```

출력된 commit SHA를 배포 기록에 `PREVIOUS_API_SHA`로 보관한다. Vercel
Dashboard에서도 현재 Production deployment를 기록한다. AWS Console에서 RDS
수동 snapshot을 만든 뒤 상태가 `Available`인지 확인한다.

## 3. Logto 애플리케이션을 설정한다

Logto Console에서 다음 순서로 만든다.

1. API Resource를 만들고 HTTPS identifier를 `LOGTO_API_AUDIENCE`로 기록한다.
2. Native Application을 만들고 public App ID를 `LOGTO_NATIVE_APP_ID`로 기록한다.
3. Native redirect와 post sign-out URI에
   `cloud.lalanext.lala://callback`을 등록한다.
4. Web Application을 만들고 public App ID를 `LOGTO_WEB_APP_ID`로 기록한다.
5. Web redirect에 `https://lala-next.cloud/auth-callback.html`을 등록한다.
6. Web post sign-out URI에 `https://lala-next.cloud/`을 등록한다.
7. M2M Application을 만들고 `Logto Management API access` 역할을 부여한다.
8. M2M ID와 secret은 AWS Secrets Manager에 저장한다.

Flutter에는 Web/Native public App ID만 전달한다. M2M secret은 EC2에서만
사용한다.

## 4. Google, Apple, 이메일 인증코드를 켠다

Logto Console의 `Connectors`에서 각 connector를 만든다.

1. Google connector가 안내하는 redirect URI를 Google Cloud OAuth client에
   그대로 등록한다.
2. Apple connector가 안내하는 Return URL을 Apple Developer 설정에 등록하고
   Service ID, Team ID, Key ID, signing key를 Logto에 설정한다.
3. Email connector는 첫 검증에서 Logto built-in email service를 사용할 수
   있다. 운영 발신 정책이 있으면 승인된 SMTP 또는 email provider connector를
   사용한다.
4. `Sign-in & account > Sign-up and sign-in`에서 Google과 Apple을 Social
   sign-in에 추가한다.
5. Email address를 identifier로 추가하고 sign-in 방식은
   `Email verification code`만 선택한다. Password는 켜지 않는다.
6. Logto Live preview에서 Google, Apple, 이메일 발송을 각각 한 번 확인한다.

이 단계의 이메일 방식은 받은 숫자 코드를 입력하는 로그인이다. Magic Link용
one-time token API와 landing page는 이 PR에 없다.

## 5. RDS에 identity schema를 적용한다

EC2의 `/opt/lala-next`에서 `main`을 최신 상태로 만든다.

```bash
cd /opt/lala-next
git fetch --prune origin
git switch main
git pull --ff-only origin main
```

Secrets Manager에서 RDS 비밀번호를 읽고 `000`과 `005`를 순서대로 적용한다.
`set +x` 상태에서 실행하고 완료 후 변수를 지운다.

```bash
set +x
SECRET_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "<RDS_SECRET_ID>" \
  --query SecretString \
  --output text)"
export PGPASSWORD="$(printf '%s' "$SECRET_JSON" | python3 -c \
  "import json,sys; print(json.load(sys.stdin)['password'])")"

for file in \
  sql/canonical/000_extensions_and_schemas.sql \
  sql/canonical/005_identity_users.sql
do
  psql \
    --host "<RDS_HOST>" \
    --port "<RDS_PORT>" \
    --username "<RDS_USER>" \
    --dbname "<RDS_DATABASE>" \
    --set ON_ERROR_STOP=1 \
    --file "$file"
done

unset PGPASSWORD SECRET_JSON
```

API가 사용하는 `DB_DSN`을 환경 파일에서 읽을 수 있는 상태로 schema verifier를
실행한다.

```bash
.venv/bin/python -m apps.api.app.tools.verify_db_schema --json
```

`ok=true`가 아니면 다음 단계로 가지 않는다.

## 6. EC2 환경변수를 설정하고 API를 배포한다

`/opt/lala-next/.env` 또는 현재 systemd가 읽는 환경 파일을 `0600` 권한으로
관리한다. 다음 이름을 설정하되 값을 화면에 출력하지 않는다.

```text
LALA_GUEST_ACCESS=true
LALA_PUBLIC_CONTEST_ACCESS=false
LALA_STATIC_SNAPSHOT_FALLBACK=false
LOGTO_ENDPOINT=<LOGTO_CLOUD_ENDPOINT>
LOGTO_API_AUDIENCE=<LALA_API_RESOURCE_IDENTIFIER>
LOGTO_MANAGEMENT_ENDPOINT=<LOGTO_CLOUD_ENDPOINT>
LOGTO_MANAGEMENT_CLIENT_ID=<M2M_APP_ID>
LOGTO_MANAGEMENT_CLIENT_SECRET=<M2M_APP_SECRET>
DB_DSN=<RDS_DSN>
CORS_ALLOW_ORIGINS=https://lala-next.cloud,https://www.lala-next.cloud
```

의존성을 설치하고 서비스를 재시작한다.

```bash
cd /opt/lala-next
.venv/bin/python -m pip install -e .
sudo systemctl daemon-reload
sudo systemctl restart lala-next
sudo systemctl status lala-next --no-pager
sudo nginx -t
sudo systemctl reload nginx
```

## 7. API 배포를 먼저 확인한다

```bash
curl -fsS https://api.lala-next.cloud/healthz
curl -fsS https://api.lala-next.cloud/readyz

curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Authorization: Bearer invalid-deploy-smoke' \
  'https://api.lala-next.cloud/api/v1/places?lat=37.5665&lng=126.9780&limit=1'
```

확인할 값은 다음과 같다.

- `/healthz`와 `/readyz`가 `200`
- `guest_access=enabled`
- `jwt_validation=configured`
- `logto_management=configured`
- `identity_schema=configured`
- 잘못된 Bearer 요청이 `401`

하나라도 다르면 Flutter를 배포하지 않고 10단계로 이동한다.

## 8. Flutter Web을 Vercel에 배포한다

개발 PC에서 최신 `main`을 checkout하고 public 값만 dart-define으로 전달한다.

```bash
export LOGTO_ENDPOINT="<LOGTO_CLOUD_ENDPOINT>"
export LOGTO_API_AUDIENCE="<LALA_API_RESOURCE_IDENTIFIER>"
export LOGTO_NATIVE_APP_ID="<NATIVE_APP_ID>"
export LOGTO_WEB_APP_ID="<WEB_APP_ID>"
export KAKAO_JAVASCRIPT_KEY="<KAKAO_JAVASCRIPT_KEY>"

flutter build web --release \
  --pwa-strategy=none \
  --dart-define=LALA_API_BASE_URL=https://api.lala-next.cloud \
  --dart-define=LALA_BUILD_SHA="$(git rev-parse HEAD)" \
  --dart-define=LOGTO_ENDPOINT="$LOGTO_ENDPOINT" \
  --dart-define=LOGTO_API_AUDIENCE="$LOGTO_API_AUDIENCE" \
  --dart-define=LOGTO_NATIVE_APP_ID="$LOGTO_NATIVE_APP_ID" \
  --dart-define=LOGTO_WEB_APP_ID="$LOGTO_WEB_APP_ID" \
  --dart-define=LOGTO_REDIRECT_URI=https://lala-next.cloud/auth-callback.html \
  --dart-define=LOGTO_POST_LOGOUT_REDIRECT_URI=https://lala-next.cloud/ \
  --dart-define=KAKAO_JAVASCRIPT_KEY="$KAKAO_JAVASCRIPT_KEY"
```

Vercel 프로젝트 binding을 환경에서 제공하고 production에 배포한다.

```bash
export VERCEL_ORG_ID="<VERCEL_ORG_ID>"
export VERCEL_PROJECT_ID="<VERCEL_PROJECT_ID>"

python3 scripts/prepare_flutter_vercel_static_output.py
python3 scripts/prepare_flutter_vercel_static_output.py --verify-project-binding
vercel deploy static-output --prod
```

배포 후 `https://lala-next.cloud/auth-callback.html`이 `200`인지 확인한다.

## 9. 세 가지 로그인 방식을 실동작 확인한다

실제 사용자 계정 대신 배포 테스트 계정을 사용한다.

1. 로그아웃 상태에서 장소와 날씨가 열리는지 확인한다.
2. 설정의 로그인 버튼을 눌러 Logto hosted 화면이 열리는지 확인한다.
3. Google로 로그인하고 앱 복귀, `/api/v1/me` 성공, 새로고침 후 세션 복구,
   로그아웃을 확인한다.
4. Apple로 같은 순서를 확인한다. iOS release 후보도
   `cloud.lalanext.lala://callback`으로 앱에 복귀해야 한다.
5. 이메일 주소를 입력하고 받은 인증코드로 로그인한 뒤 같은 순서를 확인한다.
6. 잘못된 코드, 취소, 만료된 세션이 안전한 오류 문구를 표시하는지 확인한다.
7. 전용 삭제 테스트 계정으로 앱 내 계정 삭제가 `204`를 반환하고 Logto 사용자와
   세션을 제거하는지 확인한다.
8. Apple 테스트 계정 삭제 후 Apple authorization이 철회됐다는 증거를 Logto와
   Apple의 지원되는 화면 또는 로그에서 확인한다.

iOS와 Android도 원격 운영 API를 바라보는 실제 기기에서 한 번씩 확인한다.

```bash
flutter devices

flutter run --release -d "<DEVICE_ID>" \
  --dart-define=LALA_API_BASE_URL=https://api.lala-next.cloud \
  --dart-define=LOGTO_ENDPOINT="$LOGTO_ENDPOINT" \
  --dart-define=LOGTO_API_AUDIENCE="$LOGTO_API_AUDIENCE" \
  --dart-define=LOGTO_NATIVE_APP_ID="$LOGTO_NATIVE_APP_ID"
```

같은 명령을 iOS와 Android 기기 각각에 실행한다. iOS는 Apple 로그인을 포함하고,
Android는 callback 후 앱 복귀와 세션 복구를 확인한다.

Apple authorization 철회를 확인하지 못하면 출시하지 않는다. 운영 사용자의 계정
삭제는 테스트하지 않는다.

Apple upstream authorization revocation is a release gate. Verify it with a
dedicated test account in the live connector integration. The Logto Management
API does not expose a usable provider refresh token to this server, so server
fallback is not supported. If supported Logto or Apple evidence cannot confirm
the revocation, block launch and handle the connector design in a separately
reviewed change.

## 10. 오류가 나면 이전 버전으로 돌린다

API 오류라면 EC2에서 2단계의 commit으로 복원한다.

```bash
cd /opt/lala-next
git switch --detach "<PREVIOUS_API_SHA>"
.venv/bin/python -m pip install -e .
sudo systemctl restart lala-next
```

환경 설정 문제라면 Secrets Manager의 이전 version과 이전 환경 파일을 복원한 뒤
API를 재시작한다. Flutter 오류라면 Vercel Dashboard에서 2단계에 기록한 이전
deployment를 다시 Production으로 승격한다.

`identity.users`와 `identity.deleted_users`는 이전 API가 사용하지 않는 additive
table이므로 일반 롤백에서 삭제하지 않는다. RDS snapshot 복원은 데이터가 손상된
경우에만 수행한다. 테스트 중 삭제한 Logto·Apple 계정은 롤백으로 복구되지 않는다.

## 관련 공식 문서

- [Logto Flutter quick start](https://docs.logto.io/quick-starts/flutter)
- [Logto social connectors](https://docs.logto.io/connectors/social-connectors)
- [Logto email connectors](https://docs.logto.io/connectors/email-connectors)
- [Logto Management API](https://docs.logto.io/integrate-logto/interact-with-management-api)
