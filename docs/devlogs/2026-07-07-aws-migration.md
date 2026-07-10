# Devlog - 2026-07-07 AWS 클라우드 마이그레이션

이 로그는 단일 Mac 온프레미스 운영 환경을 AWS EC2 + RDS로 이전한 작업을 기록한다.
런북(`docs/operations/aws-deployment-runbook.md`)과 마찬가지로 비밀번호, DSN, 라이브 자격증명 값은 의도적으로 생략한다. 리소스 ID와 운영 명령어는 런북을 참조.

## 목표

- 단일 Mac SPOF(단일 장애점) 제거 — 하드웨어 1대 + 전원/세션 상태에 의존하던 구조 탈피.
- 무료 또는 최소 비용으로 운영 가능한 클라우드 환경 구축.
- FastAPI + PostgreSQL/PostGIS 스택을 아키텍처 변경 없이 이전.
- 컨테스트 윈도우 이후에도 지속 가능한 운영 기반 마련.

## 배경

이전 온프레미스 환경은 `Cloudflare Tunnel → LaunchAgent(FastAPI) → Docker Postgres` 구조로
단일 Mac 위에서 동작했다. Mac sleep/로그아웃/Docker 데몬 다운 등이 전체 서비스 장애로
이어지는 SPOF 구조였다(`docs/operations/devlog/2026-06-26-onprem-hardening.md` 참조).

7개 클라우드 플랫폼 비교(`docs/operations/cloud-hosting-comparison-2026-07-06.md`) 후
GCP Cloud Run을 1순위로 검토했으나, 기존 GCP 계정에 청구 계정이 이미 있어 90일 $300
트라이얼 자격이 없었고, AWS 신규 계정의 12개월 무료 티어(EC2 + RDS 모두 포함)가
가장 확실한 무료 운영 경로로 판단해 AWS로 결정했다.

## 결정: App Runner → EC2 + RDS 전환

초기에는 관리 부담이 적은 App Runner를 검토했으나 두 가지 이유로 EC2로 전환했다:

1. **App Runner는 무료 티어가 전혀 없다.** (시간당 과금, ~$5-15/월 예상)
2. **신규 계정에서 App Runner가 즉시 활성화되지 않았다.** (`SubscriptionRequiredException`)

EC2 t3.micro + RDS db.t3.micro 조합은 둘 다 12개월 무료 티어(각 750시간/월 = 24/7 실행 가능)에
해당하며, App Runner 대비 운영 부담은 늘지만 비용은 사실상 제로로 갈 수 있다.

## 작업 항목

### 1. 네트워크 인프라 (VPC)

- 커스텀 VPC + 퍼블릭 서브넷 1개 + 프라이빗 서브넷 2개(서로 다른 AZ) 구성.
- 인터넷 게이트웨이 + 퍼블릭 라우팅 테이블.
- RDS는 프라이빗 서브넷에 배치해 인터넷에서 직접 접근 차단.
- 보안그룹: EC2(HTTP/HTTPS/SSH)와 RDS(5432, EC2 보안그룹에서만) 분리.

### 2. RDS PostgreSQL + PostGIS

- PostgreSQL 15.18, db.t3.micro, 20GB 스토리지.
- 커스텀 DB 파라미터 그룹으로 `rds.allowed_extensions = postgis,pgcrypto,vector` 설정.
  - 이 값은 `dynamic` 파라미터라도 적용에 **재부팅이 필요**하다는 점을 확인했다
    (`pending-reboot` → `in-sync`).
- 확장 설치: postgis 3.4.6, pgcrypto 1.3, vector 0.8.2 — 온프레미스 로컬 DB와 동일 세트.
- canonical SQL 스키마(`sql/canonical/000~050`)를 순서대로 적용해 10개 스키마, 30개 테이블 구축.
  - 로컬 DB에는 실제 비즈니스 데이터가 없었고(`spatial_ref_sys`만 존재), 이전 운영도
    snapshot fallback 모드였음을 확인. 따라서 데이터 마이그레이션 대신 **스키마 구축**에 집중.

