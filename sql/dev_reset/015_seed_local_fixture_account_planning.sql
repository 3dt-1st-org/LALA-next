-- LALA-next local-only dev seed/reset SQL.
-- Do not run against shared or production-like databases.
-- Synthetic identities below are DB fixtures, not usable Logto accounts.

INSERT INTO identity.users (
    issuer,
    subject,
    status,
    created_at,
    last_seen_at
) VALUES
    (
        'https://local-fixture.invalid',
        'local-fixture-user-a',
        'active',
        TIMESTAMPTZ '2026-09-16 09:00:00+09',
        TIMESTAMPTZ '2026-09-16 09:00:00+09'
    ),
    (
        'https://local-fixture.invalid',
        'local-fixture-user-b',
        'active',
        TIMESTAMPTZ '2026-09-16 09:00:00+09',
        TIMESTAMPTZ '2026-09-16 09:00:00+09'
    )
ON CONFLICT (issuer, subject) DO NOTHING;

INSERT INTO planning.user_saved_places (
    issuer,
    subject,
    place_id,
    source,
    saved_at
) VALUES
    (
        'https://local-fixture.invalid',
        'local-fixture-user-a',
        'local-suwon-hwaseong',
        'local_fixture',
        TIMESTAMPTZ '2026-09-16 09:10:00+09'
    ),
    (
        'https://local-fixture.invalid',
        'local-fixture-user-a',
        'local-missing-place',
        'local_fixture',
        TIMESTAMPTZ '2026-09-16 09:11:00+09'
    )
ON CONFLICT (issuer, subject, place_id) DO UPDATE SET
    source = EXCLUDED.source,
    saved_at = EXCLUDED.saved_at;

INSERT INTO planning.user_plans (
    issuer,
    subject,
    plan_date,
    schema_version,
    envelope,
    created_at,
    updated_at
) VALUES (
    'https://local-fixture.invalid',
    'local-fixture-user-a',
    DATE '2026-09-16',
    1,
    '{
      "language": "ko",
      "region": "수원시",
      "center": {"lat": 37.2830, "lng": 127.0150},
      "slots": [
        {
          "period": "morning",
          "title": "성곽 산책",
          "place": {
            "place_id": "local-suwon-hwaseong",
            "name": "수원화성",
            "category": "attraction",
            "region_ko": "수원시"
          }
        },
        {
          "period": "lunch",
          "title": "지역 음식",
          "place": {
            "place_id": "local-suwon-market-food",
            "name": "수원 통닭거리",
            "category": "restaurant",
            "region_ko": "수원시"
          }
        }
      ]
    }'::jsonb,
    TIMESTAMPTZ '2026-09-16 09:20:00+09',
    TIMESTAMPTZ '2026-09-16 09:20:00+09'
)
ON CONFLICT (issuer, subject, plan_date) DO UPDATE SET
    schema_version = EXCLUDED.schema_version,
    envelope = EXCLUDED.envelope,
    updated_at = EXCLUDED.updated_at;

INSERT INTO profile.user_travel_preferences (
    issuer,
    subject,
    schema_version,
    revision,
    payload,
    created_at,
    updated_at
) VALUES (
    'https://local-fixture.invalid',
    'local-fixture-user-a',
    1,
    1,
    '{
      "version": 1,
      "soft": {"pace": "balanced", "docent_depth": "standard"},
      "hard": {},
      "locale": {"docent_autoplay": false}
    }'::jsonb,
    TIMESTAMPTZ '2026-09-16 09:05:00+09',
    TIMESTAMPTZ '2026-09-16 09:05:00+09'
)
ON CONFLICT (issuer, subject) DO UPDATE SET
    schema_version = EXCLUDED.schema_version,
    revision = EXCLUDED.revision,
    payload = EXCLUDED.payload,
    updated_at = EXCLUDED.updated_at;

INSERT INTO planning.trip_preference_overrides (
    issuer,
    subject,
    plan_date,
    schema_version,
    revision,
    payload,
    created_at,
    updated_at
) VALUES (
    'https://local-fixture.invalid',
    'local-fixture-user-a',
    DATE '2026-09-16',
    1,
    1,
    '{"version": 1, "pace": "relaxed"}'::jsonb,
    TIMESTAMPTZ '2026-09-16 09:15:00+09',
    TIMESTAMPTZ '2026-09-16 09:15:00+09'
)
ON CONFLICT (issuer, subject, plan_date) DO UPDATE SET
    schema_version = EXCLUDED.schema_version,
    revision = EXCLUDED.revision,
    payload = EXCLUDED.payload,
    updated_at = EXCLUDED.updated_at;

INSERT INTO planning.slot_visits (
    issuer,
    subject,
    plan_date,
    slot_period,
    place_id,
    status,
    reason_code,
    use_for_recommendations,
    visited_at,
    confirmed_at,
    created_at,
    updated_at
) VALUES
    (
        'https://local-fixture.invalid',
        'local-fixture-user-a',
        DATE '2026-09-16',
        'morning',
        'local-suwon-hwaseong',
        'visited',
        NULL,
        false,
        TIMESTAMPTZ '2026-09-16 10:30:00+09',
        TIMESTAMPTZ '2026-09-16 10:31:00+09',
        TIMESTAMPTZ '2026-09-16 10:31:00+09',
        TIMESTAMPTZ '2026-09-16 10:31:00+09'
    ),
    (
        'https://local-fixture.invalid',
        'local-fixture-user-a',
        DATE '2026-09-16',
        'lunch',
        'local-suwon-market-food',
        'not_visited',
        'changed_mind',
        true,
        NULL,
        TIMESTAMPTZ '2026-09-16 12:30:00+09',
        TIMESTAMPTZ '2026-09-16 12:30:00+09',
        TIMESTAMPTZ '2026-09-16 12:30:00+09'
    )
ON CONFLICT (issuer, subject, plan_date, slot_period) DO UPDATE SET
    place_id = EXCLUDED.place_id,
    status = EXCLUDED.status,
    reason_code = EXCLUDED.reason_code,
    use_for_recommendations = EXCLUDED.use_for_recommendations,
    visited_at = EXCLUDED.visited_at,
    confirmed_at = EXCLUDED.confirmed_at,
    updated_at = EXCLUDED.updated_at;
