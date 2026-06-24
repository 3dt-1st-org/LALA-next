# Card Spending Source Inventory

Last updated: 2026-06-24 KST

This document tracks free public card-spending datasets that could extend
LALA's current Gyeonggi-only spending coverage.

The key question is not only whether a province publishes a card-related
dataset. The key question is whether that dataset can be mapped into
`economy.card_spending_area_monthly` and `economy.card_spending_demographics`
without inventing missing values.

## Classification

- `drop-in`: current ingest can parse the file shape directly, or only needs a
  region code map file.
- `small-adapter`: a lightweight province-specific transformer should be enough.
- `operationally-unsuitable`: the data is too old, too derived, too narrow, or
  does not preserve the monthly regional semantics that LALA score generation
  expects.

## Current Ingest Fit

The current file ingest already accepts CSV, XLSX, and ZIP sources and can map
many aliases for:

- `month` or `date`
- `region_name_ko` or `region_code`
- `industry_code`
- `industry_name_ko`
- `gender`
- `age_group`
- `spend_amount`
- `transaction_count`

See [card_spending_ingest.py](/Users/geondongkim/LALA-next/apps/api/app/services/card_spending_ingest.py:242)
and [run_card_spending_file_ingest.py](/Users/geondongkim/LALA-next/apps/api/app/tools/run_card_spending_file_ingest.py:29).

Important constraint:

- `industry_code` is optional in `economy.card_spending_area_monthly`, so a
  province-level or district-level monthly spending file can still be useful
  even if it does not include industry detail.
- A source that only provides daily averages, ratios, growth rates, or index
  values is not a clean drop-in unless the provider also exposes the raw monthly
  amount used to compute those derived values.

## Confirmed Sources