### 3. EC2 + FastAPI 배포

- Amazon Linux 2023, t3.micro, Elastic IP(고정 퍼블릭 IP) 연결.
- GitHub main 브랜치 클론 → Python 3.11 가상환경 → `pip install -e .` 로 의존성 설치.
- RDS 연결 정보를 `.env`에 설정(`DB_DSN`, `LALA_PUBLIC_CONTEST_ACCESS=true`).
- systemd 서비스(`lala-next.service`)로 uvicorn(workers=2) 등록 — 재부팅 시 자동 시작.
- Nginx 리버스 프록시로 포트 80 → 8000 연결 (Amazon Linux 2023은 기본 nftables라
  iptables 대신 Nginx를 선택 — SSL 종료에도 유리).

### 4. 검증 결과

배포 직후 `/readyz`:

```
overall : db-backed      ✅ (이전: degraded)
db      : configured      ✅
postgis : configured      ✅
data    : db-backed       ✅
ai      : disabled       (live AI 미사용 — 컨테스트 종료 후 비용 절감)
```

온프레미스 정상 상태와 동일한 DB-backed 모드 달성.

### 5. 모니터링 (CloudWatch)

- SNS 주제 + 이메일 구독 생성(팀원 인증 필요).
- 알람 5종: EC2 CPU 고사용, EC2 상태확인 실패, RDS CPU 고사용, RDS 연결수 고사용,
  RDS 여유 스토리지 부족.

### 6. 백업 자동화

- 무료 티어에서 RDS 자동 백업 보존 기간이 **1일로 제한**된다는 점을 발견
  (`FreeTierRestrictionError`).
- 우회책으로 EC2에서 매일 RDS를 `pg_dump` 후 S3 버킷에 업로드하는 스크립트 작성.
- S3 버킷: 버저닝 활성화 + 수명주기 정책(30일 Glacier, 90일 삭제).
- systemd timer로 매일 03:17 UTC 자동 실행(cron 대신 — Amazon Linux 2023 권장).
- EC2 IAM 인스턴스 프로파일로 S3 쓰기 권한 부여(정적 자격증명 대신).

## 남은 작업

- **SSL/도메인**: Route 53 또는 Cloudflare DNS로 `api.lala-next.cloud` 연결 + ACM 인증서 + Nginx HTTPS.
- **data_freshness 정상화**: 날씨 관측 데이터 갱신(`PUBLIC_DATA_SERVICE_KEY` 설정 후 갱신 스크립트).
- **CORS 도메인 제한**: 운영 전환 시 `*` → 도메인 한정.

## 작업 항목 (추가)

### 7. 운영 강화 (모니터링/백업/비밀번호)

- **CloudWatch 알람 5종** + SNS 이메일 구독(팀원 인증 필요): EC2 CPU/상태확인, RDS CPU/연결수/스토리지.
- **백업 자동화**: 무료 티어에서 RDS 자동 백업 보존이 1일로 제한됨을 발견(`FreeTierRestrictionError`).
  우회책으로 EC2에서 매일 `pg_dump` → S3 업로드(systemd timer 03:17 UTC). 버킷은 버저닝 + 30일 Glacier + 90일 삭제.
  EC2 IAM 인스턴스 프로파일로 S3 권한 부여(정적 키 대신).
- **비밀번호 강화**: RDS 마스터 비밀번호를 강력한 값으로 변경 + Secrets Manager 저장. EC2 `.env`/백업 스크립트도 새 비밀번호로 갱신 후 FastAPI 재시작 → `db-backed` 유지 확인.

### 8. SSL/도메인 (Cloudflare + Let's Encrypt)

