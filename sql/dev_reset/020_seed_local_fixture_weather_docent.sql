-- LALA-next local-only dev seed/reset SQL.
-- Do not run against shared or production-like databases.

INSERT INTO travel.weather_observations (
    location_name,
    temperature_c,
    precipitation_type,
    pm10,
    pm25,
    is_rain_snow,
    is_bad_dust,
    is_heatwave,
    is_coldwave,
    is_strong_wind,
    observed_at
)
SELECT
    '수원시',
    23.0,
    'none',
    34.0,
    18.0,
    false,
    false,
    false,
    false,
    false,
    TIMESTAMPTZ '2026-06-11 12:00:00+09'
WHERE NOT EXISTS (
    SELECT 1
    FROM travel.weather_observations
    WHERE location_name = '수원시'
      AND observed_at = TIMESTAMPTZ '2026-06-11 12:00:00+09'
);

INSERT INTO travel.docent_scripts (
    place_id,
    category,
    language,
    mode,
    script,
    source_method,
    generated_at,
    expires_at
) VALUES (
    'local-suwon-hwaseong',
    'attraction',
    'ko',
    'brief',
    '수원화성은 조선 정조의 도시 비전과 축성 기술을 함께 보여주는 대표적인 역사 관광지입니다. 성곽을 따라 걸으며 팔달문, 장안문, 화서문을 연결해 보는 짧은 동선을 추천합니다.',
    'local_fixture',
    TIMESTAMPTZ '2026-06-11 12:00:00+09',
    TIMESTAMPTZ '2026-06-18 12:00:00+09'
)
ON CONFLICT (place_id, category, language, mode) DO UPDATE SET
    script = EXCLUDED.script,
    source_method = EXCLUDED.source_method,
    generated_at = EXCLUDED.generated_at,
    expires_at = EXCLUDED.expires_at;
