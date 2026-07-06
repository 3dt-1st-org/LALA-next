# 클라우드 호스팅 비교 및 추천 보고서
**날짜**: 2026년 7월 6일
**애플리케이션**: LALA-next (FastAPI + PostgreSQL/PostGIS + Azure AI Speech)
**현재 상태**: 단일 Mac 온프레미스 (SPOF 우려)

---

## 요약

| 플랫폼 | 전체 스택 무료? | PostGIS | 월 예상 비용 | 아키텍처 변경 | 운영 부담 | 팀 협업 (4인) |
|--------|---------------|---------|------------|-------------|-----------|-------------|
| **AWS** | ⚠️ 12개월 한정 | ✅ 네이티브 | ~$12-50 | 낮음 | 중간 | ✅ 우수 |
| **GCP** | ⚠️ 90일 트라이얼 | ✅ 네이티브 | ~$35-50 | 낮음 | 낮음 | ✅ 우수 |
| **Azure** | ⚠️ 12개월 한정 | ✅ 네이티브 | ~$30-40 | 낮음 | 중간 | ✅ 우수 |
| **Supabase** | ❌ (500MB DB 제한) | ✅ 네이티브 | ~$46-61 | **높음** | 낮음 | ✅ 우수 |
| **Firebase** | ❌ PostgreSQL 없음 | ❌ 없음 | ~$15-25 | **높음** | 낮음 | ⚠️ 제한적 |
| **Vercel** | ❌ (0.5GB DB 제한) | ✅ Neon 통해서 | ~$20-30 | 중간 | 낮음 | ✅ 우수 |
| **Cloudflare** | ❌ 네이티브 DB 없음 | ⚠️ Hyperdrive | ~$5-30 | **높음** (베타) | 중간 | ✅ 우수 |

**최상위 추천**: **Google Cloud Platform (GCP)** - PostGIS 지원, 넉넉한 무료 티어, 최소 아키텍처 변경의 최적 균형

---

## 상세 비교

### 1. AWS (Amazon Web Services)

#### 무료 티어 구조 (2025년 7월 변경)
- **신규 고객**: 6개월간 $200 크레딧
- **항상 무료**: Lambda (100만 요청 + 40만 GB-초), S3 (5GB), CloudFront (1TB), ACM
- **12개월 무료**: EC2 t2/t3.micro (750시간), RDS PostgreSQL (750시간 + 20GB 스토리지)

#### FastAPI용 컴퓨팅
- **Lambda**: 항상 무료 100만 요청 + 40만 GB-초, 15분 지속 시간 제한
- **EC2**: 12개월 무료 티어 (750시간 t2/t3.micro), 이후 ~$8-12/월
- **App Runner/ECS**: 무료 티어 없음, ~$2.50/월부터

#### 데이터베이스 (PostgreSQL + PostGIS)
- **RDS PostgreSQL**: 12개월 무료 (750시간 + 20GB 스토리지), PostGIS **완전 지원**
- **무료 티어 후**: ~$12/월 (db.t3.micro)

#### 스토리지 및 네트워킹
- **S3**: 항상 무료 5GB + 1GB 송신
- **CloudFront**: 항상 무료 1TB 전송
- **Route 53**: 영역당 $0.50/월 (**무료 아님**)
- **ACM**: 항상 무료 SSL 인증서

#### 서버리스 제약사항
- Lambda: 15분 지속 시간 제한, 콜드 스타트, WebSocket 지원 제한

#### 월 예상 비용 (무료 티어 후)
- **최소**: ~$12.50/월 (Lambda + RDS + Route 53)
- **중간 트래픽**: ~$30-50/월

#### 장점
- 포괄적인 서비스 포트폴리오
- RDS의 강력한 PostGIS 지원
- 넉넉한 항상 무료 서비스 (Lambda, S3, CloudFront)
- 잘 문서화된 성숙한 플랫폼

#### 단점
- 12개월 무료 티어 (영구적 아님)
- Route 53 DNS 무료 아님
- Lambda 지속 시간 제한으로 일부 작업 제약 가능
- 현대 플랫폼보다 높은 복잡성

#### 팀 협업 기능 (4인 팀)
- ✅ **IAM**: 세분화된 권한 관리, 역할 기반 액세스 제어
- ✅ **Organizations**: 여러 계정 통합 관리
- ✅ **Resource Tagging**: 팀/프로젝트별 리소스 분류
- ✅ **CloudWatch Logs**: 중앙 집중식 로그 모니터링
- ✅ **AWS SSO**: SSO 통합, 페더레이션 지원
- ✅ **비용 공유**: 비용 할당 태그, 팀별 비용 추적

---

### 2. Google Cloud Platform (GCP)

#### 무료 티어 구조
- **90일 트라이얼**: 90일간 $300 크레딧
- **항상 무료**: 월간 제한이 있는 20+ 서비스

