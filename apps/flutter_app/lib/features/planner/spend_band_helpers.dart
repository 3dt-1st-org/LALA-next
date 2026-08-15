// V5-B SPEND (§V5-B D3): offline category-band budget estimate per plan slot.
//
// Real per-place pricing is BLOCKED_EXTERNAL / V7 (contract §3b): V5 ships the
// offline category-band estimate + an honest-unavailable band when no estimate
// exists. No live pricing fetch, no fabricated number.
//
// Bands are coarse, conservative KRW ranges keyed by the slot's place category.
// They are an ESTIMATE, not an authority — every label carries the
// (예산 구간)/(budget band) marker, mirroring the (추정)/(est.) rule on
// estimatedOpeningHours (planner_helpers §12.3). Unknown category / no place →
// honest-unavailable band (never a fabricated number).
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';
import '../place/place_helpers.dart';

/// Estimate marker appended to every SPEND band so it is never read as fact.
String spendBandMarkerLabel(String language) => lalaCopyMulti(
      language,
      ko: '예산 구간',
      en: 'budget band',
      ja: '予算目安',
      zhHans: '预算区间',
      zhHant: '預算區間',
    );

/// Honest-unavailable label rendered as its own band when no estimate exists.
String spendBandUnavailableLabel(String language) => lalaCopyMulti(
      language,
      ko: '예산 구간 미확정',
      en: 'Budget band unavailable',
      ja: '予算目安は未確定',
      zhHans: '预算区间未确定',
      zhHant: '預算區間未確定',
    );

/// A category-band budget estimate for a plan slot (offline, non-authoritative).
class SpendBand {
  const SpendBand({required this.label});

  /// Full display text, e.g. "맛집 · 약 8천~2만5천원 (예산 구간)".
  final String label;
}

/// Returns the category-band estimate for [slot], or null when no offline
/// estimate exists for the slot's category (caller renders the honest-
/// unavailable band). Never fabricates a number for an unknown category.
SpendBand? spendBandFor(LalaPlanSlot slot, String language) {
  final place = slot.place;
  if (place == null) {
    return null;
  }
  final band = _categoryBand(place.category);
  if (band == null) {
    return null;
  }
  final category = categoryLabel(place.category, language: language);
  // Compose the KO/EN label through lalaCopy so every user-facing string flows
  // through the single bilingual seam (contract B7).
  // V6: 확장 로케일은 EN 밴드 문구 + 현지 마커(한국어 노출 금지).
  final isKo = normalizeLalaLanguage(language) == 'ko';
  final bandText = isKo ? band.ko : band.en;
  return SpendBand(
    label: '$category · $bandText (${spendBandMarkerLabel(language)})',
  );
}

/// Offline KRW band per category as a (ko, en) pair. Returns null for unknown
/// categories so the caller renders honest-unavailable (B5).
// Why: conservative coarse ranges derived from category type, not live data —
// intentionally wide and always marked as a band estimate by the caller.
({String ko, String en})? _categoryBand(String category) {
  switch (category) {
    case 'restaurant':
      return (ko: '약 8천~2만5천원', en: 'about ₩8k–25k');
    case 'culture_venue':
      return (ko: '약 3천~1만5천원', en: 'about ₩3k–15k');
    case 'event':
      return (ko: '무료~약 1만원', en: 'free–₩10k');
    case 'attraction':
      return (ko: '약 5천~2만원', en: 'about ₩5k–20k');
    default:
      // Unknown category → no estimate (honest-unavailable, B5).
      return null;
  }
}
