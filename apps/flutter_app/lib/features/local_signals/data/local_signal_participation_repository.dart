import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/l10n/lala_copy.dart';
import '../domain/local_signal_public.dart';

class LocalSignalDraftInput {
  const LocalSignalDraftInput({
    required this.kind,
    required this.sourceLanguage,
    required this.title,
    required this.body,
    required this.observationDate,
    required this.commercialDisclosure,
    required this.aggregateOptIn,
    this.placeId,
    this.localityCode,
  });

  final LocalSignalKind kind;
  final String sourceLanguage;
  final String title;
  final String body;
  final String observationDate;
  final LocalSignalCommercialDisclosure commercialDisclosure;
  final bool aggregateOptIn;
  final String? placeId;
  final String? localityCode;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.wireValue,
    'source_language': sourceLanguage,
    'title': title.trim(),
    'body': body.trim(),
    'locality_level': placeId == null ? 'district' : 'place',
    if (localityCode != null && localityCode!.trim().isNotEmpty)
      'locality_code': localityCode!.trim(),
    'commercial_disclosure': commercialDisclosure.wireValue,
    'observation_date': observationDate,
    'aggregate_opt_in': aggregateOptIn,
    if (placeId != null && placeId!.trim().isNotEmpty)
      'place_links': <Map<String, String>>[
        <String, String>{'place_id': placeId!.trim(), 'relation': 'primary'},
      ],
  };
}

class LocalSignalMutationReceipt {
  const LocalSignalMutationReceipt({
    required this.id,
    required this.status,
    required this.moderationState,
    required this.visibility,
    required this.title,
    required this.body,
  });

  final String id;
  final String status;
  final String moderationState;
  final String visibility;
  final String title;
  final String body;

  /// Labels cover exactly the API Literal values; an unknown wire value is
  /// returned as-is so a contract change stays visible instead of rendered as
  /// an invented moderation claim.
  String statusLabel(String language) => switch (status) {
    'draft' => lalaCopyMulti(
      language,
      ko: '비공개 초안',
      en: 'Private draft',
      ja: '非公開の下書き',
      zhHans: '私密草稿',
      zhHant: '私密草稿',
    ),
    'submitted' => lalaCopyMulti(
      language,
      ko: '검수 요청됨',
      en: 'Submitted for review',
      ja: '審査依頼済み',
      zhHans: '已提交审核',
      zhHant: '已提交審核',
    ),
    'published' => lalaCopyMulti(
      language,
      ko: '공개됨',
      en: 'Published',
      ja: '公開済み',
      zhHans: '已公开',
      zhHant: '已公開',
    ),
    'hidden' => lalaCopyMulti(
      language,
      ko: '숨김됨',
      en: 'Hidden',
      ja: '非表示',
      zhHans: '已隐藏',
      zhHant: '已隱藏',
    ),
    'removed' => lalaCopyMulti(
      language,
      ko: '관리자에 의해 내려감',
      en: 'Removed',
      ja: '削除済み',
      zhHans: '已被移除',
      zhHant: '已被移除',
    ),
    'deleted' => lalaCopyMulti(
      language,
      ko: '삭제됨',
      en: 'Deleted',
      ja: '削除済み',
      zhHans: '已删除',
      zhHant: '已刪除',
    ),
    _ => status,
  };

  String moderationStateLabel(String language) => switch (moderationState) {
    'unreviewed' => lalaCopyMulti(
      language,
      ko: '검수 전',
      en: 'Not yet reviewed',
      ja: '未審査',
      zhHans: '尚未审核',
      zhHant: '尚未審核',
    ),
    'pending' => lalaCopyMulti(
      language,
      ko: '검수 중',
      en: 'Under review',
      ja: '審査中',
      zhHans: '审核中',
      zhHant: '審核中',
    ),
    'approved' => lalaCopyMulti(
      language,
      ko: '검수 승인',
      en: 'Review approved',
      ja: '審査承認済み',
      zhHans: '审核通过',
      zhHant: '審核通過',
    ),
    'rejected' => lalaCopyMulti(
      language,
      ko: '검수 반려',
      en: 'Review rejected',
      ja: '審査却下',
      zhHans: '审核未通过',
      zhHant: '審核未通過',
    ),
    _ => moderationState,
  };

  String visibilityLabel(String language) => switch (visibility) {
    'private' => lalaCopyMulti(
      language,
      ko: '비공개',
      en: 'Private',
      ja: '非公開',
      zhHans: '不公开',
      zhHant: '不公開',
    ),
    'pending_review' => lalaCopyMulti(
      language,
      ko: '검수 후 공개 예정',
      en: 'Awaiting review before publication',
      ja: '公開前の審査待ち',
      zhHans: '待审核后公开',
      zhHant: '待審核後公開',
    ),
    'public' => lalaCopyMulti(
      language,
      ko: '공개',
      en: 'Public',
      ja: '公開',
      zhHans: '公开',
      zhHant: '公開',
    ),
    'unlisted' => lalaCopyMulti(
      language,
      ko: '목록 비공개',
      en: 'Unlisted',
      ja: '限定公開',
      zhHans: '不列入列表',
      zhHant: '不列入清單',
    ),
    _ => visibility,
  };

