// V1-RC3 detail lane: selected-place PlaceContextCard 의 정직한 날씨 + 소스 바인딩.
// - 일반 경로(showEvidence=false)에서 날씨 요약(독과 동일 SSOT publicWeatherSummary)·
//   날씨 소스·추천 소스 칩이 노출된다(showEvidence 와 무관한 정직 정보).
// - 날씨 null/placeholder/fallback → 날씨·날씨소스 칩이 정직하게 생략(추천 소스는 유지).
// - 추천 source 가 '-'(null/빈) → 추천 소스 칩 생략.
// - 점수/근거 토글은 context 증거(spend/txn)만 추가; 출처 provenance 는 PublicDataProofRow 위임.
//   일반 경로 진실(날씨/소스)은 토글과 무관하게 유지된다(제거되지 않는다).
// - 단일 언어 결과 안에서 KO/EN 이 섞이지 않는다(language 인자로 전체 전환).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/place/widgets/context_fact.dart';
import 'package:lala_next_app/features/place/widgets/place_context_card.dart';

const String _weatherSummary = '보통 · 23°C · PM10 30 보통 · PM2.5 25 좋음';
const String _weatherSource = '기상청 실황';
const String _recSource = '실시간 추천';

LalaPlace _place({LalaPlaceScore? score, String? upstreamSource}) {
  return LalaPlace(
    placeId: 'rc3-detail-p1',
    name: '행궁동 카페',
    nameKo: '행궁동 카페',
    nameEn: 'Haenggung Cafe',
    category: 'restaurant',
    lat: 37.28,
    lng: 127.01,
    address: '경기도 수원시 팔달구',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: 210,
    source: 'db',
    upstreamSource: upstreamSource,
    score: score,
  );
}

