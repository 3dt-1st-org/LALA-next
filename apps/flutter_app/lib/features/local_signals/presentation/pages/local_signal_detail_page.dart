import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/lala_visual_tokens.dart';
import '../../../../auth/auth_controller.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/navigation/local_signal_action.dart';
import '../../../../shared/l10n/lala_copy.dart';
import '../../data/local_signal_participation_repository.dart';
import '../../domain/local_signal_aggregate.dart';
import '../../domain/local_signal_public.dart';
import '../local_signal_auth_gate.dart';
import '../widgets/local_signal_contribution_composer.dart';

class LocalSignalDetailArguments {
  const LocalSignalDetailArguments.public(this.signal)
    : aggregate = null,
      aggregateEnvelope = null,
      contribution = false,
      contributePlace = null,
      contributeRegion = null;

  const LocalSignalDetailArguments.aggregate(
    this.aggregate,
    this.aggregateEnvelope,
  ) : signal = null,
      contribution = false,
      contributePlace = null,
      contributeRegion = null;

  /// S-31 feed-level contribution entry: no signal or aggregate context, an
  /// optional manual coarse region (never precise coordinates).
  const LocalSignalDetailArguments.contribute({
    LocalSignalPlaceContributionContext? place,
    LocalSignalRegionContributionContext? region,
  }) : signal = null,
       aggregate = null,
       aggregateEnvelope = null,
       contribution = true,
       contributePlace = place,
       contributeRegion = region;

  final LocalSignalPublicItem? signal;
  final LocalSignalPlaceAggregate? aggregate;
  final LocalSignalAggregates? aggregateEnvelope;
  final bool contribution;
  final LocalSignalPlaceContributionContext? contributePlace;
  final LocalSignalRegionContributionContext? contributeRegion;
}

/// S-32: governed Local Signal detail and authenticated participation.
class LocalSignalDetailPage extends StatefulWidget {
  const LocalSignalDetailPage({
    required this.signalId,
    required this.language,
    required this.initialConfig,
    this.arguments,
    this.authController,
    this.onPlaceAction,
    this.repository,
    super.key,
  });

  final String signalId;
  final String language;
  final LalaAppConfig initialConfig;
  final LocalSignalDetailArguments? arguments;
  final LalaAuthController? authController;
  final ValueChanged<LocalSignalPlaceActionRequest>? onPlaceAction;
  final LocalSignalParticipationRepository? repository;

  @override
  State<LocalSignalDetailPage> createState() => _LocalSignalDetailPageState();
}

class _LocalSignalDetailPageState extends State<LocalSignalDetailPage> {
  late final LocalSignalParticipationRepository _repository;
  late final bool _ownsRepository;
  LocalSignalPublicItem? _signal;
  LocalSignalCommentFeed? _comments;
  bool _loading = false;
  bool _commentsLoading = false;
  // Why: a failed comment read must not render as "no public comments" —
  // empty and failed are different truths.
  bool _commentsFailed = false;
  bool _actionBusy = false;
  bool _useful = false;
  bool _saved = false;
  String? _safeError;
  final TextEditingController _commentController = TextEditingController();

  // Contribution mode guard state mirrored from the embedded composer so the
  // page-owned AppBar back button runs the same unsaved-input confirmation as
  // the composer's close action and system back.
  bool _contributionDirty = false;
  bool _contributionBusy = false;

  LocalSignalPlaceAggregate? get _aggregate => widget.arguments?.aggregate;

  bool get _isContribution => widget.arguments?.contribution ?? false;

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository =
        widget.repository ??
        LalaLocalSignalParticipationRepository(widget.initialConfig);
    _signal = widget.arguments?.signal;
    if (_isContribution) {
      // Contribution mode shows the auth gate / composer immediately; there is
      // no signal to load or comment feed to read.
      return;
    }
    if (_signal == null && _aggregate == null) {
      unawaited(_loadSignal());
    } else if (_signal != null) {
      unawaited(_loadComments());
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    if (_ownsRepository) _repository.close();
    super.dispose();
  }