  factory LocalSignalMutationReceipt.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid Local Signal mutation receipt.');
    }
    String requiredText(String key) {
      final raw = value[key];
      if (raw is! String || raw.trim().isEmpty) {
        throw FormatException('Missing Local Signal receipt field: $key');
      }
      return raw.trim();
    }

    return LocalSignalMutationReceipt(
      id: requiredText('id'),
      status: requiredText('status'),
      moderationState: requiredText('moderation_state'),
      visibility: requiredText('visibility'),
      title: requiredText('title'),
      body: requiredText('body'),
    );
  }
}

abstract interface class LocalSignalParticipationRepository {
  Future<LocalSignalPublicItem> getSignal(String signalId, String language);

  Future<LocalSignalCommentFeed> getComments(String signalId, String language);

  Future<LocalSignalMutationReceipt> createDraft(LocalSignalDraftInput input);

  Future<LocalSignalMutationReceipt> updateDraft(
    String signalId,
    LocalSignalDraftInput input,
  );

  Future<LocalSignalMutationReceipt> submitDraft(String signalId);

  Future<void> deleteDraft(String signalId);

  Future<void> setUseful(String signalId, bool active);

  Future<void> setSaved(String signalId, bool active);

  Future<void> addComment(String signalId, String sourceLanguage, String body);

  Future<void> report(String signalId, String reasonCode);

  void close();
}

class LalaLocalSignalParticipationRepository
    implements LocalSignalParticipationRepository {
  LalaLocalSignalParticipationRepository(LalaAppConfig config)
    : _client = LalaApiClient(
        baseUri: Uri.parse(config.baseUri),
        bearerToken: config.bearerToken,
        apiKey: config.apiKey,
        accessTokenProvider: config.accessTokenProvider,
      );

  final LalaApiClient _client;

  @override
  Future<LocalSignalPublicItem> getSignal(
    String signalId,
    String language,
  ) async {
    final response = await _client.getLocalSignal(
      signalId: signalId,
      language: apiRequestLanguage(language),
    );
    final item = LocalSignalPublicItem.fromJson(response.data);
    if (item == null) {
      throw const FormatException('Invalid public Local Signal.');
    }
    return item;
  }

  @override
  Future<LocalSignalCommentFeed> getComments(
    String signalId,
    String language,
  ) async {
    final response = await _client.getLocalSignalComments(
      signalId: signalId,
      language: apiRequestLanguage(language),
    );
    return LocalSignalCommentFeed.fromJson(response.data);
  }

  @override
  Future<LocalSignalMutationReceipt> createDraft(
    LocalSignalDraftInput input,
  ) async {
    final response = await _client.createLocalSignalDraft(
      draft: input.toJson(),
    );
    return LocalSignalMutationReceipt.fromJson(response.data);
  }

  @override
  Future<LocalSignalMutationReceipt> updateDraft(
    String signalId,
    LocalSignalDraftInput input,
  ) async {
    final response = await _client.updateLocalSignalDraft(
      signalId: signalId,
      patch: input.toJson(),
    );
    return LocalSignalMutationReceipt.fromJson(response.data);
  }

  @override
  Future<LocalSignalMutationReceipt> submitDraft(String signalId) async {
    final response = await _client.submitLocalSignalDraft(signalId: signalId);
    return LocalSignalMutationReceipt.fromJson(response.data);
  }

  @override
  Future<void> deleteDraft(String signalId) async {
    await _client.deleteLocalSignalDraft(signalId: signalId);
  }

  @override
  Future<void> setUseful(String signalId, bool active) async {
    await _client.setLocalSignalReaction(
      signalId: signalId,
      reactionType: 'useful',
      active: active,
    );
  }

  @override
  Future<void> setSaved(String signalId, bool active) async {
    await _client.setLocalSignalSaved(signalId: signalId, active: active);
  }

  @override
  Future<void> addComment(
    String signalId,
    String sourceLanguage,
    String body,
  ) async {
    await _client.createLocalSignalComment(
      signalId: signalId,
      sourceLanguage: sourceLanguage,
      body: body,
    );
  }

  @override
  Future<void> report(String signalId, String reasonCode) async {
    await _client.reportLocalSignal(signalId: signalId, reasonCode: reasonCode);
  }

  @override
  void close() => _client.close();
}
