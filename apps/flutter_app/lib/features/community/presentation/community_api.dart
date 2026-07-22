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
    return lalaCopy(
      language,
      ko: '$minutes분 전',
      en: '$minutes min ago',
    );
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

/// 작성자 식별자를 짧게 축약(UUID 앞 8자리). 화면 표시용.
String shortAuthorLabel(String authorUserId) {
  if (authorUserId.isEmpty) return '';
  if (authorUserId.length <= 8) return authorUserId;
  return authorUserId.substring(0, 8);
}