  Future<void> _loadSignal() async {
    setState(() {
      _loading = true;
      _safeError = null;
    });
    try {
      final signal = await _repository.getSignal(
        widget.signalId,
        widget.language,
      );
      if (!mounted) return;
      setState(() => _signal = signal);
      await _loadComments();
    } on Object {
      if (!mounted) return;
      setState(
        () => _safeError = _copy(
          widget.language,
          ko: '이 로컬 신호를 불러오지 못했어요.',
          en: 'This Local Signal could not be loaded.',
          ja: 'このローカル信号を読み込めませんでした。',
          zhHans: '无法加载此本地信号。',
          zhHant: '無法載入此在地訊號。',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadComments() async {
    final signal = _signal;
    if (signal == null) return;
    setState(() {
      _commentsLoading = true;
      _commentsFailed = false;
    });
    try {
      final comments = await _repository.getComments(
        signal.id,
        widget.language,
      );
      if (mounted) setState(() => _comments = comments);
    } on Object {
      // Comments are secondary. Keep the verified signal body visible, but
      // surface the failure instead of an honest-looking empty list.
      if (mounted) setState(() => _commentsFailed = true);
    } finally {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  bool get _authenticated => widget.authController?.state.authenticated == true;

  Future<bool> _ensureAuthenticated() async {
    if (_authenticated) return true;
    final controller = widget.authController;
    if (controller == null || !controller.config.enabled) {
      _showMessage(
        _copy(
          widget.language,
          ko: '이 빌드에서는 계정 연결을 사용할 수 없어요.',
          en: 'Account linking is unavailable in this build.',
          ja: 'このビルドではアカウント連携を利用できません。',
          zhHans: '此版本无法使用账号连接。',
          zhHant: '此版本無法使用帳號連結。',
        ),
      );
      return false;
    }
    await controller.signIn();
    if (!mounted) return false;
    if (!controller.state.authenticated) {
      _showMessage(
        _copy(
          widget.language,
          ko: '로그인을 완료한 뒤 다시 시도해 주세요.',
          en: 'Complete sign-in, then try again.',
          ja: 'ログイン完了後にもう一度お試しください。',
          zhHans: '请完成登录后重试。',
          zhHant: '請完成登入後重試。',
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _toggleUseful() async {
    if (_actionBusy || !await _ensureAuthenticated()) return;
    final signal = _signal;
    if (signal == null) return;
    final next = !_useful;
    await _runAction(
      () => _repository.setUseful(signal.id, next),
      onSuccess: () => _useful = next,
    );
  }

  Future<void> _toggleSaved() async {
    if (_actionBusy || !await _ensureAuthenticated()) return;
    final signal = _signal;
    if (signal == null) return;
    final next = !_saved;
    await _runAction(
      () => _repository.setSaved(signal.id, next),
      onSuccess: () => _saved = next,
    );
  }

  Future<void> _addComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _actionBusy || !await _ensureAuthenticated()) return;
    final signal = _signal;
    if (signal == null) return;
    await _runAction(
      () => _repository.addComment(
        signal.id,
        _apiLanguage(widget.language),
        body,
      ),
      onSuccess: () => _commentController.clear(),
    );
    await _loadComments();
  }

  Future<void> _report() async {
    if (_actionBusy || !await _ensureAuthenticated()) return;
    final signal = _signal;
    if (signal == null || !mounted) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => _ReportSheet(language: widget.language),
    );
    if (reason == null || !mounted) return;
    await _runAction(
      () => _repository.report(signal.id, reason),
      successMessage: _copy(
        widget.language,
        ko: '신고를 접수했어요.',
        en: 'Your report was received.',
        ja: '報告を受け付けました。',
        zhHans: '举报已提交。',
        zhHant: '檢舉已提交。',
      ),
    );
  }

  Future<void> _shareExperience() async {
    final outcome = await requestLocalSignalAuthentication(
      context,
      controller: widget.authController,
      language: widget.language,
      actionLabel: _copy(
        widget.language,
        ko: '경험 공유',
        en: 'sharing a Local Signal',
        ja: '体験の共有',
        zhHans: '分享体验',
        zhHant: '分享體驗',
      ),
    );
    if (!mounted || outcome != LocalSignalAuthOutcome.alreadyAuthenticated) {
      return;
    }
    final placeId = _linkedPlaceId;
    final placeContext = placeId == null
        ? null
        : (placeId: placeId, placeName: _aggregate?.placeNameKo);
    final localityCode = _signal?.localityCode;
    final regionContext = placeContext == null && localityCode != null
        ? (code: localityCode, label: localityCode)
        : null;
    final submitted = await showLocalSignalContributionSheet(
      context,
      language: widget.language,
      repository: _repository,
      placeContext: placeContext,
      regionContext: regionContext,
    );
    if (submitted == true && mounted) {
      _showMessage(
        _copy(
          widget.language,
          ko: '검수 요청을 보냈어요. 공개 전까지 원문은 비공개로 유지됩니다.',
          en: 'Submitted for review. Your draft stays private until approval.',
          ja: '審査を依頼しました。承認までは非公開です。',
          zhHans: '已提交审核，获批前草稿保持私密。',
          zhHant: '已提交審核，核准前草稿維持私密。',
        ),
      );
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    VoidCallback? onSuccess,
    String? successMessage,
  }) async {
    setState(() => _actionBusy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => onSuccess?.call());
      if (successMessage != null) _showMessage(successMessage);
    } on Object {
      if (mounted) {
        _showMessage(
          _copy(
            widget.language,
            ko: '요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
            en: 'The request could not be completed. Please try again.',
            ja: 'リクエストを完了できませんでした。もう一度お試しください。',
            zhHans: '请求未完成，请稍后重试。',
            zhHant: '請求未完成，請稍後再試。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _dispatchPlace(LocalSignalPlaceAction action) {
    final placeId = _linkedPlaceId;
    if (placeId == null || widget.onPlaceAction == null) return;
    widget.onPlaceAction!(
      LocalSignalPlaceActionRequest(placeId: placeId, action: action),
    );
  }

  String? get _linkedPlaceId {
    final links = _signal?.placeLinks;
    if (links != null && links.isNotEmpty) return links.first.placeId;
    return _aggregate?.placeId;
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authController;
    Widget page() => Scaffold(
      key: const ValueKey('local-signal-detail-page'),
      backgroundColor: LalaVisualColors.surface,
      appBar: AppBar(
        backgroundColor: LalaVisualColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const ValueKey('local-signal-detail-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _isContribution ? _closeContribution : () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(
          _isContribution
              ? _copy(
                  widget.language,
                  ko: '내 경험 보내기',
                  en: 'Share your experience',
                  ja: '体験を投稿',
                  zhHans: '分享体验',
                  zhHant: '分享體驗',
                )
              : _copy(
                  widget.language,
                  ko: '로컬 신호 상세',
                  en: 'Local Signal detail',
                  ja: 'ローカル信号の詳細',
                  zhHans: '本地信号详情',
                  zhHant: '在地訊號詳情',
                ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
    if (auth == null) return page();
    return AnimatedBuilder(animation: auth, builder: (context, _) => page());
  }

  /// AppBar back in contribution mode routes through the composer's
  /// unsaved-input guard so the arrow cannot silently discard a draft.
  Future<void> _closeContribution() async {
    if (_contributionBusy) return;
    if (_contributionDirty && mounted) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('local-signal-composer-discard-confirm'),
          title: Text(
            _copy(
              widget.language,
              ko: '작성 중인 내용이 있어요',
              en: 'You have unsaved text',
              ja: '入力中の内容があります',
              zhHans: '还有未保存的内容',
              zhHant: '還有未儲存的內容',
            ),
          ),
          content: Text(
            _copy(
              widget.language,
              ko: '지금 닫으면 저장하지 않은 내용은 사라져요.',
              en: 'If you close now, unsaved text will be lost.',
              ja: '今閉じると、保存していない内容は失われます。',
              zhHans: '现在关闭将丢失未保存的内容。',
              zhHant: '現在關閉將遺失未儲存的內容。',
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const ValueKey('local-signal-composer-keep-editing'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                _copy(
                  widget.language,
                  ko: '계속 작성',
                  en: 'Keep editing',
                  ja: '編集を続ける',
                  zhHans: '继续编辑',
                  zhHant: '繼續編輯',
                ),
              ),
            ),
            FilledButton(
              key: const ValueKey('local-signal-composer-discard'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                _copy(
                  widget.language,
                  ko: '닫기',
                  en: 'Discard and close',
                  ja: '閉じる',
                  zhHans: '关闭',
                  zhHant: '關閉',
                ),
              ),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    context.pop();
  }

  Widget _buildContributionBody() {
    final arguments = widget.arguments;
    if (!_authenticated) {
      // Guests get a real sign-in path (or an honest "unavailable in this
      // build") before any draft field appears — authentication is never
      // simulated.
      return LocalSignalAuthenticationView(
        language: widget.language,
        controller: widget.authController,
        onAuthenticated: () {
          if (mounted) setState(() {});
        },
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LocalSignalContributionComposer(
              language: widget.language,
              repository: _repository,
              placeContext: arguments?.contributePlace,
              regionContext: arguments?.contributeRegion,
              onClose: (_) => context.pop(),
              onInputStateChanged: (dirty, busy) {
                if (mounted &&
                    (dirty != _contributionDirty ||
                        busy != _contributionBusy)) {
                  setState(() {
                    _contributionDirty = dirty;
                    _contributionBusy = busy;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            _PrivacyBoundary(language: widget.language, aggregate: false),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isContribution) return _buildContributionBody();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_safeError != null) {
      return _LoadError(
        language: widget.language,
        message: _safeError!,
        onRetry: _loadSignal,
      );
    }
    final signal = _signal;
    final aggregate = _aggregate;
    if (signal == null && aggregate == null) {
      return _LoadError(
        language: widget.language,
        message: _copy(
          widget.language,
          ko: '표시할 로컬 신호가 없어요.',
          en: 'There is no Local Signal to display.',
          ja: '表示できるローカル信号がありません。',
          zhHans: '没有可显示的本地信号。',
          zhHant: '沒有可顯示的在地訊號。',
        ),
      );
    }
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: <Widget>[
          if (signal != null)
            _PublicSignalBody(signal: signal, language: widget.language)
          else
            _AggregateBody(
              aggregate: aggregate!,
              envelope: widget.arguments?.aggregateEnvelope,
              language: widget.language,
            ),
          const SizedBox(height: 16),
          _PrivacyBoundary(
            language: widget.language,
            aggregate: aggregate != null,
          ),
          const SizedBox(height: 16),
          _PlaceActions(
            language: widget.language,
            enabled:
                (_signal?.placeLinks.isNotEmpty == true ||
                    _aggregate?.placeId != null) &&
                widget.onPlaceAction != null,
            onViewPlace: () => _dispatchPlace(LocalSignalPlaceAction.viewPlace),
            onOpenPlan: () => _dispatchPlace(LocalSignalPlaceAction.addToPlan),
          ),
          const SizedBox(height: 16),
          if (signal != null) ...<Widget>[
            _ParticipationActions(
              language: widget.language,
              authenticated: _authenticated,
              useful: _useful,
              saved: _saved,
              busy: _actionBusy,
              reactionCount: signal.reactionCount + (_useful ? 1 : 0),
              onUseful: _toggleUseful,
              onSaved: _toggleSaved,
              onReport: _report,
            ),
            const SizedBox(height: 16),
            _CommentsSection(
              language: widget.language,
              authenticated: _authenticated,
              loading: _commentsLoading,
              failed: _commentsFailed,
              comments: _comments?.items ?? const <LocalSignalPublicComment>[],
              controller: _commentController,
              busy: _actionBusy,
              onSubmit: _addComment,
              onRetry: _loadComments,
            ),
            const SizedBox(height: 16),
          ],
          LocalSignalContributionEntry(
            language: widget.language,
            authenticated: _authenticated,
            onPressed: _shareExperience,
          ),
        ],
      ),
    );
  }
}

class _PublicSignalBody extends StatelessWidget {
  const _PublicSignalBody({required this.signal, required this.language});

  final LocalSignalPublicItem signal;
  final String language;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            Chip(label: Text(signal.kind.label(language))),
            Chip(
              avatar: const Icon(Icons.people_outline, size: 16),
              label: Text(
                _copy(
                  language,
                  ko: '사용자 공개 경험',
                  en: 'Public user experience',
                  ja: '公開ユーザー体験',
                  zhHans: '公开用户体验',
                  zhHant: '公開使用者體驗',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          signal.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(signal.body, style: const TextStyle(fontSize: 16, height: 1.55)),
        const SizedBox(height: 14),
        _MetadataLine(
          icon: Icons.calendar_today_outlined,
          text: _dateLabel(
            signal.observationDate ?? signal.publishedAt,
            language,
          ),
        ),
        if (signal.localityCode != null) ...<Widget>[
          const SizedBox(height: 7),
          _MetadataLine(
            icon: Icons.location_on_outlined,
            text: signal.localityCode!,
          ),
        ],
        if (signal.commercialDisclosure !=
            LocalSignalCommercialDisclosure.none) ...<Widget>[
          const SizedBox(height: 7),
          _MetadataLine(
            icon: Icons.campaign_outlined,
            text: signal.commercialDisclosure.label(language),
          ),
        ],
      ],
    ),
  );
}

class _AggregateBody extends StatelessWidget {
  const _AggregateBody({
    required this.aggregate,
    required this.envelope,
    required this.language,
  });

  final LocalSignalPlaceAggregate aggregate;
  final LocalSignalAggregates? envelope;
  final String language;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Chip(
          avatar: const Icon(Icons.insights_outlined, size: 16),
          label: Text(
            _copy(
              language,
              ko: '시스템 집계',
              en: 'System aggregate',
              ja: 'システム集計',
              zhHans: '系统汇总',
              zhHant: '系統彙總',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          aggregate.placeNameKo,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          aggregate.providerLabel(language),
          style: const TextStyle(
            color: LalaVisualColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _MetricRow(
          label: _copy(
            language,
            ko: '전체 언급',
            en: 'Total mentions',
            ja: '総言及数',
            zhHans: '总提及数',
            zhHant: '總提及數',
          ),
          value: '${aggregate.mentionCount}',
        ),
        if (aggregate.organicMentionCount != null)
          _MetricRow(
            label: _copy(
              language,
              ko: '자연 언급',
              en: 'Organic mentions',
              ja: '自然な言及',
              zhHans: '自然提及',
              zhHant: '自然提及',
            ),
            value: '${aggregate.organicMentionCount}',
          ),
        if (aggregate.sentimentScore != null)
          _MetricRow(
            label: _copy(
              language,
              ko: '감성 집계 지표',
              en: 'Sentiment aggregate',
              ja: '感情集計指標',
              zhHans: '情感汇总指标',
              zhHant: '情感彙總指標',
            ),
            value: aggregate.sentimentScore!.toStringAsFixed(2),
          ),
        if (aggregate.reviewQualityScore != null)
          _MetricRow(
            label: _copy(
              language,
              ko: '리뷰 품질 지표',
              en: 'Review quality aggregate',
              ja: 'レビュー品質指標',
              zhHans: '评论质量指标',
              zhHant: '評論品質指標',
            ),
            value: aggregate.reviewQualityScore!.toStringAsFixed(2),
          ),
        const Divider(height: 24),
        _MetadataLine(
          icon: Icons.date_range_outlined,
          text: '${aggregate.weekStart} ~ ${aggregate.weekEnd}',
        ),
        const SizedBox(height: 7),
        _MetadataLine(
          icon: Icons.update_outlined,
          text:
              envelope?.freshnessLabel(language) ??
              _copy(
                language,
                ko: '집계 시점 미확인',
                en: 'Aggregation time unknown',
                ja: '集計時点は不明',
                zhHans: '汇总时间未知',
                zhHant: '彙總時間未知',
              ),
        ),
      ],
    ),
  );
}

class _PrivacyBoundary extends StatelessWidget {
  const _PrivacyBoundary({required this.language, required this.aggregate});

  final String language;
  final bool aggregate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LalaVisualColors.primarySoft,
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.verified_user_outlined,
          color: LalaVisualColors.primaryBlue,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            aggregate
                ? _copy(
                    language,
                    ko: '승인된 집계 수치만 표시합니다. 원문 리뷰, 작성자, 외부 URL, 정밀 위치는 공개하지 않아요.',
                    en: 'Only approved aggregate values are shown. Raw reviews, authors, external URLs, and precise locations are not exposed.',
                    ja: '承認済みの集計値のみ表示し、原文レビュー、著者、外部URL、正確な位置は公開しません。',
                    zhHans: '仅显示获批汇总值，不公开原始评论、作者、外部网址或精确位置。',
                    zhHant: '僅顯示核准彙總值，不公開原始評論、作者、外部網址或精確位置。',
                  )
                : _copy(
                    language,
                    ko: '검수 후 공개된 경험입니다. 작성자 식별정보와 외부 원문은 표시하지 않아요.',
                    en: 'This experience was published after review. Author identity and external source text are not displayed.',
                    ja: '審査後に公開された体験です。著者の識別情報や外部原文は表示しません。',
                    zhHans: '此体验经审核后公开，不显示作者身份或外部原文。',
                    zhHant: '此體驗經審核後公開，不顯示作者身分或外部原文。',
                  ),
            style: const TextStyle(height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _PlaceActions extends StatelessWidget {
  const _PlaceActions({
    required this.language,
    required this.enabled,
    required this.onViewPlace,
    required this.onOpenPlan,
  });

  final String language;
  final bool enabled;
  final VoidCallback onViewPlace;
  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: OutlinedButton.icon(
          key: const ValueKey('local-signal-detail-place'),
          onPressed: enabled ? onViewPlace : null,
          icon: const Icon(Icons.place_outlined),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, LalaVisualTokens.actionHeight),
          ),
          label: Text(
            _copy(
              language,
              ko: '장소 보기',
              en: 'View place',
              ja: 'スポットを見る',
              zhHans: '查看地点',
              zhHant: '查看地點',
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: FilledButton.icon(
          key: const ValueKey('local-signal-detail-plan'),
          onPressed: enabled ? onOpenPlan : null,
          icon: const Icon(Icons.route_outlined),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, LalaVisualTokens.actionHeight),
          ),
          label: Text(
            _copy(
              language,
              ko: '일정에서 보기',
              en: 'Open plan',
              ja: 'プランで見る',
              zhHans: '在计划中查看',
              zhHant: '在計畫中查看',
            ),
          ),
        ),
      ),
    ],
  );
}

class _ParticipationActions extends StatelessWidget {
  const _ParticipationActions({
    required this.language,
    required this.authenticated,
    required this.useful,
    required this.saved,
    required this.busy,
    required this.reactionCount,
    required this.onUseful,
    required this.onSaved,
    required this.onReport,
  });

  final String language;
  final bool authenticated;
  final bool useful;
  final bool saved;
  final bool busy;
  final int reactionCount;
  final VoidCallback onUseful;
  final VoidCallback onSaved;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _copy(
            language,
            ko: '이 경험에 참여하기',
            en: 'Participate safely',
            ja: 'この体験に参加',
            zhHans: '参与此体验',
            zhHant: '參與此體驗',
          ),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilterChip(
              key: const ValueKey('local-signal-useful'),
              selected: useful,
              onSelected: busy ? null : (_) => onUseful(),
              avatar: const Icon(Icons.thumb_up_alt_outlined, size: 18),
              label: Text(
                '${_copy(language, ko: '도움돼요', en: 'Useful', ja: '役立つ', zhHans: '有帮助', zhHant: '有幫助')} $reactionCount',
              ),
            ),
            FilterChip(
              key: const ValueKey('local-signal-save'),
              selected: saved,
              onSelected: busy ? null : (_) => onSaved(),
              avatar: const Icon(Icons.bookmark_outline, size: 18),
              label: Text(
                _copy(
                  language,
                  ko: '저장',
                  en: 'Save',
                  ja: '保存',
                  zhHans: '保存',
                  zhHant: '儲存',
                ),
              ),
            ),
            ActionChip(
              key: const ValueKey('local-signal-report'),
              onPressed: busy ? null : onReport,
              avatar: const Icon(Icons.flag_outlined, size: 18),
              label: Text(
                _copy(
                  language,
                  ko: '신고',
                  en: 'Report',
                  ja: '報告',
                  zhHans: '举报',
                  zhHant: '檢舉',
                ),
              ),
            ),
          ],
        ),
        if (!authenticated) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _copy(
              language,
              ko: '반응·저장·신고는 로그인 후 사용할 수 있어요.',
              en: 'Sign in to react, save, or report.',
              ja: '反応・保存・報告にはログインが必要です。',
              zhHans: '登录后可回应、保存或举报。',
              zhHant: '登入後可回應、儲存或檢舉。',
            ),
            style: const TextStyle(color: LalaVisualColors.muted, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class _CommentsSection extends StatelessWidget {
  const _CommentsSection({
    required this.language,
    required this.authenticated,
    required this.loading,
    required this.failed,
    required this.comments,
    required this.controller,
    required this.busy,
    required this.onSubmit,
    required this.onRetry,
  });

  final String language;
  final bool authenticated;
  final bool loading;
  final bool failed;
  final List<LocalSignalPublicComment> comments;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _copy(
            language,
            ko: '공개 댓글',
            en: 'Public comments',
            ja: '公開コメント',
            zhHans: '公开评论',
            zhHant: '公開留言',
          ),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (loading)
          const LinearProgressIndicator()
        else if (failed)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _copy(
                    language,
                    ko: '댓글을 불러오지 못했어요.',
                    en: 'Comments could not be loaded.',
                    ja: 'コメントを読み込めませんでした。',
                    zhHans: '无法加载评论。',
                    zhHant: '無法載入留言。',
                  ),
                  style: const TextStyle(color: LalaVisualColors.muted),
                ),
              ),
              TextButton(
                key: const ValueKey('local-signal-comments-retry'),
                onPressed: onRetry,
                child: Text(
                  _copy(
                    language,
                    ko: '다시 시도',
                    en: 'Try again',
                    ja: '再試行',
                    zhHans: '重试',
                    zhHant: '重試',
                  ),
                ),
              ),
            ],
          )
        else if (comments.isEmpty)
          Text(
            _copy(
              language,
              ko: '아직 공개된 댓글이 없어요.',
              en: 'No public comments yet.',
              ja: '公開コメントはまだありません。',
              zhHans: '暂无公开评论。',
              zhHant: '暫無公開留言。',
            ),
            style: const TextStyle(color: LalaVisualColors.muted),
          )
        else
          ...comments.map(
            (comment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(comment.body, style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 3),
                  Text(
                    _dateLabel(comment.createdAt, language),
                    style: const TextStyle(
                      color: LalaVisualColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('local-signal-comment-field'),
          controller: controller,
          enabled: !busy,
          maxLength: 1200,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: authenticated
                ? _copy(
                    language,
                    ko: '확인 가능한 경험을 덧붙여 주세요',
                    en: 'Add a verifiable experience',
                    ja: '確認できる体験を追加してください',
                    zhHans: '补充可验证的体验',
                    zhHant: '補充可驗證的體驗',
                  )
                : _copy(
                    language,
                    ko: '댓글을 쓰려면 로그인하세요',
                    en: 'Sign in to comment',
                    ja: 'コメントにはログインが必要です',
                    zhHans: '登录后评论',
                    zhHant: '登入後留言',
                  ),
            border: const OutlineInputBorder(),
            counterText: '',
            suffixIcon: IconButton(
              key: const ValueKey('local-signal-comment-submit'),
              tooltip: _copy(
                language,
                ko: '댓글 보내기',
                en: 'Send comment',
                ja: 'コメントを送信',
                zhHans: '发送评论',
                zhHant: '傳送留言',
              ),
              onPressed: busy ? null : onSubmit,
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final reasons = <(String, String)>[
      (
        'unsafe_content',
        _copy(
          language,
          ko: '안전하지 않은 내용',
          en: 'Unsafe content',
          ja: '安全でない内容',
          zhHans: '不安全内容',
          zhHant: '不安全內容',
        ),
      ),
      (
        'privacy_exposure',
        _copy(
          language,
          ko: '개인정보 노출',
          en: 'Privacy exposure',
          ja: '個人情報の露出',
          zhHans: '隐私泄露',
          zhHant: '隱私洩露',
        ),
      ),
      (
        'misleading_place',
        _copy(
          language,
          ko: '장소 정보가 잘못됨',
          en: 'Misleading place information',
          ja: '場所情報が不正確',
          zhHans: '地点信息不准确',
          zhHant: '地點資訊不正確',
        ),
      ),
      (
        'promotion_not_disclosed',
        _copy(
          language,
          ko: '광고 고지 누락',
          en: 'Undisclosed promotion',
          ja: '広告表示の不足',
          zhHans: '未披露推广',
          zhHant: '未揭露推廣',
        ),
      ),
      (
        'translation_issue',
        _copy(
          language,
          ko: '번역 문제',
          en: 'Translation issue',
          ja: '翻訳の問題',
          zhHans: '翻译问题',
          zhHant: '翻譯問題',
        ),
      ),
    ];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        Text(
          _copy(
            language,
            ko: '신고 사유',
            en: 'Report reason',
            ja: '報告理由',
            zhHans: '举报原因',
            zhHant: '檢舉原因',
          ),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...reasons.map(
          (reason) => ListTile(
            onTap: () => context.pop(reason.$1),
            title: Text(reason.$2),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: LalaVisualColors.card,
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      border: Border.all(color: LalaVisualColors.line),
    ),
    child: child,
  );
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 18, color: LalaVisualColors.muted),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: LalaVisualColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(
            color: LalaVisualColors.primaryBlue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.language,
    required this.message,
    this.onRetry,
  });

  final String language;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                _copy(
                  language,
                  ko: '다시 시도',
                  en: 'Try again',
                  ja: '再試行',
                  zhHans: '重试',
                  zhHant: '重試',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

String _apiLanguage(String language) => language == 'ko' ? 'ko' : 'en';

String _dateLabel(String? value, String language) {
  final parsed = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (parsed == null) {
    return _copy(
      language,
      ko: '관측 시각 미확인',
      en: 'Observation time unavailable',
      ja: '観測時刻は未確認',
      zhHans: '观测时间未确认',
      zhHant: '觀測時間未確認',
    );
  }
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}'
      '-${parsed.day.toString().padLeft(2, '0')}';
}

String _copy(
  String language, {
  required String ko,
  required String en,
  required String ja,
  required String zhHans,
  required String zhHant,
}) => lalaCopyMulti(
  language,
  ko: ko,
  en: en,
  ja: ja,
  zhHans: zhHans,
  zhHant: zhHant,
);
