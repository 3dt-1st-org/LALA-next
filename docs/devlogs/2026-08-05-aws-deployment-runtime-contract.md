# 2026-08-05 AWS 배포 런타임 계약 수정

## 결함 발견

### 배포 워크플로우의 리소스 식별자 노출
`.github/workflows/deploy.yml`이 리터럴 AWS 계정 식별자, Role ARN, EC2 인스턴스 ID를 포함하여 리소스 식별자가 코드베이스에 직접 노출됨.

### systemd 단위 파일 설치 누락
배포 워크플로우가 코드를 당겨오지만 `infra/systemd/lala-next-api.service`를 설치하지 않아 서비스가 등록되지 않고 `systemctl daemon-reload`가 실행되지 않음. 기존 설치된 서비스가 있을 수 있지만 배포 계약이 보장되지 않음.

### 런타임 프로필 검증 부재
배포 후 헬스체크가 `/readyz` 응답을 출력하지만 `runtime_profile=api`, `static_snapshot_fallback=disabled`, `db-backed` 모드를 명시적으로 검증하지 않아 잘못된 구성이 배포될 수 있음.

### 문서화 부재
AWS 배포 런북이 GitHub Actions 변수 사용법과 API 런타임 프로필(`api`)을 문서화하지 않고 `/opt/lala-next/.env`를 시크릿 소스로 오인할 수 있게 함.

---

## 변경 사항

### 1. `.github/workflows/deploy.yml`
- **리터럴 식별자 제거**: `role-to-assume`과 `INSTANCE_ID`를 `${{ vars.AWS_DEPLOY_ROLE_ARN }}`과 `${{ vars.AWS_EC2_INSTANCE_ID }}`로 변경
- **systemd 단위 설치 추가**: SSM 명령이 추적된 unit을 root 소유 0644 파일로 설치하고 `daemon-reload`, 재시작, active 검증을 수행
- **운영 동작 보존**: unit이 Nginx upstream 포트 8000, 공모전 공개 접근, snapshot 비활성화, live OpenAI 활성화를 명시
- **런타임 계약 검증 강화**: 헬스체크가 `data.status==ok`, `mode.overall==db-backed`, `checks.runtime_profile==api`, `checks.static_snapshot_fallback==disabled`를 명시적으로 어서션

### 2. `apps/api/tests/test_task5_deployment_contract.py`
- **리터럴 식별자 금지 테스트**: 12자리 계정 번호, Role ARN, EC2 인스턴스 ID가 workflow 파일에 없는지 검증
- **GitHub Actions 변수 참조 테스트**: `AWS_DEPLOY_ROLE_ARN`, `AWS_EC2_INSTANCE_ID` 변수 참조 확인
- **systemd 설치 테스트**: 배포 워크플로우가 systemd 단위를 설치하고 daemon-reload, 재시작, 활성 상태 확인을 포함하는지 검증
- **런타임 계약 테스트**: 헬스체크가 runtime_profile, static_snapshot_fallback, db-backed 모드를 검증하는지 확인

### 3. `docs/operations/aws-deployment-runbook.md`
- **GitHub Actions 변수 문서화**: `AWS_DEPLOY_ROLE_ARN`, `AWS_EC2_INSTANCE_ID` 변수명과 용도 설명 추가
- **런타임 프로필 문서화**: API 서비스가 `runtime_profile=api`로 실행되고 Secrets Manager + EC2 IAM role을 통해 시크릿을 획득함 명시
- **시크릿 소스 명확화**: `/opt/lala-next/.env`는 CORS_ALLOW_ORIGINS 같은 비밀이 아닌 구성만 포함하며 RDS 비밀번호나 API 키는 포함하지 않음 명시
- **보안 정책 강조**: 실제 리소스 ID와 값은 GitHub Actions 설정에서 관리하며 결코 커밋되지 않아야 함 명시

---

## 검증 계약

### 배포 계약 테스트
```bash
uv run pytest apps/api/tests/test_task5_deployment_contract.py -k "aws_deploy_yml"
```

- 워크플로우에 리터럴 계정 번호, Role ARN, EC2 인스턴스 ID 없음
- GitHub Actions 변수 `AWS_DEPLOY_ROLE_ARN`, `AWS_EC2_INSTANCE_ID` 참조됨
- systemd 단위가 `/etc/systemd/system/lala-next.service`로 설치됨
- `daemon-reload`, `restart`, `is-active` 실행됨
- 헬스체크가 runtime_profile, static_snapshot_fallback, db-backed 검증

### 런북 문서화 테스트
```bash
uv run pytest apps/api/tests/test_task5_deployment_contract.py -k "aws_runbook"
```

- `AWS_DEPLOY_ROLE_ARN`, `AWS_EC2_INSTANCE_ID` 문서화됨
- `runtime profile api` 문서화됨
- `Secrets Manager` 언급됨
- 실제 값이 커밋되지 않아야 함 명시됨
- `.env`가 시크릿 소스로 오인되지 않음

---

## 의도적 미포함 사항

### Semantic RAG 마이그레이션
현재 배포된 API는 `rag_retrieval_mode=legacy`, `rag_embedding_method=local-hash`를 사용. 이 PR은 런타임 프로필(`api`)과 정적 스냅샷 폴백(`disabled`)만 검증하며 RAG 설정은 검증하지 않음. Semantic RAG 마이그레이션은 별도 명시적 런타임 마이그레이션으로 차후 처리.

### 기능 동작 변경
API 기능 동작, RAG 코드, Flutter 코드, 정식 SQL, 무관 문서는 변경하지 않음.

### 보안 약화
테스트를 약화하거나 비밀 값/자리표시자를 추가하지 않음.

---

## 영향

### 보안 강화
- AWS 리소스 식별자가 public repo에서 제거됨
- GitHub Actions Variables로 리소스 ID 격리

### 배포 계약 보장
- systemd 단위가 항상 설치되고 등록됨
- API가 `runtime_profile=api`로 실행됨
- Secrets Manager + IAM role을 통한 시크릿 관리가 보장됨
- 배포 후 런타임 상태가 명시적으로 검증됨

### 운영 투명성
- GitHub Actions 변수 사용법이 문서화됨
- 런타임 프로필과 시크릿 소스가 명확해짐
- `/opt/lala-next/.env`가 시크릿 소스가 아님 명시됨

---

## 검토 포인트

1. **GitHub Actions Variables 설정**: `AWS_DEPLOY_ROLE_ARN`, `AWS_EC2_INSTANCE_ID` 변수가 리포지토리에 설정되어야 함
2. **기존 systemd 단위 백업**: EC2에 기존 `/etc/systemd/system/lala-next.service`가 있다면 백업 후 새 단위로 덮어씌워짐
3. **SSM 명령 확장**: 배포 명령에 systemd 설치가 추가되어 배포 시간이 약간 증가할 수 있음
4. **헬스체크 실패 처리**: runtime_profile이 `api`가 아니면 배포가 실패하므로 설치된 systemd unit과 IAM secret 조회 상태를 확인

---

## 관련 링크

- GitHub Actions 배포: `.github/workflows/deploy.yml`
- systemd 단위: `infra/systemd/lala-next-api.service`
- 배포 계약 테스트: `apps/api/tests/test_task5_deployment_contract.py`
- AWS 런북: `docs/operations/aws-deployment-runbook.md`
