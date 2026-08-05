# AWS-First Build Secret Resolution

**최종 업데이트**: 2026-08-06
**상태**: 코드 경로 구현 완료, 원격 매핑 미확인

---

## 개요

LALA-next Flutter 빌드 시크릿 해결은 **AWS Systems Manager Parameter Store 우선, AWS Secrets Manager 폴백, 로컬 dotenv 최종** 순서를 따릅니다. 코드 경로는 SSM-first 해결을 구현하지만, 정확한 승인된 파라미터 매핑/권한은 외부 구성 단계로 남아 있습니다.

---

## 소스 우선순위

### KAKAO_JAVASCRIPT_KEY 해결 순서

1. **AWS Systems Manager Parameter Store** (우선)
   - 논리 이름: `kakao-javascript-key`
   - 전체 경로: `/lala-next/kakao-javascript-key` (접두사 `LALA_AWS_SSM_PREFIX`로 구성 가능)
   - 또는 `LALA_AWS_SSM_PARAMETER_NAME` 환경변수로 명시적 파라미터 이름 지정 가능
   - 리전: `AWS_REGION` 또는 `AWS_DEFAULT_REGION` (기본값: `us-east-1`)
   - IAM 권한: `ssm:GetParameter`
   - **매핑 상태**: 원격 파라미터 매핑 미확인

2. **AWS Secrets Manager** (폴백)
   - 논리 이름: `kakao-javascript-key`
   - 전체 경로: `lala-next/kakao-javascript-key` (접두사 `LALA_AWS_SM_PREFIX`로 구성 가능)
   - 리전: `AWS_REGION` 또는 `AWS_DEFAULT_REGION` (기본값: `us-east-1`)
   - IAM 권한: `secretsmanager:GetSecretValue`
   - **매핑 상태**: 원격 시크릿 매핑 미확인

3. **프로세스 환경 변수** (폴백)
   - 이미 내보낸(exported) 프로세스 환경 변수는 AWS 원본 소스를 사용할 수 없을 때만 폴백으로 사용됨
   - AWS SSM/SM이 사용 가능한 경우, 프로세스 환경 변수가 우선순위에서 패배함
   - 이는 로컬 개발 환경에서 원격 소스를 일시적으로 우회하는 데 사용할 수 있음

4. **로컬 dotenv 파일** (최종)
   - `.env.local` (우선)
   - `.env` (차선)

5. **Fail-closed**

4. **Fail-closed**
   - 모든 소스에서 값이 없으면 빌드 실패
   - 보안을 위해 기본값/데모 값 제공하지 않음

---

## 구현

### 빌드 스크립트 변경 사항

1. **`scripts/unix/_common.sh`**
   - `aws_ssm_secret_get()` 함수: AWS SSM Parameter Store 조회
   - `aws_sm_secret_get()` 함수: AWS Secrets Manager 조회
   - `load_flutter_build_secrets()` 함수: SSM-first 해결 로직

2. **Flutter 빌드 스크립트**
   - `scripts/unix/verify_flutter_app.sh`
   - `scripts/unix/deploy_flutter_web_vercel.sh`
   - `scripts/unix/smoke_flutter_web.sh`
   - 모두 `load_flutter_build_secrets "KAKAO_JAVASCRIPT_KEY" "kakao-javascript-key"` 호출

### 허용되는 Dart Defines

다음 변수만 Flutter 빌드에 전달됩니다:

- `LALA_API_BASE_URL` - API 엔드포인트 (비밀 아님)
- `KAKAO_JAVASCRIPT_KEY` - 카카오 지도 JavaScript 키 (공개 브라우저 자격증명)
- `LALA_BUILD_SHA` - 빌드 SHA (비밀 아님)

**중요**: DB_DSN, 베어러 토큰, OpenAI API 키, Logto 비밀, 제공자 비밀, 음성 비밀은 Dart에 전달되지 않습니다.

---

## 로컬 개발

### 개발 환경 설정

로컬 개발의 경우 `.env.local` 또는 `.env` 파일에 값을 넣으세요:

```bash
# .env.local 또는 .env
KAKAO_JAVASCRIPT_KEY=your-local-development-key
```

### 프로세스 환경 변수 동작

이미 내보낸(exported) 프로세스 환경 변수는 **폴백**으로 처리되며 **오버라이드**가 아닙니다:

- **AWS SSM/SM 사용 가능**: 원격 값이 프로세스 환경 변수보다 우선함
- **AWS SSM/SM 사용 불가능**: 프로세스 환경 변수가 dotenv 파일보다 우선함

```bash
# 예제: 프로세스 환경 변수 설정
export KAKAO_JAVASCRIPT_KEY="pre-existing-value"

# SSM이 사용 가능한 경우:
# load_flutter_build_secrets는 SSM 값을 사용함 (pre-existing-value 무시)

# SSM이 사용 불가능한 경우:
# load_flutter_build_secrets는 pre-existing-value를 유지함
```

이는 CI/CD 환경에서 일시적으로 원격 소스를 우회하거나, 로컬 개발에서 테스트를 위해 유용합니다.