- 도메인 `lala-next.cloud`의 네임서버는 Cloudflare. (가비아에서 변경한 값은 네임서버가 Cloudflare를 가리키므로 무효.)
- **핵심 이슈**: `api` 서브도메인이 이전 Tunnel CNAME(`cfargotunnel.com`)으로 남아 A 레코드를 덮고 있었음.
- Cloudflare API 토큰(`.env`의 `CLOUDFLARE_API_TOKEN`)으로 CLI 자동화:
  1. 기존 Tunnel CNAME 삭제 + `api` A 레코드 `54.160.16.183`(회색 구름) 추가.
  2. certbot(Let's Encrypt)으로 인증서 발급 + Nginx HTTPS 자동 설정 + HTTP→HTTPS 리다이렉트.
  3. Cloudflare SSL 모드 Full (strict) 설정 + `api`를 오렌지 구름(Proxied)으로 전환.
  4. certbot 갱신 timer 매일 02:30 UTC 등록.
- 결과: `https://api.lala-next.cloud` 정상 작동(`/readyz` = db-backed). Cloudflare 보안/DDoS 방어 + EC2 유효 인증서 이중 레이어.

## 작업 항목 (추가 2)

### 9. data_freshness — 근본 원인 파악, 별도 작업으로 분리

- 날씨 갱신 스크립트(`--apply`)는 `succeeded`로 끝났지만 `travel.weather_observations`에 **0건** 삽입.
- 원인: `check_data_freshness_status`가 **4개 테이블 모두** 최근 데이터를 요구 —
  `travel.public_places`, `travel.weather_observations`, `analytics.place_score_snapshots`, `rag.knowledge_chunks`.
  스키마만 있고 비즈니스 데이터가 비어있어(이전 온프레미스도 snapshot fallback 모드) 날씨 갱신 대상 자체가 0개.
- 결론: 이것은 **데이터 적재 파이프라인 구축** (KOPIS/tour API/card spending/RAG ingest)이라는 별도 작업.
  dev_reset seed는 헤더에 `Do not run against production databases` 명시라 production 부적절.
  → 인프라 완료 관점에서는 블로킹 처리하고 문서화만 수행.

### 10. CORS 도메인 한정 + 환경변수명 버그 수정

- EC2 `.env`에 잘못 들어가 있던 `LALA_CORS_ALLOW_ORIGINS=*`를 발견 — config는 `CORS_ALLOW_ORIGINS`(LALA_ 접두사 없음)를 읽으므로 **설정이 적용되지 않고 있었음**.
- 올바른 환경변수명 + `https://lala-next.cloud,https://www.lala-next.cloud` 한정으로 수정.
- 검증: `Origin: https://lala-next.cloud` 요청에 `access-control-allow-origin` 헤더 정상 반환 확인.

### 11. CloudWatch Logs 스트리밍

- EC2 IAM 역할에 `lala-next-cloudwatch-logs-policy` 추가(logs 그룹/스트림/PutLogEvents).
- `amazon-cloudwatch-agent` 설치 + 설정: `lala-next/fastapi`, `lala-next/nginx`, `lala-next/backup` 로그 그룹.
- 검증: 트래픽 생성 후 `aws logs filter-log-events`로 fastapi/nginx 로그 이벤트 확인 완료.

### 12. 프론트엔드/백엔드 도메인 분리 복구

- 초기 착오: 루트 `lala-next.cloud`/`www`를 EC2(백엔드)로 리다이렉트함 → 사용자 피드백 "프론트엔드로 돼야지".
- 조사: Vercel에 프로젝트 2개 존재 — `lala-next`(프론트엔드, Flutter 웹) / `lala-next-api`(백엔드). 루트는 원래 Vercel 프론트엔드였음.
- 복구: Cloudflare에서 루트/www A 레코드를 `54.160.16.183`(EC2) → `76.76.21.21`(Vercel)로 변경 + 회색 구름(Vercel이 자체 SSL 처리). EC2의 루트 Nginx server 블록은 제거.
- **DNS 권한 주의**: 네임서버가 Cloudflare → 가비아 레코드는 무시됨. 가비아에 남은 Azure CNAME/TXT도 무효.
- 최종 구조: `lala-next.cloud`/`www` → Vercel(프론트엔드, 회색 구름), `api.lala-next.cloud` → EC2(백엔드, 오렌지 구름 + Full strict + Let's Encrypt). CORS 허용 도메인(`https://lala-next.cloud`)으로 프론트엔드↔백엔드 연결 확인.

## 작업 항목 (추가 3)

### 13. OpenAI API 지원 추가 (코드 변경)

- 목표: Azure OpenAI 대신 일반 `OPENAI_API_KEY`(api.openai.com)로 RAG 임베딩 실행.
- 기존 코드는 `EmbeddingMethod = Literal["local-hash", "azure-openai"]`로 `openai` 미지원, `AzureOpenAI` 클라이언트 전용이었음.
- 변경:
  - `config.py`: `openai_api_key`, `openai_base_url`(기본 api.openai.com/v1), `openai_embedding_model`(기본 text-embedding-3-small) Settings 추가
  - `rag_index.py`: `EmbeddingMethod`에 `"openai"` 추가 + `build_openai_embedding()` 구현 (OpenAI 클라이언트, enable_live_ai 가드)
  - `run_rag_index.py`: argparse choices에 `openai` 추가 (초기 누락, 별도 fix PR)
  - `.env.example`: OPENAI_* 키 문서화
  - 테스트: 라우팅 + 키 가드 단위 테스트 (24개 통과)
- PR #7(기능), PR #8(choices fix) 머지.
- 비용: text-embedding-3-small $0.02/1M 토큰. 파이프라인 1회 약 $0.02-0.06.

### 14. 비즈니스 데이터 적재 파이프라인 실행 (data_freshness=configured 달성)

DAG 순서대로 EC2에서 실행 (경기+서울, t3.micro 메모리 고려해 `--rows`/`--limit` 축소, swap 2G 추가):
1. **TourAPI** (places): 경기 40 + 서울 40 = **80행** ← 모든 것의 기반
2. **KCISA culture** (경기): 10행
3. **KOPIS** (경기 41 + 서울 11): 40행
4. **카드 소비 파일**: area_monthly 3,650 + demographic 57,832행
5. **프랜차이즈 참조**: 500행
6. **프랜차이즈 identity**: 20행 매칭
7. **place_score_batch**: **80행** (LEFT JOIN으로 places만 있어도 생성)
8. **RAG index** (openai 임베딩): **130 청크**
9. **weather refresh** (가장 마지막, 24h): 20행

결과: 4개 타겟 테이블 모두 채워져 `/readyz data_freshness=configured` 달성, `overall=db-backed`.

### 15. live_ai 모드 트레이드오프

- RAG openai 임베딩 실행을 위해 `LALA_ENABLE_LIVE_AI=true` 필요.
- 하지만 FastAPI 런타임이 true면 `/readyz` ai 모드가 Azure OpenAI 설정을 검사 → degraded.
- 해결: 임베딩은 **배치 도구 실행 시에만** 임시로 true, FastAPI 런타임은 false 유지 (ai=disabled, overall=db-backed).
- 학습: readyz ai 모드 체크가 Azure 전용이라 openai 설정을 안 봄 — 향후 보강 후보.

## 팀원을 위한 참고사항

- 상세 리소스 ID, SSH 접속법, 운영 명령어, 장애 플레이북은
  `docs/operations/aws-deployment-runbook.md`에 정리되어 있다.
- EC2 접속은 런북의 SSH 키 경로 사용. RDS는 EC2를 통해서만 접근 가능(퍼블릭 노출 없음).
- 코드 배포: EC2에서 `git pull` 후 의존성 변경 시 `pip install -e .` + `systemctl restart lala-next`.
- 스키마 변경: `sql/canonical/` 순서대로 RDS에 적용.
- 비용: 현재 ~$0-2/월(12개월 무료 티어). $200 신규 계정 크레딧으로 12개월+ 커버 예상.
