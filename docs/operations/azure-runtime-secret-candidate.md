# Azure 운영 비밀 조회 계약

**코드는 준비됐지만 운영 backend 전환은 별도다.** 2026-10-10 로컬 후보를 검토하여
저장소 통합용으로 보완한 계약이며, 실제 Azure 관리 ID·비밀 조회 성공을 뜻하지 않는다.
[실행 순서와 남은 조건](azure-managed-prepayment-readiness.md)을 함께 확인한다.

| 프로필 | 동작 |
|---|---|
| `api` / `worker`, backend 미지정 | 기존 AWS IAM 역할 + Secrets Manager |
| `api` / `worker`, `LALA_SECRET_BACKEND=azure` | Azure ManagedIdentityCredential + Key Vault |
| `ci` | 테스트 환경값만 사용; 클라우드·dotenv 접근 없음 |
| `local` | 기존 로컬 실행 계약 유지 |

Azure에서는 `KEY_VAULT_URL`과 정확한 `LALA_ALLOWED_KEY_VAULT_HOSTS`를 지정한다.
HTTPS, 유효한 단일 Vault 호스트, 루트 경로만 허용한다. ONMU Vault는 허용하지 않는다.
`AZURE_CLIENT_ID`는 API/worker에 연결한 사용자 할당 관리 ID다. 생략하면 시스템 할당
관리 ID를 사용한다. Azure CLI·개인 credential·DefaultAzureCredential 체인을 사용하지 않는다.

필수 비밀 조회 실패는 시작/필수 기능 검사를 중단한다. 누락·권한 거부·일시 장애·잘못된 값을
구분하되 오류에는 논리 이름만 남긴다. Azure 실패 시 AWS·dotenv·프로세스 비밀값으로
우회하지 않는다. 비밀 매핑은 기존 `runtime_secrets.py` registry를 유지한다.

요청마다 설정을 읽는 현재 앱 구조를 고려해 결과를 프로세스 메모리에만 저장한다.

- 정상 조회: 최대 5분. 실패/없는 선택 비밀: 15초. 최대 256개, Vault·관리 ID·논리 이름별 분리.
- 캐시가 만료되면 다시 조회한다. 실패했을 때 만료된 정상값을 되살리지 않는다.
- allowlist는 캐시 조회 전에도 검사한다. Vault/관리 ID가 달라지면 캐시를 공유하지 않는다.
- SDK 연결/읽기 제한과 재시도 상한을 둔다. 전체 앱 시작 시간은 선택 비밀 개수와 실제
  관리 ID/네트워크 상황을 포함해 스테이징에서 확인한다.
- 비밀 회전 반영은 최대 5분 지연될 수 있다. 즉시 폐기가 필요하면 앱 revision을 재시작하고
  실제 권한·값을 다시 검증한다. 비밀값·전체 DSN을 로그나 repr로 내보내지 않는다.

실제 API 이미지, 별도 DB 앱 역할, 정식 스키마, Logto/OAuth, DB-backed 앱 흐름과 복원을
검증해야 배포를 수용할 수 있다. 오프라인 stub 테스트는 그 검증을 대체하지 않는다.