### AWS 자격증명 없이 로컬 빌드

AWS CLI가 설치되지 않았거나 자격증명이 없으면 자동으로 dotenv로 폴백합니다:

```bash
# AWS 자격증명 없이도 작동
flutter build web --release --dart-define="KAKAO_JAVASCRIPT_KEY=$KAKAO_JAVASCRIPT_KEY"
```

---

## 배포

### AWS Systems Manager Parameter Store 설정

프로덕션 환경에서는 팀의 승인된 시크릿 관리 워크플로우를 통해 AWS SSM Parameter Store에 SecureString 파라미터를 프로비저닝하세요:

- 파라미터 이름: `/lala-next/kakao-javascript-key` (또는 `LALA_AWS_SSM_PARAMETER_NAME` 환경변수로 지정)
- 유형: SecureString
- 권한 요구사항: `ssm:GetParameter`

**중요**: 시크릿 값을 셸 기록이나 프로세스 인자에 노출하지 마세요. `--value` 또는 `--secret-string` 인자에 직접 값을 붙여넣지 마세요.

### AWS Secrets Manager 설정 (선택적 폴백)

SSM 사용을 선호하지 않는 경우 Secrets Manager를 사용할 수 있습니다:

- 시크릿 이름: `lala-next/kakao-javascript-key` (또는 `LALA_AWS_SM_PREFIX` 환경변수로 지정)
- 권한 요구사항: `secretsmanager:GetSecretValue`

**중요**: 승인된 시크릿 관리 프로세스를 통해 프로비저닝하세요. CLI 인자에 직접 값을 붙여넣지 마세요.

### 배포 스크립트 사용

```bash
# 프로덕션 빌드 및 배포
scripts/unix/deploy_flutter_web_vercel.sh
```

스크립트가 자동으로:
1. AWS SSM Parameter Store에서 시크릿 조회 시도
2. 실패하면 AWS Secrets Manager 폴백
3. 실패하면 `.env.local`/`.env` 폴백
4. 값이 없으면 빌드 실패 (fail-closed)

---

## 보안 정책

### 시크릿 값 절대 노출 금지

- 로그에 시크릿 값 출력 금지
- 커밋 메시지에 시크릿 포함 금지
- 테스트 출력에서 시크릿 마스킹

### 소스 범주 보고

보고서는 다음만 언급할 수 있습니다:
- 소스 범주 (aws-ssm / aws-sm / local-dotenv / missing)
- 존재/부존재 상태
- 성공/실패 상태

실제 시크릿 값이나 AWS 리소스 ID, 계정 번호는 문서화하지 않습니다.

---

## 테스트

### 오프라인 테스트

AWS에 연결하지 않고 테스트:

```bash
scripts/unix/test_aws_first_build_secrets.sh
```

테스트 항목:
- 함수 존재 확인 (aws_ssm_secret_get, aws_sm_secret_get, load_flutter_build_secrets)
- 기존 값 덮어쓰기 방지
- AWS 없을 때 dotenv 폴백
- 값 없을 때 fail-closed
- `.env.local` 우선순위
- AWS SSM 우선순위 (로컬 .env 보다 우선)
- AWS SM 폴백 (SSM 실패 시)
- AWS 전체 실패 시 dotenv 최종 폴백
- stdout/stderr 누출 방지 테스트

---

## 문제 해결

### 빌드 실패: "KAKAO_JAVASCRIPT_KEY is required"

**원인**: 모든 소스에서 값을 찾을 수 없음

**해결**:
1. 프로덕션: AWS SSM Parameter Store 또는 Secrets Manager에 시크릿 생성
2. 로컬 개발: `.env.local` 또는 `.env`에 값 추가

### AWS 권한 거부

**원인**: IAM 권한 부족 또는 자격증명 없음

**해결**:
1. IAM 정책에 `ssm:GetParameter` 및 `secretsmanager:GetSecretValue` 권한 확인
2. AWS CLI 자격증명 확인 (없으면 dotenv로 자동 폴백)
3. 또는 dotenv 파일 사용 (자동 폴백)

### 값이 로드되지 않음

**원인**: 환경 변수 이미 설정되어 있음

**해결**: 이미 설정된 변수는 덮어쓰지 않습니다. unset 후 다시 시도:
```bash
unset KAKAO_JAVASCRIPT_KEY
scripts/unix/deploy_flutter_web_vercel.sh
```

---

## 참고

### IAM 권한 요구사항

SSM-first 해결을 위해 필요한 IAM 권한:

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:GetParameter",
    "secretsmanager:GetSecretValue"
  ],
  "Resource": [
    "arn:aws:ssm:*:*:parameter/lala-next/*",
    "arn:aws:secretsmanager:*:*:secret:lala-next/*"
  ]
}
```

**중요**: 기존 Parameter Store 또는 Secrets Manager 매핑이 존재하지 않으면 경로를 추측하지 마세요.

### 관련 문서

- [AWS 배포 런북](aws-deployment-runbook.md)
- [Key Vault 재사용 계획](key-vault-reuse.md)
- [Vercel 배포](vercel-deployment.md)