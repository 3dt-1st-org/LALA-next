# 팀원 EC2 접속 가이드 (AWS SSM Session Manager)

EC2에 SSH(포트 22)가 **폐쇄**되어 있습니다. 대신 **AWS SSM Session Manager**로 접속합니다 (IAM 인증, 포트 노출 없음, 별도 AWS 계정 불필요).

## 1. AWS 콘솔 로그인

1. **콘솔 URL**: `https://292216133883.signin.aws.amazon.com/console`
2. 계정: `292216133883` (URL에 포함됨)
3. 사용자명 + 임시 비밀번호 입력 (초대받은 값)
4. 첫 로그인 시 **비밀번호 변경** (강제)

> 🔒 임시 비밀번호는 초대 메시지로 전달됩니다. 본인 AWS 계정이 아닌 **팀 공용 계정(292216133883)** 의 IAM 사용자입니다. 무료 크레딧은 본인이 소비하지 않습니다.

## 2. 브라우저로 EC2 셸 접속 (가장 간단, 설치 불필요)

1. 콘솔에서 **EC2** 서비스 → **인스턴스**
2. `i-0a15ffbfa381a5843` 선택 (LALA-next 운영 서버)
3. 상단 **Connect** 버튼 → **Session Manager** 탭 → **Connect**
4. 브라우저에 터미널이 열립니다 (ec2-user 권한)

## 3. CLI로 접속 (선호 시)

### 3-1. 사전 준비 (최초 1회)
```bash
# AWS CLI + Session Manager 플러그인 설치
brew install --cask session-manager-plugin   # macOS
# AWS 자격증명 설정 (콘솔에서 본인 IAM 사용자의 Access Key 발급 후)
aws configure
```

> 💡 브라우저 접속만 쓴다면 이 단계는 건너뛰어도 됩니다.

### 3-2. 접속
```bash
aws ssm start-session --target i-0a15ffbfa381a5843 --region us-east-1
```

## 4. 권한 범위 (최소 권한)

본인 IAM 사용자는 `lala-next-team` 그룹에 속하며, **아래만 가능**합니다:
- `ssm:StartSession` — 위 인스턴스 1대에만 셸 접속
- `ssm:Describe*` / `ec2:DescribeInstances` — 인스턴스 정보 조회
- `ssm:TerminateSession` — 본인 세션 종료

**불가능**: 다른 EC2/RDS/S3 변경, IAM 변경, 과금 리소스 생성, 다른 AWS 서비스. 안전하게 설계됨.

## 5. 자주 쓰는 명령 (EC2 내부)

```bash
cd /opt/lala-next                          # 앱 디렉토리
git log --oneline -5                        # 배포된 커밋 확인
sudo systemctl status lala-next             # FastAPI 상태
sudo journalctl -u lala-next -n 50          # 최근 로그
curl -s http://localhost:8000/readyz | python3 -m json.tool   # 헬스체크
```

> ⚠️ **배포는 자동**: main 브랜치에 PR 머지 시 GitHub Actions가 자동 배포합니다. EC2에서 수동 `git pull`/`restart`는 디버깅 외에 금지.

## 6. 문제 해결

| 증상 | 조치 |
|------|------|
| 콘솔 로그인 안 됨 | 비밀번호 재설정 요청 (운영자에게) |
| Connect 버튼 비활성 / Session Manager 탭 없음 | 인스턴스 SSM 에이전트 미Online — 운영자에게 문의 |
| CLI `StartSession` 권한 에러 | 본인 IAM 그룹 확인 요청 |

## 7. 비상 (SSM이 안 될 때)

SSM 경로가 모두 막힌 경우에만, 운영자가 SSH를 일시 재개방할 수 있습니다. 팀원은 직접 할 수 없으니 운영자에게 연락.

---

## 8. 운영자: 팀원 IAM 생성 체크리스트 (재발 방지)

> **교훈**: 2026-07-11 팀원이 첫 로그인 비밀번호 변경 시 "권한 없음" 에러로 접근 차단. `create-login-profile --password-reset-required`로 변경을 요구해놓고 **변경 권한을 안 준 기초적 누락**. 아래 3가지를 **반드시 동시에** 부여할 것.

팀원 IAM 사용자 생성 시 누락 없이 적용:
```bash
USER=<username>
# 1) 그룹에 3가지 권한 (최초 1회 세팅, 이후 사용자는 그룹 추가만)
aws iam attach-group-policy --group-name lala-next-team \
  --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword        # 본인 비밀번호 변경 (필수)
# inline 정책 2종: ssm-session-access, self-account-manage (본인 MFA/액세스키)

# 2) 사용자 생성 + 그룹 추가 + 콘솔 비밀번호
aws iam create-user --user-name "$USER" --tags "Key=email,Value=<email>"
aws iam add-user-to-group --user-name "$USER" --group-name lala-next-team
aws iam create-login-profile --user-name "$USER" --password "<temp>" --password-reset-required
```

**체크리스트** (생성 후 반드시 확인):
- [ ] `aws iam list-attached-group-policies --group-name lala-next-team` → `IAMUserChangePassword` 있음
- [ ] `aws iam list-group-policies --group-name lala-next-team` → `ssm-session-access`, `self-account-manage` 있음
- [ ] 사용자가 그룹에 속함 (`aws iam get-group --group-name lala-next-team`)
- [ ] 팀원이 본인 비밀번호 변경 + MFA 설정 가능 (권한 에러 없음)

⚠️ 비밀번호 변경을 요구(`--password-reset-required`)하려면 **반드시 변경 권한도 함께** 줄 것. 그렇지 않으면 팀원이 첫 로그인에서 차단됨.

---

**관련 문서**: [AWS 배포 런북](aws-deployment-runbook.md) · [배포 자동화 devlog](../devlogs/2026-07-11-deploy-automation.md)