#### FastAPI용 컴퓨팅
- **Cloud Run** (추천): 항상 무료 24만 vCPU-초 + 45만 GiB-초 + 200만 요청
  - **지속 시간**: 최대 60분
  - **WebSockets**: **지원**
  - **FastAPI**: 컨테이너 통한 네이티브 지원
  - 무료 티어 후: $0.00002475/vCPU-초 + $0.00000276/GiB-초
- **Cloud Functions**: 200만 호출 + 40만 GB-초, 9분 제한
- **Compute Engine**: 항상 무료 1개 f1-micro VM (0.6GB RAM)

#### 데이터베이스 (PostgreSQL + PostGIS)
- **Cloud SQL PostgreSQL**: PostGIS **완전 지원**
- **데이터베이스 항상 무료 티어 없음** (30일 트라이얼만)
- **공유 코어 인스턴스**:
  - db-f1-micro: ~$7-10/월 (0.6GB RAM)
  - db-g1-small: ~$25/월 (1.7GB RAM)
- **스토리지**: ~$0.17/GB/월 SSD

#### 스토리지 및 네트워킹
- **Cloud Storage**: 항상 무료 5GB
- **로드 밸런싱**: 처음 5개 포워딩 규칙 무료 (이후 $0.025/시간)
- **SSL**: Google 로드 밸런서와 무료
- **CDN**: Cloud CDN 통합 사용 가능

#### 서버리스 제약사항
- Cloud Run: 60분 최대 지속 시간 (관대함)
- **WebSocket 지원**
- 콜드 스타트: 100-400ms

#### 월 예상 비용 (무료 티어 후)
- **Cloud Run**: $0-10/월 (대부분 워크로드 무료 티어 내)
- **Cloud SQL db-g1-small**: ~$25/월
- **스토리지**: 1GB 최소
- **합계**: ~$35-50/월

#### 장점
- Cloud Run은 FastAPI에 이상적 (컨테이너 기반, WebSocket)
- 우수한 PostGIS 지원
- 넉넉한 컴퓨팅 무료 티어 (Cloud Run)
- 60분 지속 시간 제한 (가장 관대함)
- 현대적인 개발자 경험

#### 단점
- 데이터베이스 항상 무료 티어 없음
- 90일 트라이얼은 AWS/Azure 12개월보다 짧음

#### 팀 협업 기능 (4인 팀)
- ✅ **Cloud IAM**: 세분화된 권한 관리, 역할 기반 액세스
- ✅ **Resource Manager**: 프로젝트 조직, 폴더 구조
- ✅ **Shared VPC**: 팀 간 네트워크 리소스 공유
- ✅ **Cloud Logging**: 중앙 집중식 로그 모니터링
- ✅ **Cloud Monitoring**: 통합 모니터링 대시보드
- ✅ **Billing Export**: 팀별 비용 분석 가능
- ✅ **Workspace**: 공유 작업 공간, 커스텀 역할 정의

---

### 3. Microsoft Azure

#### 무료 티어 구조
- **12개월 무료**: 신규 고객을 위한 VM, PostgreSQL, Storage
- **항상 무료**: 월간 제한이 있는 55+ 서비스

#### FastAPI용 컴퓨팅
- **Container Apps** (추천): 항상 무료 18만 vCPU-초 + 36만 GiB-초 + 200만 요청
  - **지속 시간**: 명시적 제한 없음 (consumption 플랜)
  - 무료 티어 후: 초당付费
- **Virtual Machines**: 12개월 무료 (750시간 B1s/B2pts v2/B2ats v2)
  - 무료 티어 후: B1s ~$7.59/월
- **App Service**: 항상 무료 10개 앱 (1일 1시간 F1 플랜)
- **Azure Functions**: 100만 요청/월, 230초 타임아웃

#### 데이터베이스 (PostgreSQL + PostGIS)
- **Azure Database for PostgreSQL**: PostGIS **완전 지원** (포털에서 활성화)
- **12개월 무료**: 750시간 Flexible Server B1MS + 32GB 스토리지 + 32GB 백업
- **무료 티어 후**: 티어별 가격 차이

#### 스토리지 및 네트워킹
- **Blob Storage**: 12개월 무료 5GB + 항상 무료 100GB 송신
- **대역폭**: 항상 무료 월 100GB 송신
- **SSL**: App Service 관리 인증서 **무료** (SNI SSL)
- **사용자 정의 도메인**: $11.99/년 (App Service Domain)
- **CDN**: Azure CDN Standard Microsoft 2027년 9월에 중지 예정

#### 서버리스 제약사항
- Azure Functions: 230초 HTTP 타임아웃
- WebSocket 지원: 제한적
- 콜드 스타트: 예

#### 월 예상 비용 (무료 티어 후)
- **Container Apps**: 사용량에 따라 가변
- **PostgreSQL B1MS**: 추정 (명시적 가격 미표시)
- **합계**: ~$30-40/월 추정

