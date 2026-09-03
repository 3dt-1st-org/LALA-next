// ONMU P3b: 커뮤니티 화면용 공용 유틸리티.
// - [createCommunityClient]: LalaAppConfig 로부터 LalaApiClient 를 구성. 커뮤니티 엔드포인트는
//   core/backend/lala_backend.dart (불변 보호 대상)를 거치지 않고 직접 호출한다.
// - [formatRelativeTime]: ISO-8601 created_at 문자열을 "~분 전/~시간 전/날짜" 로 표현.
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// 커뮤니티 API 호출용 LalaApiClient 구성. 커뮤니티는 별도 인증 컨텍스트(LalaBackend) 없이
/// 앱 공용 config(bearer/apiKey/accessTokenProvider)를 그대로 주입한다.
LalaApiClient createCommunityClient(LalaAppConfig config) {
  return LalaApiClient(
    baseUri: Uri.parse(config.baseUri),
    bearerToken: config.bearerToken,
    apiKey: config.apiKey,
    accessTokenProvider: config.accessTokenProvider,
  );
}

/// ISO-8601 [iso] 문자열을 상대 시간(ko/en) 으로 변환. 파싱 실패 시 빈 문자열.
String formatRelativeTime(String iso, String language) {
  final created = DateTime.tryParse(iso);
  if (created == null) return '';
  final now = DateTime.now();
  final delta = now.difference(created);
  if (delta.isNegative) {
    return lalaCopy(language, ko: '방금 전', en: 'just now');
  }
  final minutes = delta.inMinutes;
  if (minutes < 1) {
    return lalaCopy(language, ko: '방금 전', en: 'just now');
  }
  if (minutes < 60) {
    return lalaCopy(language, ko: '$minutes분 전', en: '$minutes min ago');
  }
  final hours = delta.inHours;
  if (hours < 24) {
    return lalaCopy(language, ko: '$hours시간 전', en: '$hours hr ago');
  }
  final days = delta.inDays;
  if (days < 7) {
    return lalaCopy(language, ko: '$days일 전', en: '$days d ago');
  }
  final local = created.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// 작성자 화면 표시 라벨. 통신 계약은 내부 사용자 UUID(author_user_id)만 전달하며
/// 그 식별자는 팔로우·신고 같은 동작 대상으로만 쓰이고 화면에는 노출하지 않는다.
/// 아직 프로필 표시명 필드가 계약에 없으므로 실명이 있을 때만 쓰고, 없으면 신원을
/// 추정하지 않는 중립 라벨(현지화 '여행자')을 보여준다.
String authorDisplayLabel(String language, {String? profileDisplayName}) {
  final name = profileDisplayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return lalaCopyMulti(
    language,
    ko: '여행자',
    en: 'Traveler',
    ja: '旅行者',
    zhHans: '旅行者',
    zhHant: '旅行者',
  );
}
