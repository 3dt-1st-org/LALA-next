import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

// B1.3b PoC: 생성(dart-dio) 클라이언트가 실제 /api/v1/places 응답(서울 샘플)을 역직렬화해
// 타입/직렬화 파이프라인(patch_dart_dio_serializers 적용)이 끝까지 동작함을 검증한다.
const String _placesJson = r'''
{"ok": true, "data": {"count": 2, "places": [{"place_id": "tour-api-2785797", "name": "겨울, 청계천의 빛", "name_ko": "겨울, 청계천의 빛", "name_en": null, "category": "event", "lat": 37.5691317067, "lng": 126.9776154729, "address": "서울특별시 중구 태평로1가 1", "image_url": "https://tong.visitkorea.or.kr/cms/resource/36/3567636_image2_1.jpg", "region_ko": "중구", "region_en": null, "event_start_date": null, "event_end_date": null, "event_url": null, "is_ongoing": null, "is_approximate_location": false, "distance_m": 294, "source": "db", "upstream_source": "tour_api", "score": null}, {"place_id": "tour-api-130629", "name": "백악미술관", "name_ko": "백악미술관", "name_en": null, "category": "culture_venue", "lat": 37.5736924051, "lng": 126.9841536365, "address": "서울특별시 종로구 인사동9길 16 (관훈동)", "image_url": "https://tong.visitkorea.or.kr/cms/resource/95/3590795_image2_1.jpg", "region_ko": "종로구", "region_en": null, "event_start_date": null, "event_end_date": null, "event_url": null, "is_ongoing": null, "is_approximate_location": false, "distance_m": 966, "source": "db", "upstream_source": "tour_api", "score": null}], "query": {"lat": 37.5665, "lng": 126.978, "radius_m": 2000, "category": "all", "language": "ko", "include_scores": false, "limit": 60}, "source": "db", "location_engine": "postgis"}, "meta": {"request_id": "0ac04c33-bd0f-4be5-93fc-fed888aa066b", "source": "db"}, "error": null}
''';

void main() {
  test('generated client deserializes a real /api/v1/places response', () {
    final decoded = jsonDecode(_placesJson);
    final envelope = standardSerializers.deserializeWith(
      PlacesSuccessEnvelope.serializer,
      decoded,
    ) as PlacesSuccessEnvelope;

    expect(envelope.ok, isTrue);
    expect(envelope.data, isNotNull);
    expect(envelope.data.places.length, 2);
    expect(envelope.data.places.first.name, '겨울, 청계천의 빛');
    expect(envelope.data.places.first.category.name, 'event');
    expect(envelope.error, isNull);
  });
}