#### 장점
- 강력한 PostGIS 지원
- 데이터베이스 12개월 무료 티어 (넉넉함)
- FastAPI에 적합한 Container Apps
- Azure AI Speech 통합 (동일 생태계)

#### 단점
- App Service 무료 티어(F1) 사용자 정의 도메인/SSL 지원 안 함
- 2027년 Azure CDN 중지
- Azure Functions 지속 시간 제한 (230초)

#### 팀 협업 기능 (4인 팀)
- ✅ **Azure RBAC**: 세분화된 역할 기반 액세스 제어
- ✅ **Management Groups**: 구독 조직화, 계층적 관리
- ✅ **Azure AD / Entra ID**: SSO, MFA, 조건부 액세스
- ✅ **Cost Management**: 팀별 비용 분석, 예산 설정
- ✅ **Azure Monitor**: 통합 모니터링, 로그 분석
- ✅ **Azure DevOps**: CI/CD 통합, 보드 관리
- ✅ **Resource Groups**: 리소스 그룹별 액세스 제어

---

### 4. Supabase

#### 핵심 발견: 아키텍처 변경 필요
**Supabase는 FastAPI를 직접 호스팅하지 않습니다.** 다음 중 하나를 선택해야 합니다:
1. Edge Functions로 FastAPI 재작성 (Deno/TypeScript), 또는
2. 하이브리드 접근 (FastAPI는 별도 호스팅, Supabase는 DB 레이어로만 사용)

#### 무료 티어 데이터베이스 (PostgreSQL + PostGIS)
- **데이터베이스 크기**: 500MB만 (귀하의 1GB는 Pro 플랜 필요)
- **PostGIS**: ✅ **네이티브 지원** (대시보드에서 활성화)
- **백업**: ❌ 무료 티어에 포함 안 됨
- **연결**: ~60 직접, ~200 풀러

#### 컴퓨팅 옵션
- **Edge Functions**: Deno/TypeScript **전용** (Python 아님)
  - 월 50만 호출 무료
  - 50초 지속 시간 제한 (Pro에서 400초)
  - 2초 CPU 시간 제한

#### 스토리지 및 네트워킹
- **파일 스토리지**: 1GB 무료, 5GB 송신
- **사용자 정의 도메인**: 월 $10 추가
- **SSL**: 포함
- **CDN**: 기본 CDN 포함

#### 월 예상 비용
- **Pro 플랜**: 월 $25 기본
- **데이터베이스 초과분** (512MB): ~$6.40
- **사용자 정의 도메인**: $10
- **외부 FastAPI 호스팅**: ~$5-20
- **합계**: ~$46-61/월

#### 장점
- 우수한 PostGIS 지원
- 내장 인증, 스토리지, 실시간 기능
- 현대적인 개발자 경험
- TypeScript 신규 프로젝트에 적합

#### 단점
- **FastAPI 직접 호스팅 불가** (재작성 또는 하이브리드 필요)
- 무료 티어 500MB 데이터베이스 제한
- Edge Functions 지속 시간 제한 (무료 50초, Pro 400초)
- 사용자 정의 도메인 추가 비용
- 스토리지 백업 자동화 안 됨

#### 팀 협업 기능 (4인 팀)
- ✅ **Row Level Security**: 행 수준 보안 정책
- ✅ **Team 미리보기**: 여러 환경 (dev, staging, prod)
- ✅ **Database Roles**: 데이터베이스 역할 기반 액세스
- ✅ **Audit Logs**: 변경 내역 추적 (Pro 플랜)
- ✅ **SSO**: SSO 통합 (Pro 플랜)
- ✅ **Branching**: 데이터베이스 브랜치 (개발용)
- ⚠️ **제한사항**: 4인 팀은 Pro 플랜 필요 ($25/월)

---

### 5. Firebase

#### 핵심 발견: 직접 부합하지 않음
**Firebase는 귀하의 FastAPI + PostgreSQL 스택에 적합하지 않습니다.** Firebase는 Firestore(NoSQL)를 사용하며, PostgreSQL이 아닙니다.

#### 무료 티어
- **Cloud Firestore**: 1GB 스토리지 (NoSQL, PostgreSQL 호환 안 됨)
- **Cloud Functions**: 200만 호출 + 40만 GB-초
- **Cloud Storage**: 5GB
- **Firebase Hosting**: 10GB 스토리지 + 360MB/일 전송

#### PostGIS 지원
- ❌ **PostGIS 지원 없음** (Firestore는 NoSQL)

#### 필요한 아키텍처
Firebase를 사용하려면 다음이 필요합니다:
1. **Firebase Hosting** 프론트엔드용
2. **Google Cloud Run** FastAPI 컨테이너용 (GCP 통해)
3. **Google Cloud SQL** PostgreSQL + PostGIS용 (GCP 통해)

