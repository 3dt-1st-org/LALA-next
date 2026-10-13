# Azure 관리형 이관 — 결제 전 준비와 실행 경계

**상태: 코드·검증 준비 단계. 실제 Azure 배포·데이터 이관·운영 전환 완료가 아니다.**

2026-10-14 기준 준비 문서다. 기존 운영을 유지한 채 새 관리형 환경을 준비한다.
과거 `dev` 테넌트의 배포 성공 기록을 새 환경의 준비 완료 근거로 사용하지 않는다.

## 이번 변경으로 준비한 것

| 영역 | 저장소에 준비한 내용 | 실제 환경에서 남은 확인 |
|---|---|---|
| 비밀 조회 | AWS 기본값 유지, Azure 관리 ID를 명시적으로 선택, 허용 Vault 검사, 오류 분류·캐시 | 관리 ID 연결, Key Vault 권한·실제 값 |
| 관리형 구성 | Container Apps, PostgreSQL, VNet·사설 DNS, Key Vault, ACR, 로그 템플릿 | 구독·할당량·지역·주소 대역·최종 SKU |
| 초기 생성 | 기본 `deployApi=false`. 인프라와 API 시작을 분리 | DB 앱 계정·스키마·인증·이미지 준비 후 API 생성 |
| 배포 절차 | 수동 실행, 환경별 OIDC, 성공한 main CI의 SHA 확인 | 보호된 staging/prod 환경과 담당자 승인 |
| 운영 승격 | 스테이징에서 검증한 이미지 digest를 운영 ACR로 복사 | 동일 테넌트 ACR 읽기·가져오기 권한, 기능 검증 기록 |
| 자동 배포 방지 | `[skip deploy]` 커밋은 AWS/Vercel 배포 제외, 이전 Azure dev 자동 생성 중단 | 병합 후 배포 job이 실제로 건너뛰었는지 확인 |
| 회귀 검사 | Azure 실패·캐시·배포 게이트 테스트, Bicep 컴파일·Docker 빌드 CI | 실제 Azure 네트워크·DB 복원·앱 검증 |

병합은 소스 통합이다. 결제, 리소스 생성, GitHub 환경/Entra 권한 변경, 비밀 이관,
DB 쓰기, DNS 변경, 유료 AI·음성 호출을 실행하지 않는다.

## 결제 전에 실행 가능한 검사

운영 환경 파일이 없는 별도 checkout에서 진행한다.

```bash
uv sync --extra dev --frozen
LALA_RUNTIME_PROFILE=ci uv run --frozen pytest apps/api/tests
uv run --frozen pre-commit run --all-files
az bicep build --file infra/azure/main.bicep --outfile /tmp/lala-azure-main.json
docker build --platform linux/amd64 --file infra/azure/api.Dockerfile --tag lala-api:ci .
```

Bicep 컴파일과 Docker 빌드는 Azure 로그인이나 유료 Azure 리소스를 요구하지 않는다.
Docker가 없는 PC에서는 CI의 컨테이너 빌드 결과를 확인한다. 템플릿 컴파일은 RBAC,
구독 상태, 정책, 할당량, 서비스 가용성 검증을 대신하지 않는다.

CI는 API/Unix/Flutter, 격리된 PostgreSQL 회귀 검사와 Azure 템플릿·이미지 빌드/네트워크 차단 기동 검사를 수행한다.
PostgreSQL CI의 일회용 DB는 Azure DB가 아니며 운영 데이터도 사용하지 않는다.

## 결제·실행 승인 후 진행 순서

1. **대상 확정:** 결제 담당자가 구독·테넌트·결제 수단·청구/증빙 기준·예산을 확인한다.
   기술 담당자는 Korea Central의 SKU/할당량과 CIDR 충돌을 다시 확인한다.
2. **접근 준비:** `staging`과 `prod` GitHub Environment를 만들고 main만 허용한다.
   사용 가능한 환경 보호 규칙·리뷰어 승인 기능을 확인한다. 자동 실행은 추가하지 않는다.
   Entra OIDC subject는 각 `repo:<owner>/<repo>:environment:<환경>`으로 분리한다.
3. **인프라 생성:** 예시 파라미터를 최종 예산에 맞게 검토한다. 처음에는 `deployApi=false`로
   리소스만 만든다. `postgresAdminPassword`와 `postgresAppPassword`는 안전한 임시
   파라미터 파일/보안 저장소 참조로 전달하며 명령 인자·Git에 값을 넣지 않는다.
4. **DB·비밀 준비:** 승인된 private-network 실행 위치에서 별도 앱 DB 계정과 권한을 만든다.
   Bicep은 계정이나 SQL 스키마를 만들지 않는다. 관리자 계정으로 API를 실행하지 않는다.
   원본 백업을 격리 DB에 복원해 확장 기능·정식 SQL·행 수·무결성·복원 시간을 검증한다.
   Logto/OAuth와 필요한 비밀을 LALA Key Vault에 등록한다. 관리 ID는 해당 Vault 읽기와
   자기 ACR pull만 허용한다.
