-- LALA-next local-only dev seed/reset SQL.
-- Do not run against shared or production-like databases.

INSERT INTO community.keyword_watchlist (
    keyword,
    region_slug,
    enabled
) VALUES
    ('행궁동 맛집', 'suwon-haenggung', true),
    ('수원화성 산책', 'suwon-haenggung', true),
    ('팔달문 카페', 'suwon-paldalmun', true)
ON CONFLICT (keyword, region_slug) DO UPDATE SET
    enabled = EXCLUDED.enabled;

INSERT INTO community.posts (
    provider,
    external_key,
    keyword,
    region_slug,
    title,
    body,
    post_url,
    created_at_source
) VALUES (
    'local_fixture',
    'local-fixture-suwon-hwaseong-001',
    '수원화성 산책',
    'suwon-haenggung',
    '주말 수원화성 산책 코스 추천',
    '가족과 함께 걷기 좋은 짧은 성곽 코스를 찾는다는 공개 예시 게시글입니다.',
    'https://example.invalid/lala-next/local-fixture/suwon-hwaseong-001',
    TIMESTAMPTZ '2026-06-11 10:00:00+09'
)
ON CONFLICT (external_key) DO UPDATE SET
    provider = EXCLUDED.provider,
    keyword = EXCLUDED.keyword,
    region_slug = EXCLUDED.region_slug,
    title = EXCLUDED.title,
    body = EXCLUDED.body,
    post_url = EXCLUDED.post_url,
    created_at_source = EXCLUDED.created_at_source;

INSERT INTO community.place_mentions_weekly (
    week_start,
    place_name_ko,
    provider,
    category,
    mention_count
) VALUES (
    DATE '2026-06-08',
    '수원화성',
    'local_fixture',
    'attraction',
    12
)
ON CONFLICT (week_start, place_name_ko, provider, category) DO UPDATE SET
    mention_count = EXCLUDED.mention_count,
    updated_at = now();

INSERT INTO ops.dependency_checks (
    dependency_name,
    status,
    latency_ms,
    checked_at
)
SELECT
    'local-fixture-api-readyz',
    'degraded-safe',
    12,
    TIMESTAMPTZ '2026-06-11 12:00:00+09'
WHERE NOT EXISTS (
    SELECT 1
    FROM ops.dependency_checks
    WHERE dependency_name = 'local-fixture-api-readyz'
      AND checked_at = TIMESTAMPTZ '2026-06-11 12:00:00+09'
);