#### 월 예상 비용
- **Cloud Run**: $0-10/월
- **Cloud SQL**: ~$25/월
- **합계**: ~$15-25/월 (낮은 사용량)

#### 장점
- 좋은 프론트엔드 호스팅
- Google Cloud 서비스와 통합

#### 단점
- **PostgreSQL/PostGIS 지원 없음**
- 여러 GCP 서비스 필요
- 기본적으로 GCP 래퍼
- 사용 사례에 부적합

#### 팀 협업 기능 (4인 팀)
- ⚠️ **Firebase Authentication**: 사용자 관리 기본 제공
- ✅ **Security Rules**: 역할 기반 액세스 제한
- ✅ **Firebase App Check**: 앱 무단 사용 방지
- ⚠️ **제한사항**: 백엔드 협업 기능 제한적
- ⚠️ **데이터베이스 협업**: NoSQL 한계로 관계형 데이터 협업 어려움

---

### 6. Vercel

#### 무료 티어 컴퓨팅 (FastAPI)
- **Python 지원**: 예 (3.12, 3.13, 3.14)
- **무료 제한**: 100만 호출 + 4 CPU 시간 + 360 GB-시간 메모리
- **지속 시간**: 무료 티어에서 300초 (5분)
- **WebSocket**: 공개 베타 (새 기능)

#### 데이터베이스 (PostgreSQL + PostGIS)
- **Vercel Postgres**: **중단됨** (2024년 12월 Neon으로 마이그레이션)
- **Marketplace 통합**:
  - **Neon**: PostGIS 지원, 0.5GB 무료
  - **Supabase**: PostGIS 지원, 500MB 무료
  - **Railway**: PostGIS 지원, $5 일회성 크레딧

#### 스토리지 및 네트워킹
- **Vercel Blob**: 1GB 무료 (Hobby 플랜)
- **사용자 정의 도메인**: 무제한, 항상 무료
- **SSL**: Let's Encrypt를 통한 자동
- **CDN**: 글로벌 에지 네트워크 포함

#### 서버리스 제약사항
- **지속 시간 제한**: 300초 (무료), 1800초 (Pro 베타)
- **WebSocket**: 공개 베타
- **메모리**: 2GB (무료), 4GB (Pro)

#### 월 예상 비용
- **Pro 플랜**: 월 $20 기본
- **Neon 데이터베이스**: 1GB ~$0.35
- **합계**: 최소 ~$20-30/월

#### 장점
- 우수한 개발자 경험
- 자동 SSL 및 사용자 정의 도메인
- FastAPI 공식 지원
- 글로벌 에지 네트워크

#### 단점
- **1GB 데이터베이스가 무료 티어 초과** (Neon 0.5GB, Supabase 500MB)
- **무료 티어 300초 지속 시간 제한**
- **공개 베타 WebSocket** (안정성 위험)
- 데이터베이스 비용 1일차부터 발생

#### 팀 협업 기능 (4인 팀)
- ✅ **Team Collaboration**: 팀 멤버 추가 가능
- ✅ **Environment Variables**: 팀원 간 환경변수 공유
- ✅ **Deploy Previews**: 각 PR별 배포 미리보기
- ✅ **Comments**: 배포에 댓글, 토론 가능
- ⚠️ **Pro 플랜 필요**: 4인 팀은 Pro 플랜 필요 ($20/월)
- ✅ **SSO**: SSO 통합 (Enterprise)

---

### 7. Cloudflare

#### 무료 티어 컴퓨팅 (Python Workers)
- **상태**: Python Workers **공개 베타**
- **무료 제한**: 일 10만 요청, 요청당 10ms CPU 시간
- **지속 시간**: 무제한 (HTTP), 15분 (Cron)
- **WebSocket**: 완전 지원
- **메모리**: isolate당 128MB

#### 데이터베이스 (PostgreSQL + PostGIS)
- **D1**: SQLite 기반 (**PostgreSQL 아님**)
- **네이티브 PostgreSQL 호스팅 없음**
- **Hyperdrive**: 외부 PostgreSQL 연결 가속화
  - 일 10만 쿼리 무료
  - Supabase, Neon, Railway, AWS RDS 등 호환

#### 스토리지 및 네트워킹
- **R2 Storage**: 10GB 무료, **송신 비용 제로**
- **사용자 정의 도메인**: 영역당 최대 100개 무제한 무료
- **SSL**: Universal SSL 무료
- **CDN**: 무료 글로벌 CDN

#### 서버리스 제약사항
- **10ms CPU 시간 제한** (무료), 30초-5분 (유료)
- **메모리**: 128MB 제한
- **베타 상태**: Python Workers GA 아님

#### 월 예상 비용
- **Workers Paid**: 최소 월 $5
- **외부 PostgreSQL**: 제공자 따라 $0-25
- **R2 Storage**: $0 (무료 티어가 1GB 백업 커버)
- **합계**: ~$5-30/월

