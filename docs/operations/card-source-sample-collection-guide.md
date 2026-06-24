# Regional Card Source Sample Collection Guide

Last updated: 2026-06-24 KST

이 문서는 LALA의 비경기권 카드매출 확장을 위해 사용자가 직접 준비해야 하는
샘플 파일과 계정/신청 절차를 실습형으로 정리한 가이드다.

원칙:

- 지금 단계에서 필요한 것은 `운영 반입용 전체 수집`이 아니라 `샘플 파일 확보`다.
- 우선순위는 `서울 -> 세종 -> 경남`이다.
- raw 파일은 git에 넣지 말고 `artifacts/tmp/raw/...` 아래에 둔다.
- 카드매출이 없는 지역은 계속 `local_spending_score = null`을 유지한다.

## 준비물

시작 전에 준비할 것:

1. `data.go.kr` 로그인 가능한 계정
2. 경남 빅데이터 플랫폼 로그인 가능한 계정
3. 로컬 저장 경로

권장 저장 경로:

- `artifacts/tmp/raw/seoul-card/`
- `artifacts/tmp/raw/sejong-card/`
- `artifacts/tmp/raw/gyeongnam-card/`

## 목표 결과

이번 가이드의 완료 기준은 아래 3가지를 확보하는 것이다.

1. 서울 샘플 파일 1개
2. 세종 샘플 파일 1개
3. 경남 샘플 파일 1개 이상

확보 후에는 Codex에게 `파일 경로`만 전달하면 된다.

예시:

```text
artifacts/tmp/raw/seoul-card/서울특별시_상권분석서비스_추정매출.csv
artifacts/tmp/raw/sejong-card/세종특별자치시_카드매출_행정동별_카드소비_현황.csv
artifacts/tmp/raw/gyeongnam-card/2024년_경상남도_지역별_월별_카드매출현황.xlsx
```

## 1. 서울 샘플 파일 받기

대상 소스:

- [서울특별시_상권분석서비스(추정매출)](https://www.data.go.kr/data/15147229/fileData.do)

이 소스가 필요한 이유:

- 현재 확인된 서울 무료 소스 중 운영 확장 가치가 가장 높다.
- 바로 `drop-in`은 아니지만 `small-adapter` 후보로 가장 유력하다.

실습 순서:

1. 링크를 연다.
2. `data.go.kr` 로그인이 필요하면 로그인한다.
3. 페이지에서 `다운로드`, `바로가기`, 또는 파일 제공 버튼을 찾는다.
4. 파일 1개만 내려받는다.
5. 파일명을 유지한 채 `artifacts/tmp/raw/seoul-card/` 아래에 둔다.

완료 체크:

- 파일이 실제로 열리는지 확인한다.
- CSV/XLSX/ZIP 중 어떤 형식인지 확인한다.
- Codex에게 파일 경로를 전달한다.

추가 후보:

- [서울시 상권분석서비스(소비-행정동)](https://data.seoul.go.kr/dataList/OA-22166/S/1/datasetView.do)

주의:

- 이 서울 열린데이터광장 소스는 파일이 아니라 Open API 중심일 수 있다.
- 지금은 위 `추정매출` 파일이 먼저다.

## 2. 세종 샘플 파일 받기

대상 소스:

- [세종특별자치시_카드매출_행정동별 카드소비 현황](https://www.data.go.kr/data/15145312/fileData.do?recommendDataYn=Y)

이 소스가 필요한 이유:

- 행정동별 월 단위 소비 데이터라서 area-month ingest 후보로 좋다.
- 업종 정보가 없어도 `economy.card_spending_area_monthly`에는 먼저 연결할 수 있다.

실습 순서:

1. 링크를 연다.
2. `data.go.kr` 로그인이 필요하면 로그인한다.
3. `다운로드` 또는 `바로가기`로 파일을 받는다.
4. 파일을 `artifacts/tmp/raw/sejong-card/` 아래에 둔다.

완료 체크:

- 컬럼에 `연월`, `행정동`, `사용금액` 계열 값이 들어있는지 확인한다.
- Codex에게 파일 경로를 전달한다.

지금은 받지 않아도 되는 세종 소스:

- [업종별 카드소비 현황](https://www.data.go.kr/data/15145309/fileData.do?recommendDataYn=Y)
- [시간대별 카드소비 현황](https://www.data.go.kr/data/15145317/fileData.do?recommendDataYn=Y)

이유:

- 현재 1차 ingest 목표는 `지역 월합계` 또는 이에 가까운 구조다.
- 업종별 citywide, 시간대별 구성 데이터는 우선순위가 낮다.

## 3. 경남 샘플 파일 받기

대상 소스:

- [2024년 경상남도 지역별 월별 카드매출현황](https://bigdata.gyeongnam.go.kr/bigdata/collect/view.gn?apiIdx=619&cds=OC0016&menuCd=DOM_000000112002000000&pageIndex=1&searchKeyword=&st=)
- 가능하면 같이:
  [2024년 경상남도 지역별 성연령별 카드매출현황](https://bigdata.gyeongnam.go.kr/bigdata/collect/view.gn?apiIdx=615&cds=&menuCd=DOM_000000112002000000&pageIndex=10&searchKeyword=&st=)

이 소스가 필요한 이유:

- 현재 확인된 비경기권 후보 중 구조가 가장 좋은 편이다.
- area-month와 demographics 둘 다 이어질 가능성이 있다.

실습 순서:

1. 경남 빅데이터 플랫폼에 로그인한다.
2. 월별 카드매출현황 페이지를 연다.
3. `다운로드` 버튼으로 월별 파일 1개를 받는다.
4. 가능하면 성연령별 파일도 1개 받는다.
5. 파일을 `artifacts/tmp/raw/gyeongnam-card/` 아래에 둔다.

완료 체크:

- 최소 1개는 지역별 월별 카드매출 파일이어야 한다.
- 가능하면 demographics 파일도 같이 둔다.
- Codex에게 파일 경로를 전달한다.

## 4. 계정과 신청이 필요한 경우

### data.go.kr

용도:

- 서울, 세종 등 파일데이터 다운로드
- 일부 Open API 활용신청

가이드:

- [공공데이터 이용가이드](https://www.data.go.kr/ugs/selectPublicDataUseGuideView.do)

실무 기준:

- `파일 다운로드`만 되면 이번 단계는 충분하다.
- Open API 키 신청은 지금 당장 필수는 아니다.

### 서울 열린데이터광장

용도:

- 서울 Open API 기반 접근이 필요할 때

가이드:

- [인증키 신청](https://data.seoul.go.kr/together/mypage/actkeyMain.do)
- [Open API 이용방법](https://data.seoul.go.kr/together/guide/useGuide.do)

실무 기준:

- 현재는 파일 샘플 검증이 우선이다.
- API 키는 2차 어댑터 단계에서 필요할 수 있다.

### 경남 빅데이터 플랫폼

용도:

- 경남 카드매출 데이터 다운로드

가이드:

- [경남 빅데이터 플랫폼](https://bigdata.gyeongnam.go.kr/index.gn?menuCd=DOM_000000109001000000)
- [오픈 API 활용 신청 안내](https://bigdata.gyeongnam.go.kr/index.gn?menuCd=DOM_000000114001003000)

실무 기준:

- 이번 단계는 로그인 후 파일 다운로드가 우선이다.
- Open API 신청은 샘플 구조가 맞는지 확인한 뒤로 미뤄도 된다.

## 5. 부산과 충남은 왜 지금 보류인가

### 부산

현재 판단:

- 보류

이유:

- 공개 지표가 `월합계`가 아니라 `월별 일평균` 중심이다.
- `spend_amount`로 바로 넣기에는 의미 왜곡 위험이 있다.

### 충남

현재 판단:

- 운영용 기본 경로에서는 보류

이유:

- 구조는 좋아 보이지만 라이선스 문구 확인이 더 필요하다.
- 공모전 내부 참고는 가능해도 1차 ingest 표준 소스로 먼저 채택하지 않는다.

## 6. 사용자에게 남은 실제 액션

정말 필요한 사용자 액션만 남기면 아래와 같다.

1. 서울 샘플 파일 1개 다운로드
2. 세종 샘플 파일 1개 다운로드
3. 경남 샘플 파일 1개 이상 다운로드
4. 각 파일을 권장 경로에 저장
5. Codex에게 파일 경로 전달

## 7. 파일 전달 후 Codex가 이어서 할 일

파일 경로를 받으면 Codex가 바로 이어서 할 일:

1. 실제 컬럼 구조 확인
2. 현재 `card_spending_ingest.py` alias와 매핑 비교
3. `drop-in` 또는 `small-adapter` 재판정
4. 필요하면 지역별 어댑터 초안 구현
5. 적용 전 preview와 문서 반영