LalaPlaceScore _score({double spend = 0, int txn = 0}) {
  return LalaPlaceScore(
    finalScore: 0.8,
    formulaVersion: 'v1',
    components: const LalaPlaceScoreComponents(
      localSpendingScore: null,
      smallMerchantFitScore: null,
      demandDispersionScore: null,
      weatherFitScore: null,
      reviewQualityScore: null,
      cultureRelevanceScore: null,
      accessibilityFitScore: null,
    ),
    dataBasis: 'realtime',
    features: <String, dynamic>{
      'region_spend_amount': spend,
      'region_transaction_count': txn,
    },
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

bool _has(List<ContextFact> facts, IconData icon, String label) =>
    facts.any((f) => f.icon == icon && f.label == label);

bool _hasLabel(List<ContextFact> facts, String contains) =>
    facts.any((f) => f.label.contains(contains));

void main() {
  group('placeContextFacts — normal path (showEvidence=false)', () {
    test('날씨 요약·날씨소스·추천소스 칩이 모두 노출된다', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'ko',
        weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        source: 'db',
        includeEvidence: false,
      );
      expect(_has(facts, Icons.wb_cloudy_outlined, _weatherSummary), isTrue);
      expect(_has(facts, Icons.cloud_outlined, _weatherSource), isTrue);
      expect(_has(facts, Icons.bolt_outlined, _recSource), isTrue);
    });

    test('일반 경로에서 깊은 증거(spend/txn/provenance)는 노출되지 않는다', () {
      final facts = placeContextFacts(
        place: _place(
          score: _score(spend: 12000000, txn: 42),
          upstreamSource: 'tour_api',
        ),
        language: 'ko',
        weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        source: 'db',
        includeEvidence: false,
      );
      expect(_hasLabel(facts, '카드 소비'), isFalse);
      expect(_hasLabel(facts, '거래'), isFalse);
      expect(_hasLabel(facts, '한국관광공사'), isFalse); // provenance(verified) gated
    });
  });

  group('placeContextFacts — null/placeholder/fallback weather omission', () {
    test('날씨 null → 날씨·날씨소스 칩 생략, 추천소스는 유지', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'ko',
        weather: null,
        source: 'db',
        includeEvidence: false,
      );
      expect(_hasLabel(facts, '23°C'), isFalse);
      expect(_has(facts, Icons.cloud_outlined, _weatherSource), isFalse);
      expect(_has(facts, Icons.wb_cloudy_outlined, _weatherSummary), isFalse);
      expect(_has(facts, Icons.bolt_outlined, _recSource), isTrue);
    });

    test('placeholder/fallback 날씨 소스 → gate 통과 못함, 날씨 칩 생략(조작 없음)', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'ko',
        weather: _weather(temp: '23', source: 'fallback'),
        source: 'db',
        includeEvidence: false,
      );
      expect(_hasLabel(facts, '23°C'), isFalse);
      expect(_has(facts, Icons.cloud_outlined, '날씨 준비 중'), isFalse);
      expect(_has(facts, Icons.bolt_outlined, _recSource), isTrue);
    });
  });

  group('placeContextFacts — recommendation source omission', () {
    test('source null → 추천소스 칩 생략(-), 날씨는 source 와 무관하게 유지', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'ko',
        weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        source: null,
        includeEvidence: false,
      );
      expect(_hasLabel(facts, _recSource), isFalse);
      expect(_has(facts, Icons.cloud_outlined, _weatherSource), isTrue);
    });

    test('source 빈 문자열 → 추천소스 칩 생략', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'ko',
        weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        source: '',
        includeEvidence: false,
      );
      expect(_hasLabel(facts, _recSource), isFalse);
    });
  });

  group('placeContextFacts — evidence gating adds, never removes', () {
    final place = _place(
      score: _score(spend: 12000000, txn: 42),
      upstreamSource: 'tour_api',
    );
    final weather = _weather(temp: '23', source: 'kma_ultra_srt_ncst');

    test('showEvidence=false: 깊은 증거 숨김, 일반 경로 진실 노출', () {
      final facts = placeContextFacts(
        place: place,
        language: 'ko',
        weather: weather,
        source: 'db',
        includeEvidence: false,
      );
      expect(_hasLabel(facts, '카드 소비'), isFalse);
      expect(_hasLabel(facts, '거래'), isFalse);
      expect(_hasLabel(facts, '한국관광공사'), isFalse);
      // normal-path truth still present
      expect(_has(facts, Icons.cloud_outlined, _weatherSource), isTrue);
      expect(_has(facts, Icons.bolt_outlined, _recSource), isTrue);
    });

    test(
      'showEvidence=true: context 증거(spend/txn) 추가 + 일반 진실 유지; provenance 는 proof row 위임',
      () {
        final facts = placeContextFacts(
          place: place,
          language: 'ko',
          weather: weather,
          source: 'db',
          includeEvidence: true,
        );
        expect(_hasLabel(facts, '카드 소비'), isTrue);
        expect(_hasLabel(facts, '거래 42건'), isTrue);
        // provenance(externalSourceLabel)은 PublicDataProofRow 에서 단일 렌더 — 카드 중복 없음
        expect(_hasLabel(facts, '한국관광공사'), isFalse);
        // normal-path truth NOT removed by toggling evidence on
        expect(_has(facts, Icons.cloud_outlined, _weatherSource), isTrue);
        expect(_has(facts, Icons.bolt_outlined, _recSource), isTrue);
      },
    );
  });

  group('placeContextFacts — single language (no KO/EN mix)', () {
    test('ko: 모든 라벨이 한국어', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'ko',
        weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        source: 'db',
        includeEvidence: false,
      );
      expect(_has(facts, Icons.bolt_outlined, _recSource), isTrue);
      expect(_has(facts, Icons.cloud_outlined, _weatherSource), isTrue);
      expect(_hasLabel(facts, 'Live recommendations'), isFalse);
      expect(_hasLabel(facts, 'KMA live weather'), isFalse);
    });

    test('en: 모든 라벨이 영어', () {
      final facts = placeContextFacts(
        place: _place(),
        language: 'en',
        weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        source: 'db',
        includeEvidence: false,
      );
      expect(_has(facts, Icons.bolt_outlined, 'Live recommendations'), isTrue);
      expect(_has(facts, Icons.cloud_outlined, 'KMA live weather'), isTrue);
      expect(_hasLabel(facts, 'Normal · 23°C'), isTrue);
      expect(_hasLabel(facts, _recSource), isFalse);
      expect(_hasLabel(facts, _weatherSource), isFalse);
    });
  });

  group('PlaceContextCard widget — selected detail rendering', () {
    testWidgets(
      'normal path renders weather, weather-source, rec-source chips',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PlaceContextCard(
              place: _place(),
              language: 'ko',
              weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
              source: 'db',
              showEvidence: false,
            ),
          ),
        );
        expect(find.text(_weatherSource), findsOneWidget);
        expect(find.text(_recSource), findsOneWidget);
        expect(find.textContaining('23°C'), findsOneWidget);
      },
    );

    testWidgets(
      'weather null omits weather + weather-source chips; rec-source stays',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PlaceContextCard(
              place: _place(),
              language: 'ko',
              weather: null,
              source: 'db',
              showEvidence: false,
            ),
          ),
        );
        expect(find.text(_weatherSource), findsNothing);
        expect(find.textContaining('23°C'), findsNothing);
        expect(find.text(_recSource), findsOneWidget);
      },
    );

    testWidgets('source null omits rec-source chip; weather stays', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PlaceContextCard(
            place: _place(),
            language: 'ko',
            weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
            source: null,
            showEvidence: false,
          ),
        ),
      );
      expect(find.text(_recSource), findsNothing);
      expect(find.text(_weatherSource), findsOneWidget);
    });
  });
}

LalaWeather _weather({
  required String temp,
  required String source,
  String outdoorStatus = 'normal',
  LalaDust? dust,
}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: temp,
    icon: 'partly-cloudy',
    dust: dust ?? _dust(),
    forecast: const <LalaForecastItem>[],
    outdoorStatus: outdoorStatus,
    force: false,
    source: source,
    location: 'Suwon',
    recordTime: '2026-07-24T09:00:00+09:00',
    locationMatch: true,
  );
}

LalaDust _dust({
  String pm10 = '30',
  String pm25 = '25',
  String grade = 'normal',
  String gradeKo = '보통',
  String pm10Grade = 'normal',
  String pm10GradeKo = '보통',
  String pm25Grade = 'good',
  String pm25GradeKo = '좋음',
}) {
  return LalaDust(
    pm10: pm10,
    pm25: pm25,
    grade: grade,
    gradeKo: gradeKo,
    pm10Grade: pm10Grade,
    pm10GradeKo: pm10GradeKo,
    pm25Grade: pm25Grade,
    pm25GradeKo: pm25GradeKo,
  );
}