#### 장점
- **송신 비용 제로** (백업에 좋음)
- 글로벌 에지 배포 (330+ 도시)
- 빠른 콜드 스타트 (<5ms)
- Hyperdrive 연결 풀링

#### 단점
- **Python Workers 베타** (안정성 위험)
- **네이티브 PostgreSQL 없음** (외부 필요)
- **무료 티어 10ms CPU 시간 제한**
- **128MB 메모리 제한**
- 아키텍처 변경 필요

#### 팀 협업 기능 (4인 팀)
- ✅ **Access Policies**: 계정/존/Worker별 액세스 제어
- ✅ **Multi-User Accounts**: 여러 사용자 초대 가능
- ✅ **API Tokens**: 팀원별 API 토큰 관리
- ✅ **Audit Logs**: 계정 활동 추적 (Enterprise)
- ⚠️ **제한사항**: 일부 협업 기능은 유료 플랜 필요
- ✅ **Workers Analytics**: 성능 모니터링 공유

---

## 카테고리별 우승자

### 장기 최저비용
| 순위 | 플랫폼 | 월 예상 비용 | 비고 |
|------|----------|------------|------|
| 1 | Cloudflare | $5-30 | Workers $5 + 외부 DB |
| 2 | AWS | $12-50 | Lambda + RDS 마이크로 |
| 3 | Vercel | $20-30 | Pro 플랜 기본 |

### 가장 쉬운 마이그레이션 경로
| 순위 | 플랫폼 | 이유 |
|------|----------|-----|
| 1 | **GCP Cloud Run** | 컨테이너 기반, FastAPI 변경 최소, 60분 제한, WebSocket |
| 2 | **Azure Container Apps** | Cloud Run 유사, 생태계 통합 우수 |
| 3 | AWS Lambda | 어댑터 레이어 필요 (Mangum), 15분 제한 |

### 가장 넉넉한 무료 티어
| 순위 | 플랫폼 | 무료 항목 |
|------|----------|----------|
| 1 | AWS | $200 크레딧 (6개월) + 12개월 무료 티어 |
| 2 | Azure | 12개월 무료 티어 (VM + DB + Storage) |
| 3 | GCP | $300 크레딧 (90일) + 항상 무료 컴퓨팅 |

### 최고 서버리스/에지
| 순위 | 플랫폼 | 이유 |
|------|----------|-----|
| 1 | Cloudflare | 5ms 미만 콜드 스타트, 글로벌 에지 |
| 2 | Vercel | 우수한 DX, 자동 SSL |
| 3 | GCP Cloud Run | 60분 지속 시간, WebSocket |

### 팀 협업 최우수 (4인 팀 기준)
| 순위 | 플랫폼 | 특징 |
|------|----------|------|
| 1 | **AWS** | 세분화된 IAM, Organizations, 비용 공유 |
| 2 | **Azure** | RBAC, Management Groups, Entra ID 통합 |
| 3 | **GCP** | Cloud IAM, Resource Manager, Shared VPC |
| 4 | **Vercel** | Deploy Previews, Comments (Pro 필요) |
| 5 | **Supabase** | RLS, Branching (Pro 필요) |

---

## 상위 3개 추천

### 🥇 1위 추천: Google Cloud Platform (Cloud Run + Cloud SQL)

#### 선정 이유
- PostGIS 지원, 넉넉한 무료 티어, 최소 변경의 **최적 균형**
- Cloud Run은 FastAPI에 **이상적** (컨테이너 기반, 함수만 아님)
- **60분 지속 시간 제한** (서버리스 중 가장 관대함)
- **WebSocket 지원** 포함
- 현대적인 개발자 경험

#### 마이그레이션 경로
1. FastAPI 앱 **컨테이너화** (Dockerfile)
2. Cloud Run에 **배포**
3. PostgreSQL을 Cloud SQL로 **마이그레이션** (직접 마이그레이션 지원)
4. Cloud SQL에서 PostGIS 확장 **활성화**
5. DB 연결용 환경변수 **구성**

#### 비용 분석
| 구성요소 | 무료 티어 | 무료 후 |
|-----------|-----------|------------|
| Cloud Run (컴퓨팅) | 24만 vCPU-초 + 45만 GiB-초 + 200만 요청 | $0-10/월 |
| Cloud SQL (데이터베이스) | 30일 트라이얼만 | ~$25/월 (db-g1-small) |
| Cloud Storage | 5GB | ~$0.17/GB |
| 로드 밸런싱 | 5개 규칙 무료 | $0.025/시간 |
| SSL | 무료 | 무료 |
| **합계** | 무료 (90일) | **~$35-50/월** |

#### 위험/주의사항
- 데이터베이스 **항상 무료 티어 없음** (AWS/Azure 12개월과 다름)
- 90일 트라이얼은 경쟁사보다 짧음
- Cloud SQL은 연결 프록시 또는 사설 IP 필요