5. **첫 API 생성:** CI를 통과한 SHA로 실제 이미지를 빌드·push하고 digest를 확인한다.
   해당 환경 ACR의 `registry/lala-api@sha256:<digest>`를 `containerImage`로 지정하여
   검토한 Bicep을 `deployApi=true`로 적용한다. hello-world나 가변 태그로 완료를 판정하지 않는다.
   이 최초 생성은 아래의 기존 앱 업데이트 워크플로와 별도 작업이다.
6. **스테이징 수용 검사:** `/healthz`와 `/readyz`뿐 아니라 로그인·계정 전환·장소 조회·저장·복원,
   Flutter 지도/위치/언어, 외부 연동을 검증한다. 유료 AI/음성은 별도 승인 후 제한적으로 확인한다.
   통과한 SHA와 이미지 digest, 검사 결과를 기록한다.
7. **운영 배포·전환:** 운영 ACR로 같은 digest를 가져와 일치 여부를 검사한다.
   운영 API 검증 후에만 별도 승인으로 DNS/앱 API 주소를 전환한다. 문제가 생기면 이전
   이미지/트래픽 대상으로 되돌린다. DB 쓰기가 시작된 후에는 역방향 데이터 정합성까지
   고려하며, DNS만 되돌리는 것을 전체 DB 복구로 간주하지 않는다.

위 단계는 **앞으로 승인 후 실행할 작업**이며 이번 PR에서 실행한 작업 목록이 아니다.

## 파라미터 초안

| 항목 | staging 예시 | prod 예시 |
|---|---|---|
| 파일 | `infra/azure/staging.parameters.example.json` | `infra/azure/prod.parameters.example.json` |
| API | 0.5 vCPU / 1 GiB, 0~1개 | 0.5 vCPU / 1 GiB, 1~3개 |
| DB | PostgreSQL 15 / B1ms / 32 GiB | PostgreSQL 15 / D2ds_v5 / 64 GiB |
| 백업 | 7일 | 14일 |
| 네트워크 | DB 사설 접근, 별도 subnet/DNS | DB 사설 접근, 별도 subnet/DNS |
| 초기 API·유료 기능 | API 생성 OFF, AI·음성 OFF | API 생성 OFF, AI·음성 OFF |

두 파일은 비밀과 실제 리소스 식별자가 없는 **예시**다. 최종 구매안이나 자동 실행 가능한
완성 파라미터가 아니다. 이 구성은 DB HA와 지리 중복 백업을 제공하지 않는다. 확장 허용 목록은
PostGIS/vector/pgcrypto이며, SQL의 `CREATE EXTENSION` 및 데이터 복원은 별도다.

## 수동 API 업데이트의 필수 설정

환경별 변수: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_RESOURCE_GROUP`, `AZURE_CONTAINER_APP_NAME`, `AZURE_REGISTRY_NAME`.

- `AZURE_MANAGED_INFRA_READY=true`는 실제 인프라·DB·인증·권한·환경 보호 준비 후에만 설정한다.
  저장소 전체 변수로 우회하지 않는다. 현재 준비 단계에서는 비워 둔다.
- `source_sha`는 성공한 main push CI가 있는 전체 SHA여야 한다. PR SHA, 태그 이름, dev SHA는 안 된다.
- `prod`는 `AZURE_STAGING_VERIFIED_SHA`, `AZURE_STAGING_VERIFIED_IMAGE`,
  `AZURE_STAGING_REGISTRY_ID`도 필요하다. 담당자가 스테이징 수용 검사를 마친 후 기록한다.
- 스테이징 OIDC에는 대상 ACR push와 해당 Container App 업데이트 권한이 필요하다.
  운영 OIDC에는 소스/대상 ACR의 이미지 읽기·가져오기 권한과 운영 앱 업데이트 권한이 필요하다.
  현재 Bicep의 `AcrPush` 부여만으로 운영 registry 간 import 권한까지 준비됐다고 간주하지 않는다.
- 워크플로는 기존 앱의 이미지만 업데이트한다. RBAC/비밀 변경, DB 마이그레이션, 최초 인프라
  생성, DNS 전환은 하지 않는다. API 검사는 실제 Azure 앱 FQDN을 사용한다.
- 성공한 health/readiness만으로 `AZURE_STAGING_VERIFIED_*`를 자동 설정하지 않는다.
  실제 기능·복원 검사를 확인한 담당자가 수용 여부를 결정한다.

## 배포하지 않는 PR 병합

이번 준비 PR의 **최종 main 커밋 메시지**에 `[skip deploy]`를 포함한다. CI는 그대로 실행한다.
AWS/Vercel은 성공한 같은 저장소의 최신 main push와 배포 의도를 별도로 검사한다.
과거 CI 재실행, PR/fork CI, 실패한 CI, 메시지가 누락된 이벤트도 배포하지 않는다.
이 표시는 다음 일반 변경의 자동 배포까지 영구 정지하는 설정은 아니다.

## 계약과 공식 근거

- [Azure 런타임 비밀 계약](azure-runtime-secret-candidate.md)
- [기존 AWS 기본 계약](aws-secrets-manager-runtime-contract.md)
- [GitHub workflow_run](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run)
- [Key Vault 비밀 캐시](https://learn.microsoft.com/en-us/azure/key-vault/secrets/secure-secrets)
- [Container Apps 상태 검사](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
- [ACR 간 이미지 가져오기](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-import-images)
