# 데이터 복원: 로컬 DB → 프로덕션 RDS (additive upsert)

로컬 개발 DB의 데이터를 프로덕션 RDS로 **안전하게(additive, 무손실)** 복원하는 절차.
SG(보안그룹) 개방 없이 S3 + SSM 경로만 사용. 2026-07-24 POI 복원에 사용한 방법 그대로.

## 전제
- 로컬 Docker DB: `127.0.0.1:55433` (`.env`의 `DB_DSN`). 데이터가 풍부(POI/파이프라인 결과).
- 프로덕션 RDS: **private subnet** (직접 접근 불가). EC2(`i-0a15ffbfa381a5843`) 경유로만.
- EC2 접근: **SSM Session Manager / Run Command** 만 (`team-ec2-access.md` 참조, SSH 폐쇄).
- S3 버킷: `lala-next-backups-292216133883` (EC2 IAM role 이 읽기/쓰기 가능).

## 핵심 설계: additive upsert
- `pg_dump --data-only --column-inserts` (컬럼명 명시 → identity/serial 컬럼 자동 생략, 스키마 호환 안전).
- 각 INSERT에 `ON CONFLICT DO NOTHING` 부착 → 기존 프로덕션 행 보존, 로컬 행만 추가. **무손실 + 멱등(re-runnable)**.
- 변환: `docs/operations` 또는 아래 스크립트(`add_onconflict.py`)로 `;` 앞에 `ON CONFLICT DO NOTHING` 삽입.

## 절차

### 1. 로컬에서 덤프 생성
```bash
set -a; . ./.env; set +a
pg_dump "$DB_DSN" --data-only --column-inserts --rows-per-insert=100 --no-owner \
  --table=travel.places --table=travel.weather_observations --table=travel.place_enrichments \
  --table=culture.events --table=rag.knowledge_chunks \
  --table=community.posts --table=community.place_mentions_weekly \
  --table=economy.franchise_brands --table=ops.job_runs \
  > /tmp/upsert_raw.sql
python3 add_onconflict.py < /tmp/upsert_raw.sql > /tmp/upsert.sql   # ON CONFLICT DO NOTHING 부착
aws s3 cp /tmp/upsert.sql s3://lala-next-backups-292216133883/_restore/upsert.sql
```
> 주의: `economy.card_spending_*` 은 부모 테이블(`source_file`) FK가 있어 같이 복원 안 하면 스킵됨. prod는 systemd 파이프라인이 매일 채우므로 보통 제외.

### 2. SSM Run Command 로 프로덕션 적재
```bash
aws ssm send-command --instance-ids i-0a15ffbfa381a5843 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["aws s3 cp s3://lala-next-backups-292216133883/_restore/upsert.sql /tmp/ && cd /opt/lala-next && DB_DSN=$(grep -E ^DB_DSN= .env|head -1|cut -d= -f2-|tr -d \\\") && psql \"$DB_DSN\" -v ON_ERROR_STOP=0 -q -f /tmp/upsert.sql"]'
```
- **`ON_ERROR_STOP=0` 필수**: `--rows-per-insert=100` 다중행 INSERT 내에 같은 unique-key 중복이 있으면 `ON CONFLICT`가 못 잡아서 그 배치가 에러나는데, 0이면 스킵하고 계속 진행. (1이면 첫 에러에서 중단 → 후행 테이블 미적재.)
- 명령 결과 조회: `aws ssm get-command-invocation --command-id <id> --instance-id i-0a15ffbfa381a5843 --query 'StandardOutputContent' --output text`

### 3. 검증
```bash
# API (기기 위치 근처)
curl -s "https://api.lala-next.cloud/api/v1/places?lat=37.032&lng=127.025&radius_m=3000&limit=5"
# 프로덕션 카운트 (SSM)
psql ... -c "SELECT count(*) FROM travel.places;"
```

### 4. 정리 (중요)
```bash
aws s3 rm s3://lala-next-backups-292216133883/_restore/ --recursive   # 덤프에 실데이터 포함
rm -f /tmp/upsert*.sql
```

## 교훈 (2026-07-24)
- 프로덕션 places가 "없어진" 게 아니라 **희소**했던 것 (81행, 기기 위치 오산엔 0건). 복원 전 스키마/카운트/위치분포를 먼저 확인할 것.
- API 파라미터 확인: `radius_m` (기본 1000=1km). `radius` 아님.