#### 트레이드오프
**GCP를 선택하면 얻는 것:**
- ✅ 서버리스상 최고 FastAPI 경험
- ✅ PostGIS 완전 지원
- ✅ 60분 지속 시간 제한
- ✅ WebSocket 지원
- ✅ 현대적, 컨테이너 네이티브 배포

**하지만 포기하는 것:**
- ❌ 영구 무료 데이터베이스 티어
- ❌ 더 긴 트라이얼 기간 (90일 vs 12개월)

#### 팀 협업 (4인 팀 기준)
- ✅ 4인 팀 모두 기본 협업 기능 사용 가능
- ✅ Cloud IAM으로 세분화된 권한 관리
- ✅ 프로젝트 수준에서 팀원 초대, 역할 부여
- ✅ 무료 티어에서도 대부분 협업 기능 지원

---

### 🥈 2위 추천: AWS (Lambda + RDS 또는 App Runner + RDS)

#### 선정 이유
- 데이터베이스 **12개월 무료 티어** (가장 넉넉함)
- RDS의 강력한 PostGIS 지원
- Lambda **항상 무료** (100만 요청 + 40만 GB-초)
- 포괄적인 서비스 포트폴리오
- 광범위한 문서화의 성숙한 플랫폼

#### 마이그레이션 경로
**옵션 A: 서버리스 (Lambda)**
1. FastAPI에 **Mangum 어댑터** 추가
2. **API Gateway**와 함께 Lambda에 배포
3. RDS PostgreSQL로 마이그레이션
4. 환경변수 구성

**옵션 B: 컨테이너 (App Runner)**
1. FastAPI 컨테이너화
2. App Runner에 배포
3. 동일한 데이터베이스 마이그레이션

#### 비용 분석
| 구성요소 | 무료 티어 | 무료 후 |
|-----------|-----------|------------|
| Lambda (컴퓨팅) | 100만 요청 + 40만 GB-초 (항상 무료) | 100만 요청당 $0.20 |
| RDS PostgreSQL | 750시간 + 20GB (12개월) | ~$12/월 (t3.micro) |
| S3 (스토리지) | 5GB (항상 무료) | ~$0.023/GB |
| CloudFront | 1TB (항상 무료) | 이후 무료 |
| Route 53 (DNS) | ❌ 무료 아님 | $0.50/월 |
| ACM (SSL) | 무료 | 무료 |
| **합계** | 무료 (12개월) | **~$12-50/월** |

#### 위험/주의사항
- **Lambda 15분 지속 시간 제한**으로 일부 작업 제약 가능
- Lambda에서 **콜드 스타트** (1-5초)
- Route 53 DNS는 **무료 아님** (GCP/Azure와 다름)
- Lambda WebSocket 지원 제한적 (29초 타임아웃)

#### 트레이드오프
**AWS를 선택하면 얻는 것:**
- ✅ 12개월 무료 데이터베이스 티어 (가장 넉넉함)
- ✅ 항상 무료 Lambda 컴퓨팅
- ✅ 강력한 PostGIS 지원
- ✅ 포괄적인 서비스 생태계
- ✅ 성숙한 플랫폼

**하지만 포기하는 것:**
- ❌ 더 긴 지속 시간 제한 (Lambda 15분 vs GCP 60분)
- ❌ 무료 DNS (Route 53 추가 비용)
- ❌ 단순성 (더 많은 서비스 구성요소)

#### 팀 협업 (4인 팀 기준)
- ✅ AWS Organizations로 계정 통합 관리
- ✅ IAM 역할/정책으로 세분화된 권한
- ✅ 리소스 태깅으로 팀/프로젝트별 비용 추적
- ✅ 4인 팀 모두 기본 협업 기능 사용 가능

---

### 🥉 3위 추천: Azure (Container Apps + PostgreSQL)

#### 선정 이유
- 데이터베이스 + VM **12개월 무료 티어**
- FastAPI에 적합한 **Container Apps**
- **Azure AI Speech 네이티브 통합** (동일 생태계)
- App Service 관리 인증서 **무료**
- Microsoft 중심 팀에 적합

#### 마이그레이션 경로
1. FastAPI 컨테이너화
2. Container Apps에 배포
3. Azure Database for PostgreSQL로 마이그레이션
4. 포털을 통해 PostGIS 활성화

#### 비용 분석
| 구성요소 | 무료 티어 | 무료 후 |
|-----------|-----------|------------|
| Container Apps | 18만 vCPU-초 + 36만 GiB-초 + 200만 요청 | 사용량에 따라 |
| PostgreSQL | 750시간 B1MS + 32GB (12개월) | 티어별 상이 |
| Blob Storage | 5GB (12개월) | ~$0.0208/GB |
| 대역폭 | 항상 무료 100GB | 무료 티어 |
| SSL (SNI) | 무료 (유료 플랜만) | 무료 |
| 사용자 정의 도메인 | $11.99/년 | 동일 |
| **합계** | 무료 (12개월) | **~$30-40/월** |

