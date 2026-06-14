-- LALA-next local-only dev seed/reset SQL.
-- Do not run against shared or production-like databases.

INSERT INTO economy.card_spending_area_monthly (
    month,
    region_name_ko,
    industry_code,
    industry_name_ko,
    spend_amount,
    transaction_count,
    visitor_type,
    primary_source
)
SELECT
    seed.month,
    seed.region_name_ko,
    seed.industry_code,
    seed.industry_name_ko,
    seed.spend_amount,
    seed.transaction_count,
    seed.visitor_type,
    seed.primary_source
FROM (
    VALUES
        (DATE '2026-05-01', '수원시', 'I561', '음식점업', 9800000.00, 1280, 'domestic', 'dev_seed'),
        (DATE '2026-05-01', '수원시', 'R902', '문화서비스', 4200000.00, 420, 'domestic', 'dev_seed'),
        (DATE '2026-05-01', '여주시', 'R902', '문화서비스', 2700000.00, 210, 'domestic', 'dev_seed')
) AS seed(
    month,
    region_name_ko,
    industry_code,
    industry_name_ko,
    spend_amount,
    transaction_count,
    visitor_type,
    primary_source
)
WHERE NOT EXISTS (
    SELECT 1
    FROM economy.card_spending_area_monthly existing
    WHERE existing.month = seed.month
      AND existing.region_name_ko = seed.region_name_ko
      AND existing.industry_code = seed.industry_code
      AND existing.visitor_type = seed.visitor_type
      AND existing.primary_source = seed.primary_source
);

INSERT INTO economy.card_spending_demographics (
    month,
    region_name_ko,
    industry_code,
    gender,
    age_group,
    spend_amount,
    transaction_count,
    primary_source
)
SELECT
    seed.month,
    seed.region_name_ko,
    seed.industry_code,
    seed.gender,
    seed.age_group,
    seed.spend_amount,
    seed.transaction_count,
    seed.primary_source
FROM (
    VALUES
        (DATE '2026-05-01', '수원시', 'I561', 'all', '20-39', 3200000.00, 460, 'dev_seed'),
        (DATE '2026-05-01', '수원시', 'R902', 'all', '40-59', 2300000.00, 220, 'dev_seed'),
        (DATE '2026-05-01', '여주시', 'R902', 'all', '40-59', 1600000.00, 150, 'dev_seed')
) AS seed(
    month,
    region_name_ko,
    industry_code,
    gender,
    age_group,
    spend_amount,
    transaction_count,
    primary_source
)
WHERE NOT EXISTS (
    SELECT 1
    FROM economy.card_spending_demographics existing
    WHERE existing.month = seed.month
      AND existing.region_name_ko = seed.region_name_ko
      AND existing.industry_code = seed.industry_code
      AND existing.gender = seed.gender
      AND existing.age_group = seed.age_group
      AND existing.primary_source = seed.primary_source
);

INSERT INTO culture.events (
    event_id,
    title_ko,
    title_en,
    event_type,
    venue_name_ko,
    venue_place_id,
    region_name_ko,
    starts_on,
    ends_on,
    url,
    primary_source,
    source_record_id
) VALUES
    (
        'dev-seed-suwon-night-walk-2026',
        '화성행궁 야간 산책',
        'Hwaseong Haenggung Night Walk',
        'walking_program',
        '화성행궁',
        'demo-suwon-night-walk',
        '수원시',
        DATE '2026-06-01',
        DATE '2026-08-31',
        'https://example.invalid/lala-next/dev-seed/suwon-night-walk-2026',
        'dev_seed',
        'dev-seed-suwon-night-walk-2026'
    ),
    (
        'dev-seed-suwon-fortress-culture-2026',
        '수원화성 문화 해설',
        'Suwon Hwaseong Culture Walk',
        'docent_program',
        '수원화성',
        'demo-suwon-hwaseong',
        '수원시',
        DATE '2026-06-01',
        DATE '2026-12-31',
        'https://example.invalid/lala-next/dev-seed/suwon-fortress-culture-2026',
        'dev_seed',
        'dev-seed-suwon-fortress-culture-2026'
    )
ON CONFLICT (event_id) DO UPDATE SET
    title_ko = EXCLUDED.title_ko,
    title_en = EXCLUDED.title_en,
    event_type = EXCLUDED.event_type,
    venue_name_ko = EXCLUDED.venue_name_ko,
    venue_place_id = EXCLUDED.venue_place_id,
    region_name_ko = EXCLUDED.region_name_ko,
    starts_on = EXCLUDED.starts_on,
    ends_on = EXCLUDED.ends_on,
    url = EXCLUDED.url,
    primary_source = EXCLUDED.primary_source,
    source_record_id = EXCLUDED.source_record_id,
    updated_at = now();

INSERT INTO travel.place_events (
    place_id,
    title,
    starts_at,
    ends_at,
    url
)
SELECT
    seed.place_id,
    seed.title,
    seed.starts_at,
    seed.ends_at,
    seed.url
FROM (
    VALUES
        (
            'demo-suwon-hwaseong',
            '수원화성 문화 해설',
            TIMESTAMPTZ '2026-06-01 10:00:00+09',
            TIMESTAMPTZ '2026-12-31 18:00:00+09',
            'https://example.invalid/lala-next/dev-seed/suwon-fortress-culture-2026'
        ),
        (
            'demo-suwon-night-walk',
            '화성행궁 야간 산책',
            TIMESTAMPTZ '2026-06-01 19:00:00+09',
            TIMESTAMPTZ '2026-08-31 22:00:00+09',
            'https://example.invalid/lala-next/dev-seed/suwon-night-walk-2026'
        )
) AS seed(place_id, title, starts_at, ends_at, url)
WHERE NOT EXISTS (
    SELECT 1
    FROM travel.place_events existing
    WHERE existing.place_id = seed.place_id
      AND existing.title = seed.title
      AND existing.starts_at = seed.starts_at
);