| Region | Dataset | URL | Update / Time range | Fit | Why |
|---|---|---|---|---|---|
| Gyeonggi | `경기도_카드 소비 데이터` | [data.go.kr/15128475](https://www.data.go.kr/data/15128475/fileData.do) | auto-updated; detailed daily rows | `drop-in` | Already proven in shared-dev. Has region codes, industry codes, amount, count, gender, age. |
| Gyeonggi | `경기도_데이터분석 카드매출 시군구 성연령별 집계` | [data.go.kr/15151646](https://www.data.go.kr/data/15151646/fileData.do) | updated 2025-11-26 page snapshot; aggregate monthly rows | `drop-in` | Already proven in shared-dev. Good area-month baseline and demographics split. |
| Seoul | `서울특별시_상권분석서비스(추정매출)` | [data.go.kr/15147229](https://www.data.go.kr/data/15147229/fileData.do) | updated 2025-09-04; quarterly or analysis-oriented sales view | `small-adapter` | Free and current enough, but not the same schema as current Gyeonggi files. Needs column mapping and likely explicit documentation for spatial unit semantics. |
| Seoul | `서울시 상권분석서비스(소비-행정동)` | [data.seoul.go.kr/OA-22166](https://data.seoul.go.kr/dataList/OA-22166/S/1/datasetView.do) | quarterly refresh note on page | `small-adapter` | Administrative-dong consumption looks promising for area-level scoring, but must confirm downloadable raw columns and whether monthly amount semantics are stable enough for ingestion. |
| Busan | `부산광역시_일별 행정동 업종 소비매출 월별 일평균` | [data.go.kr/15147853](https://www.data.go.kr/data/15147853/fileData.do?recommendDataYn=Y) | annual update; page updated 2026-04-15 | `small-adapter` | Strong region and industry detail, but the public value is a monthly daily-average metric rather than a direct monthly total. We need a province-specific rule before using it for `spend_amount`. |
| Sejong | `세종특별자치시_카드매출_행정동별 카드소비 현황` | [data.go.kr/15145312](https://www.data.go.kr/data/15145312/fileData.do?recommendDataYn=Y) | annual; covers 2025 monthly rows on page | `small-adapter` | Very plausible area-month source. Region-level monthly amount exists, but industry detail is absent and column names differ from current parser aliases. |
| Sejong | `세종특별자치시_카드매출_업종별 카드소비 현황` | [data.go.kr/15145309](https://www.data.go.kr/data/15145309/fileData.do?recommendDataYn=Y) | annual | `operationally-unsuitable` | Useful context, but it appears citywide by industry rather than region-by-industry, so it cannot directly ground `region_name_ko` scoring rows. |
| Sejong | `세종특별자치시_카드매출_시간대별 카드소비 현황` | [data.go.kr/15145317](https://www.data.go.kr/data/15145317/fileData.do?recommendDataYn=Y) | annual | `operationally-unsuitable` | Time-slice composition data is useful for analysis, but not a direct replacement for monthly regional spending totals. |
| Daejeon | `대전광역시_자치구별 신용카드(KB국민카드) 매출액` | [data.go.kr/15064213](https://www.data.go.kr/data/15064213/fileData.do) | one-off; mainly 2019-03 to 2020-07 | `operationally-unsuitable` | Free and structured, but too old for production scoring refreshes. Could only be used for historical experiments. |
| Jeju | `제주특별자치도_주제3_상권분석을 위한 유동인구에 따른 카드 매출액 변화 데이터 활용_매쉬업결과` | [data.go.kr/15074768](https://www.data.go.kr/data/15074768/fileData.do) | one-off analysis result | `operationally-unsuitable` | Mashup/result dataset, not a durable monthly operational feed for ingestion. |
| Incheon | `인천광역시_금융통계데이터 조회서비스` | [data.go.kr/15108981](https://www.data.go.kr/data/15108981/openapi.do?recommendDataYn=Y) | 2020-01 to 2022-06 | `operationally-unsuitable` | Monthly card consumption exists, but the semantics are resident-based financial statistics by `거주지/성별/연령/소득구분`, not a clear spend-location area feed for `region_name_ko` scoring. It is also stale and masked for small cells. |
| Daegu | `D-데이터허브 보유 데이터셋 현황` | [data.daegu.go.kr/open/bigData/dataSetStatus.do](https://data.daegu.go.kr/open/bigData/dataSetStatus.do) | Shinhan 2021-01 to 2024-10, KB 2020-01 to 2021-07, Hyundai 2017-01 to 2022-08 | `operationally-unsuitable` | Daegu clearly has card datasets in the city big-data platform, but I have not yet confirmed a stable public raw-download URL. Today this is a platform lead, not a drop-in operational feed. |
| Ulsan | `울산 빅데이터 활용 플랫폼 카드소비` | [data.ulsan.go.kr/bigdata](https://data.ulsan.go.kr/bigdata/) | current portal view | `operationally-unsuitable` | The portal exposes `카드소비` analysis and lists `카드 데이터(민간)`, but I have not confirmed a public raw monthly file/API that can be automated safely. |
| Gangwon | `강원특별자치도 춘천시_상권 매출현황` | [data.go.kr/15153903](https://www.data.go.kr/data/15153903/fileData.do) | one-off; 2023 data, page updated 2025-11-26 | `operationally-unsuitable` | 읍면동/업종 granularity is promising, but public values are clipped into amount ranges rather than raw spend amounts. The page itself says raw monthly amounts require a separate request. |
| Chungbuk | `충청북도 빅데이터 허브 시각화 갤러리` | [data.chungbuk.go.kr 카드 소비 데이터 분석](https://data.chungbuk.go.kr/portal/bbs/multibbsPstListView.do?ctCode=CT91077037&mbCode=MBS00000006&sitemapCode=SM00000147) | current portal view | `operationally-unsuitable` | The province publicly shows `카드 소비 데이터 분석`, but I have not yet confirmed an openly downloadable raw area-month dataset behind that view. |
| Chungnam | `충남 월별 카드 소비 현황(BC카드자료기준)` | [alldam.chungnam.go.kr 카드소비](https://alldam.chungnam.go.kr/bigdata/collect/list.chungnam?dataGubun=PRV&dataGubun2=CARD&isOpen=Y&menuCd=DOM_000000201002001000&contentsSid=870) | monthly, city/county | `operationally-unsuitable` | The shape looks close to what we want and includes monthly amount and count by 시군, but the public page says commercial use and redistribution are prohibited. That makes it a poor production source even if the columns are workable. |
| Gyeongnam | `2024년 경상남도 지역별 월별 카드매출현황` | [bigdata.gyeongnam.go.kr monthly](https://bigdata.gyeongnam.go.kr/bigdata/collect/view.gn?apiIdx=619&cds=OC0016&menuCd=DOM_000000112002000000&pageIndex=1&searchKeyword=&st=) | yearly refresh; updated 2025-04-09 | `small-adapter` | This is one of the best current non-Gyeonggi leads: the public title already matches region-by-month card sales semantics and the page exposes a download action. We still need a sample file and column check before calling it drop-in. |
| Gyeongnam | `2024년 경상남도 지역별 성연령별 카드매출현황` | [bigdata.gyeongnam.go.kr demographics](https://bigdata.gyeongnam.go.kr/bigdata/collect/view.gn?apiIdx=615&cds=&menuCd=DOM_000000112002000000&pageIndex=10&searchKeyword=&st=) | yearly refresh; updated 2025-04-09 | `small-adapter` | Promising companion dataset for `economy.card_spending_demographics`. Again, we need a sample file before marking it drop-in. |

## Remaining Provinces Still Needing Exact Raw URLs

These provinces may still have useful sources, but I have not yet pinned a
source-faithful raw spending dataset URL that is clearly suitable for
automation.

| Region | Exact dataset URL | Expected shape | Fit | Notes |
|---|---|---|---|---|
| Gwangju | pending | unknown | pending | The city big-data platform exists, but I have not yet found a public raw card-sales dataset page comparable to Seoul/Gyeonggi/Sejong. |
| Jeonbuk | pending | unknown | pending | The Jeonbuk big-data hub is live, but a public card-spending dataset page still needs to be identified. |
| Jeonnam | pending | unknown | pending | Still need an exact dataset page and freshness check. |
| Gyeongbuk | pending | unknown | pending | I found only report-style card-consumption briefs so far, not a reusable raw feed. |

## Practical Attachability Today

If the question is "what can we attach next without inventing data," the
current answer is:

1. `drop-in` now: Gyeonggi only.
2. `small-adapter` next: Seoul, Sejong, Gyeongnam.
3. `decision needed`: Busan, because the public metric is a monthly daily
   average rather than a direct monthly total.
4. `research only for now`: Incheon, Daegu, Ulsan, Gangwon, Chungbuk,
   Chungnam, Daejeon, Jeju, plus still-unconfirmed Gwangju, Jeonbuk, Jeonnam,
   Gyeongbuk.

## Recommended Rollout Order

1. Seoul: highest value after Gyeonggi, likely reachable with a small adapter.
2. Sejong: administrative-dong monthly amount file looks simple enough for an
   area-only first pass.
3. Gyeongnam: both monthly and demographic card-sales pages are now confirmed
   and look structurally close to the target tables.
4. Busan: useful but needs a decision on whether daily-average metrics may be
   converted into LALA's monthly amount semantics.
5. The rest: keep as research-only unless fresher and less restricted sources
   are found.

## Next Steps

1. Download one sample each from Seoul, Sejong, and Gyeongnam, then map their
   actual columns against `card_spending_ingest.py`.
2. Decide whether Busan daily-average metrics are acceptable for a separate
   derived-source lane, or whether they should stay excluded from
   `local_spending_score`.
3. Keep searching exact raw URLs for Gwangju, Jeonbuk, Jeonnam, and Gyeongbuk.
4. Keep `local_spending_score` null for provinces whose free public sources are
   too derived, too stale, license-restricted, or not openly automatable.