#### 위험/주의사항
- 무료 티어(F1) **사용자 정의 도메인/SSL 지원 안 함**
- Azure Functions 230초 타임아웃 (매우 제한적)
- 2027년 Azure CDN 중지
- 무료 티어 후 가격 투명성 낮음 (GCP/Azure 비교)

#### 트레이드오프
**Azure를 선택하면 얻는 것:**
- ✅ 12개월 무료 데이터베이스 티어
- ✅ Azure AI Speech 네이티브 통합
- ✅ FastAPI에 적합한 Container Apps
- ✅ 무료 SNI SSL 인증서

**하지만 포기하는 것:**
- ❌ 무료 티어 사용자 정의 도메인 지원
- ❌ 투명한 무료 후 가격
- ❌ Functions의 더 긴 지속 시간 제한

#### 팀 협업 (4인 팀 기준)
- ✅ Azure RBAC로 역할 기반 액세스 제어
- ✅ Management Groups로 구독 조직화
- ✅ Entra ID (Azure AD) SSO, MFA 지원
- ✅ 4인 팀 모두 기본 협업 기능 사용 가능

---

## 최종 추천

### 귀하의 사용 사례 (FastAPI + PostgreSQL/PostGIS, ~1GB DB, Azure AI Speech, SPOF 우려)

**추천: Google Cloud Platform (Cloud Run + Cloud SQL)**

### 근거

| 요소 | GCP | 최고인 이유 |
|--------|-----|----------|
| **PostGIS 지원** | ✅ 네이티브 | Cloud SQL에서 완전 지원 |
| **FastAPI 적합성** | ✅ 우수 | 컨테이너 기반, 함수 제약 없음 |
| **지속 시간 제한** | ✅ 60분 | 서버리스 중 가장 관대함 |
| **WebSocket 지원** | ✅ 예 | 실시간 기능 작동 |
| **무료 티어** | ⚠️ 90일 | 트라이얼 짧지만 항상 무료 컴퓨팅 넉넉함 |
| **마이그레이션 복잡도** | ✅ 낮음 | 컨테이너 네이티브, 최소 코드 변경 |
| **운영 부담** | ✅ 낮음 | 관리형 서비스, 자동 확장 |
| **비용 예측 가능성** | ✅ 높음 | 명확한 사용량付费 정책 |

### 해결되는 것
- ✅ **Mac SPOF 제거** (Cloud Run 다중 AZ, Cloud SQL HA)
- ✅ **PostGIS 지원** (Cloud SQL 네이티브)
- ✅ **Azure AI Speech 작동** (외부 API, 변경 없음)
- ✅ **최소 아키텍처 변경** (FastAPI 컨테이너화, DB 마이그레이션)
- ✅ **합리적인 비용** (무료 티어 후 ~$35-50/월)
- ✅ **4인 팀 협업 지원** (Cloud IAM, Resource Manager)

### 대안: 12개월 무료 티어가 중요하다면

**AWS 선택** 다음 경우:
- 지불 전 가장 긴 런웨이 필요
- 항상 무료 Lambda 컴퓨팅 원함
- 15분 지속 시간 제한 내 작업 가능
- Route 53 DNS 비용 불필요

### 대안: 비용이 최우선

**Cloudflare 선택** 다음 경우:
- 베타 Python Workers로 작업 가능
- 외부 PostgreSQL 괜찮음 (Hyperdrive 통해)
- 최저 기본 비용 원함 (월 $5 Workers)
- 송신 비용 제로 중요 (백업)

---

## 구현 가이드: GCP 마이그레이션

### 1단계: GCP 트라이얼 자격 확인
```bash
# 현재 계정 확인
gcloud config get-value account
# 출력: geondongkim@gmail.com

# 청구 계정 확인 (없으면 트라이얼 자격 있음)
gcloud beta billing accounts list

# 청구가 비활성화된 프로젝트들 확인
# = 아직 청구 계정을 생성하지 않음 = 90일 $300 트라이얼 자격 있음
```

**현재 상태**: `geondongkim@gmail.com` 계정에 청구 계정이 없는 프로젝트들이 있어 90일 $300 트라이얼 자격 있음.

### 2단계: GCP 프로젝트 및 청구 설정
```bash
# 새 프로젝트 생성
gcloud projects create lala-next-prod \
  --name="LALA-next Production"

# 프로젝트에 청구 계정 연결
gcloud billing projects link lala-next-prod \
  --billing-account-id=BILLING_ACCOUNT_ID

# 무료 트라이얼 활성화 (처음 청구 계정 생성 시 자동)
# https://cloud.google.com/free/docs/free-tier-features
```

