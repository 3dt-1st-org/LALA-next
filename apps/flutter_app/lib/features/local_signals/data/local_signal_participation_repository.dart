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
