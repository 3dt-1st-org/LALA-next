-- LALA-next local-only dev seed/reset SQL.
-- Do not run against shared or production-like databases.

INSERT INTO travel.places (
    place_id,
    name_ko,
    name_en,
    category,
    address_ko,
    address_en,
    image_url,
    region_name_ko,
    region_name_en,
    lat,
    lng,
    primary_source
) VALUES
    (
        'local-suwon-hwaseong',
        '수원화성',
        'Suwon Hwaseong',
        'attraction',
        '경기도 수원시 팔달구 정조로 825',
        '825 Jeongjo-ro, Paldal-gu, Suwon-si, Gyeonggi-do',
        'http://tong.visitkorea.or.kr/cms/resource/71/3448371_image2_1.jpg',
        '수원시',
        'Suwon',
        37.2879,
        127.0116,
        'local_fixture'
    ),
    (
        'local-suwon-market-food',
        '수원 통닭거리',
        'Suwon Chicken Street',
        'restaurant',
        '경기도 수원시 팔달구 팔달문 인근',
        'Near Paldalmun Gate, Suwon-si, Gyeonggi-do',
        NULL,
        '수원시',
        'Suwon',
        37.2777,
        127.0171,
        'local_fixture'
    ),
    (
        'local-suwon-night-walk',
        '화성행궁 야간 산책',
        'Hwaseong Haenggung Night Walk',
        'event',
        '경기도 수원시 팔달구 행궁동',
        'Haenggung-dong, Paldal-gu, Suwon-si, Gyeonggi-do',
        'http://tong.visitkorea.or.kr/cms/resource/16/3533416_image2_1.jpg',
        '수원시',
        'Suwon',
        37.2819,
        127.0142,
        'local_fixture'
    )
ON CONFLICT (place_id) DO UPDATE SET
    name_ko = EXCLUDED.name_ko,
    name_en = EXCLUDED.name_en,
    category = EXCLUDED.category,
    address_ko = EXCLUDED.address_ko,
    address_en = EXCLUDED.address_en,
    image_url = EXCLUDED.image_url,
    region_name_ko = EXCLUDED.region_name_ko,
    region_name_en = EXCLUDED.region_name_en,
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    primary_source = EXCLUDED.primary_source,
    updated_at = now();