### 3단계: FastAPI 컨테이너화
```dockerfile
# Dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### 4단계: Cloud Run에 배포
```bash
gcloud run deploy lala-next-api \
  --platform managed \
  --region us-central1 \
  --source . \
  --allow-unauthenticated \
  --project=lala-next-prod
```

### 5단계: PostgreSQL을 Cloud SQL로 마이그레이션
```bash
# Cloud SQL 인스턴스 생성
gcloud sql instances create lala-next-db \
  --database-version POSTGRES_15 \
  --tier db-g1-small \
  --region us-central1 \
  --storage-auto-increase \
  --project=lala-next-prod

# PostGIS 활성화
gcloud sql instances patch lala-next-db \
  --database-flags=postgis=on \
  --project=lala-next-prod

# 데이터베이스 생성 및 사용자 설정
gcloud sql databases create lalanext \
  --instance=lala-next-db \
  --project=lala-next-prod
```

### 6단계: 환경변수 업데이트
```bash
gcloud run services update lala-next-api \
  --update-env-vars DATABASE_URL=postgresql://USER:PASSWORD@/lalanext?host=/cloudsql/lala-next-prod:us-central1:lala-next-db \
  --update-secrets=AZURE_SPEECH_KEY=azure-speech-key \
  --project=lala-next-prod
```

### 7단계: 로드 밸런서 및 SSL 구성
- Cloud Load Balancing 사용 (5개 포워딩 규칙 무료)
- Google 로드 밸런서와 SSL 인증서 포함

### 8단계: 팀원 초대 (4인 팀)
```bash
# 각 팀원에게 IAM 역할 부여
gcloud projects add-iam-policy-binding lala-next-prod \
  --member='user:team-member@example.com' \
  --role='roles/editor' \
  --project=lala-next-prod
```

---

## 요약

| 플랫폼 | 종합 점수 | 추천 대상 |
|----------|--------------|-----------------|
| **GCP** | ⭐⭐⭐⭐⭐ | **FastAPI + PostGIS 전체 최적** |
| **AWS** | ⭐⭐⭐⭐ | 가장 긴 무료 티어 (12개월) |
| **Azure** | ⭐⭐⭐⭐ | Azure AI 생태계 통합 |
| Cloudflare | ⭐⭐⭐ | 최저비용, 베타 상태 |
| Vercel | ⭐⭐⭐ | 최고 DX, 1GB DB 1일차 비용 |
| Supabase | ⭐⭐ | 우수한 PostGIS, FastAPI 재작성 필요 |
| Firebase | ⭐ | 부적합 (PostgreSQL 없음) |

**최종 평결**: PostGIS 지원, FastAPI 호환성, 넉넉한 무료 티어, 최소 마이그레이션 복잡도의 최적 균형을 위해 **Google Cloud Platform** 선택.

---

## 팀 협업 비교 요약 (4인 팀 기준)

| 플랫폼 | 기본 협업 | 무료 티어 협업 | Pro 플랜 필요 | 추천 팀 크기 |
|--------|----------|--------------|--------------|--------------|
| **AWS** | 우수 | ✅ | ❌ | 모든 팀 |
| **GCP** | 우수 | ✅ | ❌ | 모든 팀 |
| **Azure** | 우수 | ✅ | ❌ | 모든 팀 |
| **Supabase** | 우수 | ⚠️ | ✅ ($25/월) | 1-2인 무료, 3인+ Pro |
| **Firebase** | 제한적 | ⚠️ | ❌ | 소규모 팀 |
| **Vercel** | 우수 | ⚠️ | ✅ ($20/월) | 1-2인 무료, 3인+ Pro |
| **Cloudflare** | 양호 | ✅ | ⚠️ | 모든 팀 |

**협업 관련 결론**:
- 빅3 (AWS/GCP/Azure): 4인 팀 기본 기능으로 충분
- Supabase/Vercel: 4인 팀은 Pro 플랜 필요
- Firebase: 백엔드 협업에 제한 있음

---

## 출처

- [AWS Free Tier](https://aws.amazon.com/free/) | [AWS Pricing](https://aws.amazon.com/pricing/)
- [GCP Free Tier](https://cloud.google.com/free/docs/free-tier-features) | [GCP Pricing](https://cloud.google.com/pricing/list)
- [Azure Free Tier](https://azure.microsoft.com/ko-kr/free/) | [Azure Pricing](https://azure.microsoft.com/ko-kr/pricing/)
- [Supabase Pricing](https://supabase.com/pricing) | [PostGIS Guide](https://supabase.com/docs/guides/database/extensions/postgis)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [Vercel Pricing](https://vercel.com/pricing) | [FastAPI Guide](https://vercel.com/docs/frameworks/backend/fastapi)
- [Cloudflare Pricing](https://www.cloudflare.com/plans/) | [Python Workers](https://developers.cloudflare.com/workers/languages/python/)
