# AWS 배포 런북 (LALA-next)
**최종 업데이트**: 2026-07-07
**상태**: 운영 중 (DB-backed, 12개월 무료 티어)

> 단일 Mac 온프레미스 SPOF를 해소하기 위해 AWS EC2 + RDS PostgreSQL로 마이그레이션.

---

## 1. 아키텍처

```
[인터넷]
   ↓ HTTPS (443)
[Cloudflare 프록시 (오렌지 구름, SSL Full strict, DDoS 방어)]
   ↓ HTTPS (443) — Let's Encrypt 인증서 종료
[Nginx (리버스 프록시 + SSL 종료, HTTP→HTTPS 리다이렉트)]
   ↓ 포트 8000
[EC2 t3.micro: uvicorn FastAPI (workers=2)]
   ↓ 포트 5432 (프라이빗 서브넷)
[RDS PostgreSQL 15.18 + PostGIS 3.4 + pgcrypto + vector]
```

**외부 엔드포인트**: `https://api.lala-next.cloud` (Cloudflare 프록시 + EC2 Let's Encrypt)
**직접 IP**: `http://54.160.16.183/` (Elastic IP, 디버깅용)

---

## 2. 핵심 리소스 ID

| 리소스 | ID / 값 |
|--------|---------|
| AWS 계정 | `292216133883` (신규, $200 크레딧 6개월 + 12개월 무료티어) |
| 리전 | `us-east-1` (버지니아 북부) |
| VPC | `vpc-08905332b2ce7c4b7` |
| EC2 인스턴스 | `i-0a15ffbfa381a5843` |
| EC2 퍼블릭 IP | `54.160.16.183` (Elastic IP, 고정) |
| Elastic IP | `eipalloc-06027fd44aa12394d` |
| RDS 인스턴스 | `lala-next-db` |
| RDS 엔드포인트 | `lala-next-db.cojm284ouqxi.us-east-1.rds.amazonaws.com:5432` |
| RDS 데이터베이스 | `lalanext` (user `lalaadmin`) |
| 보안그룹 (EC2) | `sg-07b44009e6593a54b` |
| 보안그룹 (RDS) | `sg-02db54e4b9b95e81b` |
| DB 파라미터 그룹 | `lala-next-postgres-params` (rds.allowed_extensions: postgis,pgcrypto,vector) |
| SSH 키 | `~/.ssh/lala-next-key.pem` (user `ec2-user`) |
| Cloudflare Zone | `eee348ff140b1ed22e51bfe591bed110` (`lala-next.cloud`) |
| Cloudflare SSL 모드 | Full (strict) |
| 도메인 | `api.lala-next.cloud` → A `54.160.16.183` (Proxied) |
| SSL 인증서 | Let's Encrypt (EC2 `/etc/letsencrypt/live/api.lala-next.cloud/`, 자동 갱신) |
| Secrets Manager | `lala-next/rds-master-password` (RDS 마스터 비밀번호) |
| S3 백업 버킷 | `lala-next-backups-292216133883` (버저닝 + 30일 Glacier) |

---

## 3. 비용 (12개월 무료 티어)

| 항목 | 월 비용 | 비고 |
|------|---------|------|
| EC2 t3.micro | **무료** | 750시간/월 = 24/7 실행 가능 |
| RDS PostgreSQL db.t3.micro | **무료** | 750시간/월 + 20GB 스토리지 |
| Elastic IP | **무료** | 실행 중 인스턴스에 연결 시 |
| 데이터 전송 (인바운드) | **무료** | |
| 데이터 전송 (아웃바운드) | ~$0-2 | 월 100GB까지 무료, 초과 시 $0.09/GB |
| **합계** | **~$0-2/월** | $200 크레딧으로 12개월+ 커버 |

---

## 4. 접근 방법

### SSH 접속
```bash
ssh -i ~/.ssh/lala-next-key.pem ec2-user@54.160.16.183
```

### 헬스체크
```bash
# /healthz (프로세스 생존)
curl https://api.lala-next.cloud/healthz

# /readyz (DB-backed 상태)
curl https://api.lala-next.cloud/readyz | python3 -m json.tool

# 정상 상태: overall=db-backed, db=configured, postgis=configured
```

### API 문서
```
https://api.lala-next.cloud/docs
```

> 디버깅 시 Cloudflare 프록시를 우회하려면 직접 IP 사용: `curl -H "Host: api.lala-next.cloud" http://54.160.16.183/healthz`

---

## 5. 운영 명령어

### 서비스 제어 (EC2 내부)
```bash
# FastAPI 상태
sudo systemctl status lala-next

# 재시작
sudo systemctl restart lala-next

# 로그 확인
sudo journalctl -u lala-next -f

# Nginx 상태/재시작
sudo systemctl status nginx
sudo systemctl restart nginx
```

### DB 접속 (EC2 통해)
```bash
# RDS는 프라이뱃 서브넷 → EC2에서만 접근 가능
PGPASSWORD='LalaNext2024!' psql -h lala-next-db.cojm284ouqxi.us-east-1.rds.amazonaws.com -U lalaadmin -d lalanext
```

### 코드 업데이트 (EC2 내부)
```bash
cd /opt/lala-next
git pull
# 의존성 변경 시:
source .venv/bin/activate && pip install -e .
sudo systemctl restart lala-next
```

### 스키마 변경 (EC2 통해 RDS)
```bash
# 비밀번호는 Secrets Manager에서 조회 (런북에 평문 금지)
RDS_PW=$(aws secretsmanager get-secret-value \
  --secret-id lala-next/rds-master-password \
  --query SecretString --output text | python3 -c "import sys,json;print(json.loads(sys.stdin.read())['password'])")

# canonical 스키마 재적용 (순서대로)
cd /opt/lala-next
for f in $(ls -1 sql/canonical/*.sql | sort); do
  PGPASSWORD="$RDS_PW" psql -h lala-next-db.cojm284ouqxi.us-east-1.rds.amazonaws.com -U lalaadmin -d lalanext -f "$f"
done
```

---

## 6. 구성 파일 위치 (EC2)

| 파일 | 경로 | 용도 |
|------|------|------|
| 앱 코드 | `/opt/lala-next/` | git clone (main 브랜치) |
| 가상환경 | `/opt/lala-next/.venv/` | Python 3.11 + 의존성 |
| 환경변수 | `/opt/lala-next/.env` | DB_DSN, LALA_PUBLIC_CONTEST_ACCESS 등 |
| systemd 서비스 | `/etc/systemd/system/lala-next.service` | uvicorn workers=2 |
| Nginx 설정 | `/etc/nginx/conf.d/lala-next.conf` | SSL 종료 + 443→8000 프록시 + HTTP 리다이렉트 |
| SSL 인증서 | `/etc/letsencrypt/live/api.lala-next.cloud/` | Let's Encrypt, certbot-renew.timer가 매일 갱신 체크 |
| 백업 스크립트 | `/opt/lala-next/scripts/backup_to_s3.sh` | RDS→S3, lala-next-backup.timer 매일 03:17 |
| 액세스 로그 | `/var/log/lala-next/access.log` | |

---

## 7. 보안 주의사항

⚠️ **현재 비밀번호(`LalaNext2024!`)는 초기 설정용** — 운영 전환 전에 다음을 권장:
1. RDS 마스터 비밀번호 변경 (`aws rds modify-db-instance --master-user-password ...`)
2. AWS Secrets Manager로 비밀번호 이관
3. EC2 보안그룹 SSH 규칙을 특정 IP로 제한 (현재 단일 IP로 제한됨)

⚠️ **CORS 현재 `*` (모두 허용)** — 운영 전환 전에 도메인 지정으로 변경.

---

## 8. 완료된 운영 기능 / 남은 작업

### ✅ 완료됨
- [x] **SSL/TLS**: Cloudflare 프록시 + Let's Encrypt 인증서 (Full strict, 자동 갱신 02:30 UTC)
- [x] **도메인**: `https://api.lala-next.cloud` (Cloudflare DNS, 오렌지 구름)
- [x] **백업 자동화**: RDS→S3 매일 03:17 (systemd timer) + 버저닝 + Glacier 수명주기
- [x] **모니터링**: CloudWatch 알람 5종 (EC2 CPU/상태, RDS CPU/연결수/스토리지) + SNS 이메일
- [x] **비밀번호 강화**: RDS 마스터 비밀번호 → AWS Secrets Manager 이관

### ⏳ 남은 작업
- [ ] **data_freshness 정상화**: 날씨 관측 데이터 갱신 (`PUBLIC_DATA_SERVICE_KEY` 설정 후 갱신 스크립트 실행)
- [ ] **CORS 도메인 제한**: 운영 전환 시 `*` → `https://*.lala-next.cloud` 등으로 한정
- [ ] **CloudWatch 로그 스트리밍**: 애플리케이션 로그 → CloudWatch Logs (현재는 EC2 로컬)

---

## 9. 장애 대응 플레이북

### 증상: /healthz 응답 없음
1. EC2 상태 확인: `aws ec2 describe-instances --instance-ids i-0a15ffbfa381a5843`
2. SSH 접속 후: `sudo systemctl status lala-next`
3. `failed` 시: `sudo systemctl restart lala-next`
4. 로그 확인: `sudo journalctl -u lala-next -n 50`

### 증상: /readyz = degraded, db=degraded
1. RDS 상태 확인: `aws rds describe-db-instances --db-instance-identifier lala-next-db`
2. `available`이면 EC2에서 DB 연결 테스트 (psql)
3. 연결 실패 시 보안그룹 규칙 확인 (EC2 SG → RDS SG 5432)
4. FastAPI 재시작 (커넥션 풀 회복)

### 증상: EC2 재부팅 후 서비스 다운
- systemd가 자동 시작하므로 보통 자동 복구됨
- 수동 확인: `sudo systemctl status lala-next nginx`

---

## 10. 관련 문서

- [클라우드 호스팅 비교 보고서](cloud-hosting-comparison-2026-07-06.md) — 7개 플랫폼 비교 + 4인 팀 협업 분석
- [온프레미스 마이그레이션 개요](onprem-migration-overview.md) — 이전 단일 Mac 운영 맥락
