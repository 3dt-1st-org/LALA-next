import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../../app/lala_visual_tokens.dart';
import '../../../../shared/l10n/lala_copy.dart';
import '../../data/local_signal_participation_repository.dart';
import '../../domain/local_signal_public.dart';

/// Canonical-place context: the draft attaches to one place with a primary
/// relation and sends no locality code.
typedef LocalSignalPlaceContributionContext = ({
  String placeId,
  String? placeName,
});

/// Manual coarse-region context: the draft attaches to a district-level region
/// id. Precise coordinates are structurally impossible here — the type only
/// carries a code and a display label.
typedef LocalSignalRegionContributionContext = ({String code, String label});

/// Shared private-draft composer (F-071). Hosted as a modal sheet from S-32
/// detail (place context) and embedded on the S-32 route in contribute mode
/// from S-31 (coarse-region context). The widget never navigates; hosts own
/// popping via [onClose].
class LocalSignalContributionComposer extends StatefulWidget {
  const LocalSignalContributionComposer({
    required this.language,
    required this.repository,
    required this.onClose,
    this.placeContext,
    this.regionContext,
    this.onInputStateChanged,
    this.ownsPopGuard = true,
    super.key,
  });

  final String language;
  final LocalSignalParticipationRepository repository;

  /// Hosts pop themselves. `submitted` is true only after a successful submit
  /// was acknowledged with the Done action, so hosts can tell a finished
  /// submission apart from a close, discard, or delete.
  final ValueChanged<bool> onClose;

  /// Whether this widget installs its own PopScope. Modal hosts (bottom
  /// sheet) keep the default; a host that already guards the enclosing route
  /// (e.g. the contribution page) must disable it — two PopScopes on one
  /// route would both react to a blocked pop and open the discard dialog
  /// twice.
  final bool ownsPopGuard;

  /// Mirrors the unsaved-input/busy guard to page hosts that own their own
  /// close affordances (e.g. an AppBar back button), so every exit path runs
  /// the same dismissal protection.
  final void Function(bool dirty, bool busy)? onInputStateChanged;
  final LocalSignalPlaceContributionContext? placeContext;
  final LocalSignalRegionContributionContext? regionContext;

  @override
  State<LocalSignalContributionComposer> createState() =>
      _LocalSignalContributionComposerState();
}

class _LocalSignalContributionComposerState
    extends State<LocalSignalContributionComposer> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  LocalSignalKind _kind = LocalSignalKind.placeTip;
  LocalSignalCommercialDisclosure _disclosure =
      LocalSignalCommercialDisclosure.none;
  bool _aggregateOptIn = false;
  bool _busy = false;
  bool _validationShown = false;
  String? _safeError;
  LocalSignalMutationReceipt? _receipt;

  // True when typed content has not been accepted by a successful save or
  // submit yet — drives the unsaved-dismiss confirmation.
  bool _dirtySinceSave = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _notifyInputState();
  }

  void _notifyInputState() =>
      widget.onInputStateChanged?.call(_dirtySinceSave, _busy);

  LocalSignalDraftInput _input() {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
    return LocalSignalDraftInput(
      kind: _kind,
      sourceLanguage: _apiLanguage(widget.language),
      title: _title.text,
      body: _body.text,
      observationDate: date,
      commercialDisclosure: _disclosure,
      aggregateOptIn: _aggregateOptIn,
      placeId: widget.placeContext?.placeId,
      localityCode: widget.placeContext == null
          ? widget.regionContext?.code
          : null,
    );
  }

  bool get _titleValid => _title.text.trim().isNotEmpty;
  bool get _bodyValid => _body.text.trim().isNotEmpty;
  bool get _valid => _titleValid && _bodyValid;

  Future<void> _save() async {
    if (_busy) return;
    if (!_valid) {
      // Validation feedback: keep the failure visible per field instead of a
      // silently disabled button.
      setState(() => _validationShown = true);
      return;
    }
    setState(() {
      _busy = true;
      _safeError = null;
    });
    _notifyInputState();
    try {
      final receipt = _receipt == null
          ? await widget.repository.createDraft(_input())
          : await widget.repository.updateDraft(_receipt!.id, _input());
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _dirtySinceSave = false;
        _validationShown = false;
      });
      _notifyInputState();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _safeError = _safeRequestError(widget.language, error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _notifyInputState();
      }
    }
  }

  Future<void> _submit() async {
    final receipt = _receipt;
    if (_busy || receipt == null) return;
    setState(() {
      _busy = true;
      _safeError = null;
    });
    _notifyInputState();
    try {
      final submitted = await widget.repository.submitDraft(receipt.id);
      if (!mounted) return;
      // Stay open so the governed moderation/visibility receipt is read before
      // the host closes the flow.
      setState(() {
        _receipt = submitted;
        _dirtySinceSave = false;
      });
      _notifyInputState();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _safeError = _safeRequestError(widget.language, error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _notifyInputState();
      }
    }
  }

  Future<void> _delete() async {
    final receipt = _receipt;
    if (_busy || receipt == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('local-signal-draft-delete-confirm'),
        title: Text(
          _copy(
            widget.language,
            ko: '초안을 삭제할까요?',
            en: 'Delete this draft?',
            ja: '下書きを削除しますか？',
            zhHans: '删除草稿？',
            zhHant: '刪除草稿？',
          ),
        ),
        content: Text(
          _copy(
            widget.language,
            ko: '삭제한 초안은 되돌릴 수 없어요.',
            en: 'A deleted draft cannot be restored.',
            ja: '削除した下書きは元に戻せません。',
            zhHans: '删除的草稿无法恢复。',
            zhHant: '刪除的草稿無法復原。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('local-signal-draft-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              _copy(
                widget.language,
                ko: '취소',
                en: 'Cancel',
                ja: 'キャンセル',
                zhHans: '取消',
                zhHant: '取消',
              ),
            ),
          ),
          FilledButton(
            key: const ValueKey('local-signal-draft-delete-action'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _copy(
                widget.language,
                ko: '삭제',
                en: 'Delete',
                ja: '削除',
                zhHans: '删除',
                zhHant: '刪除',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _safeError = null;
    });
    _notifyInputState();
    try {
      await widget.repository.deleteDraft(receipt.id);
      if (mounted) widget.onClose(false);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _safeError = _safeRequestError(widget.language, error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _notifyInputState();
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    return await showDialog<bool>(
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
        ) ??
        false;
  }

  /// Explicit close action (X button, system back). Dirty input requires
  /// confirmation; a busy composer refuses to close mid-request.
  Future<void> _requestClose({bool submitted = false}) async {
    if (_busy) return;
    if (_dirtySinceSave && !submitted) {
      final discard = await _confirmDiscard();
      if (!discard || !mounted) return;
    }
    widget.onClose(submitted);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _receipt?.status == 'submitted';
    // Back/system-pop protection mirrors the explicit close: clean input may
    // pop straight away; dirty input must pass the discard confirmation. A
    // busy composer blocks the pop until the request settles.
    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                _copy(
                  widget.language,
                  ko: '경험 초안',
                  en: 'Experience draft',
                  ja: '体験の下書き',
                  zhHans: '体验草稿',
                  zhHant: '體驗草稿',
                ),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('local-signal-composer-close'),
              tooltip: _copy(
                widget.language,
                ko: '닫기',
                en: 'Close',
                ja: '閉じる',
                zhHans: '关闭',
                zhHant: '關閉',
              ),
              onPressed: _busy ? null : _requestClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _copy(
            widget.language,
            ko: '한국어와 영어 원문을 지원합니다. 외국어 화면에서는 영어 원문으로 제출돼요.',
            en: 'Original contributions currently support Korean and English.',
            ja: '現在、原文投稿は韓国語と英語に対応しています。',
            zhHans: '目前原创投稿支持韩文和英文。',
            zhHant: '目前原創投稿支援韓文與英文。',
          ),
          style: const TextStyle(color: LalaVisualColors.muted),
        ),
        const SizedBox(height: 12),
        _ContextLine(
          language: widget.language,
          placeContext: widget.placeContext,
          regionContext: widget.regionContext,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<LocalSignalKind>(
          key: const ValueKey('local-signal-draft-kind'),
          // Why: without isExpanded the selected-item row sizes intrinsically
          // and overflows the field at large text scales.
          isExpanded: true,
          initialValue: _kind,
          decoration: InputDecoration(
            labelText: _copy(
              widget.language,
              ko: '경험 유형',
              en: 'Experience type',
              ja: '体験の種類',
              zhHans: '体验类型',
              zhHant: '體驗類型',
            ),
            border: const OutlineInputBorder(),
          ),
          items: LocalSignalKind.values
              .map(
                (kind) => DropdownMenuItem<LocalSignalKind>(
                  value: kind,
                  child: Text(kind.label(widget.language)),
                ),
              )
              .toList(growable: false),
          onChanged: submitted || _busy
              ? null
              : (value) => setState(() => _kind = value ?? _kind),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('local-signal-draft-title'),
          controller: _title,
          enabled: !submitted && !_busy,
          maxLength: 160,
          onChanged: (_) {
            setState(() => _dirtySinceSave = true);
            _notifyInputState();
          },
          decoration: InputDecoration(
            labelText: _copy(
              widget.language,
              ko: '제목',
              en: 'Title',
              ja: 'タイトル',
              zhHans: '标题',
              zhHant: '標題',
            ),
            errorText: _validationShown && !_titleValid
                ? _copy(
                    widget.language,
                    ko: '제목을 입력해 주세요',
                    en: 'Enter a title',
                    ja: 'タイトルを入力してください',
                    zhHans: '请输入标题',
                    zhHant: '請輸入標題',
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('local-signal-draft-body'),
          controller: _body,
          enabled: !submitted && !_busy,
          minLines: 4,
          maxLines: 8,
          maxLength: 4000,
          onChanged: (_) {
            setState(() => _dirtySinceSave = true);
            _notifyInputState();
          },
          decoration: InputDecoration(
            labelText: _copy(
              widget.language,
              ko: '언제 무엇을 확인했는지 적어 주세요',
              en: 'Describe what you observed and when',
              ja: 'いつ何を確認したか記入してください',
              zhHans: '请说明何时观察到什么',
              zhHant: '請說明何時觀察到什麼',
            ),
            errorText: _validationShown && !_bodyValid
                ? _copy(
                    widget.language,
                    ko: '본문을 입력해 주세요',
                    en: 'Describe your observation',
                    ja: '本文を入力してください',
                    zhHans: '请输入正文',
                    zhHant: '請輸入內文',
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<LocalSignalCommercialDisclosure>(
          key: const ValueKey('local-signal-draft-disclosure'),
          isExpanded: true,
          initialValue: _disclosure,
          decoration: InputDecoration(
            labelText: _copy(
              widget.language,
              ko: '상업 관계 고지',
              en: 'Commercial disclosure',
              ja: '商業関係の開示',
              zhHans: '商业关系披露',
              zhHant: '商業關係揭露',
            ),
            border: const OutlineInputBorder(),
          ),
          items: LocalSignalCommercialDisclosure.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(
                    value == LocalSignalCommercialDisclosure.none
                        ? _copy(
                            widget.language,
                            ko: '해당 없음',
                            en: 'None',
                            ja: 'なし',
                            zhHans: '无',
                            zhHant: '無',
                          )
                        : value.label(widget.language),
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: submitted || _busy
              ? null
              : (value) => setState(() => _disclosure = value ?? _disclosure),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('local-signal-draft-aggregate-opt-in'),
          contentPadding: EdgeInsets.zero,
          value: _aggregateOptIn,
          onChanged: submitted || _busy
              ? null
              : (value) => setState(() => _aggregateOptIn = value ?? false),
          title: Text(
            _copy(
              widget.language,
              ko: '익명 집계에 포함하는 데 동의',
              en: 'Allow anonymous aggregate use',
              ja: '匿名集計への利用に同意',
              zhHans: '同意用于匿名汇总',
              zhHant: '同意用於匿名彙總',
            ),
          ),
          subtitle: Text(
            _copy(
              widget.language,
              ko: '원문과 작성자 정보는 집계에 공개되지 않아요.',
              en: 'Raw text and author identity are never exposed in aggregates.',
              ja: '原文や著者情報は集計に公開されません。',
              zhHans: '汇总中不会公开原文或作者身份。',
              zhHant: '彙總中不會公開原文或作者身分。',
            ),
          ),
        ),
        if (_safeError != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _safeError!,
            key: const ValueKey('local-signal-draft-error'),
            style: const TextStyle(
              color: Color(0xFFBE123C),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        if (_receipt != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            // Moderation transparency: the receipt's governed status,
            // review state, and visibility are labeled, never invented —
            // unknown wire values render as the raw contract value.
            _copy(
              widget.language,
              ko: '상태: ${_receipt!.statusLabel(widget.language)} · 검수: ${_receipt!.moderationStateLabel(widget.language)} · 공개 범위: ${_receipt!.visibilityLabel(widget.language)}',
              en: 'Status: ${_receipt!.statusLabel(widget.language)} · Review: ${_receipt!.moderationStateLabel(widget.language)} · Visibility: ${_receipt!.visibilityLabel(widget.language)}',
              ja: '状態: ${_receipt!.statusLabel(widget.language)} · 審査: ${_receipt!.moderationStateLabel(widget.language)} · 公開範囲: ${_receipt!.visibilityLabel(widget.language)}',
              zhHans:
                  '状态：${_receipt!.statusLabel(widget.language)} · 审核：${_receipt!.moderationStateLabel(widget.language)} · 可见性：${_receipt!.visibilityLabel(widget.language)}',
              zhHant:
                  '狀態：${_receipt!.statusLabel(widget.language)} · 審核：${_receipt!.moderationStateLabel(widget.language)} · 可見性：${_receipt!.visibilityLabel(widget.language)}',
            ),
            key: const ValueKey('local-signal-draft-receipt-status'),
            style: const TextStyle(
              color: LalaVisualColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (submitted)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('local-signal-draft-done'),
              onPressed: () => _requestClose(submitted: true),
              icon: const Icon(Icons.check_rounded),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, LalaVisualTokens.actionHeight),
              ),
              label: Text(
                _copy(
                  widget.language,
                  ko: '완료',
                  en: 'Done',
                  ja: '完了',
                  zhHans: '完成',
                  zhHant: '完成',
                ),
              ),
            ),
          )
        else ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('local-signal-draft-save'),
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, LalaVisualTokens.actionHeight),
              ),
              label: Text(
                _receipt == null
                    ? _copy(
                        widget.language,
                        ko: '비공개 초안 저장',
                        en: 'Save private draft',
                        ja: '非公開の下書きを保存',
                        zhHans: '保存私密草稿',
                        zhHant: '儲存私密草稿',
                      )
                    : _copy(
                        widget.language,
                        ko: '초안 수정 저장',
                        en: 'Update draft',
                        ja: '下書きを更新',
                        zhHans: '更新草稿',
                        zhHant: '更新草稿',
                      ),
              ),
            ),
          ),
          if (_receipt != null) ...<Widget>[
            const SizedBox(height: 10),
            // Stacked (not side by side) so 200% text-scale labels never
            // overflow a fixed two-column row.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('local-signal-draft-delete'),
                onPressed: _busy ? null : _delete,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(
                  _copy(
                    widget.language,
                    ko: '초안 삭제',
                    en: 'Delete draft',
                    ja: '下書きを削除',
                    zhHans: '删除草稿',
                    zhHant: '刪除草稿',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('local-signal-draft-submit'),
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(
                  _copy(
                    widget.language,
                    ko: '검수 요청',
                    en: 'Submit for review',
                    ja: '審査を依頼',
                    zhHans: '提交审核',
                    zhHant: '提交審核',
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
    if (!widget.ownsPopGuard) return body;
    return PopScope(
      canPop: !_dirtySinceSave && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: body,
    );
  }
}

/// Shows what the draft will attach to. Never precise coordinates: a canonical
/// place, a manual coarse region, or an honest no-context line.
class _ContextLine extends StatelessWidget {
  const _ContextLine({
    required this.language,
    required this.placeContext,
    required this.regionContext,
  });

  final String language;
  final LocalSignalPlaceContributionContext? placeContext;
  final LocalSignalRegionContributionContext? regionContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = placeContext;
    final region = regionContext;
    final (icon, text) = switch ((place, region)) {
      (final p?, _) => (
        Icons.place_outlined,
        p.placeName == null
            ? _copy(
                language,
                ko: '선택한 장소에 연결돼요',
                en: 'Attached to the selected place',
                ja: '選択したスポットに紐づきます',
                zhHans: '将关联到所选地点',
                zhHant: '將關聯到所選地點',
              )
            : _copy(
                language,
                ko: '장소 맥락: ${p.placeName}',
                en: 'Place context: ${p.placeName}',
                ja: 'スポット文脈：${p.placeName}',
                zhHans: '地点背景：${p.placeName}',
                zhHant: '地點背景：${p.placeName}',
              ),
      ),
      (_, final r?) => (
        Icons.location_on_outlined,
        _copy(
          language,
          ko: '지역 맥락: ${r.label}',
          en: 'Area context: ${r.label}',
          ja: '地域文脈：${r.label}',
          zhHans: '地区背景：${r.label}',
          zhHant: '地區背景：${r.label}',
        ),
      ),
      (null, null) => (
        Icons.public_outlined,
        _copy(
          language,
          ko: '지역 맥락 없음 · 전국 대상 관찰로 저장돼요',
          en: 'No area context · saved as a nationwide observation',
          ja: '地域文脈なし · 全国対象の観察として保存されます',
          zhHans: '无地区背景 · 将保存为全国范围的观察',
          zhHant: '無地區背景 · 將儲存為全國範圍的觀察',
        ),
      ),
    };
    return Container(
      key: const ValueKey('local-signal-composer-context'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LalaVisualColors.primarySoft,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: LalaVisualColors.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: LalaVisualColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal-sheet host for the composer. Barrier and drag dismissal are disabled:
/// the only exits are the composer's explicit (confirmation-guarded) close,
/// successful submit + Done, or delete — so unsaved text cannot be lost by an
/// accidental tap outside.
Future<bool?> showLocalSignalContributionSheet(
  BuildContext context, {
  required String language,
  required LocalSignalParticipationRepository repository,
  LocalSignalPlaceContributionContext? placeContext,
  LocalSignalRegionContributionContext? regionContext,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: LalaVisualColors.surface,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LalaVisualColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LocalSignalContributionComposer(
              language: language,
              repository: repository,
              placeContext: placeContext,
              regionContext: regionContext,
              onClose: (submitted) => Navigator.of(sheetContext).pop(submitted),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shared "share your experience" entry panel. Used by S-31 (auth state
/// unknown to that page — `authenticated: null` keeps the copy honest) and
/// S-32 detail (real auth state).
class LocalSignalContributionEntry extends StatelessWidget {
  const LocalSignalContributionEntry({
    super.key,
    required this.language,
    required this.onPressed,
    this.authenticated,
    this.contextLabel,
    this.entryKey,
    this.buttonKey,
  });

  final String language;
  final VoidCallback onPressed;
  final bool? authenticated;
  final String? contextLabel;
  final Key? entryKey;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final authenticated = this.authenticated;
    return Card(
      key: entryKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _copy(
                language,
                ko: '내 경험 보태기',
                en: 'Share your experience',
                ja: '自分の体験を共有',
                zhHans: '分享你的体验',
                zhHant: '分享你的體驗',
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              contextLabel == null
                  ? _copy(
                      language,
                      ko: '초안은 비공개로 저장되고 검수 승인 뒤에만 공개됩니다. 작성에는 로그인이 필요해요.',
                      en: 'Drafts stay private and are published only after review. Writing requires sign-in.',
                      ja: '下書きは非公開で保存され、審査承認後にのみ公開されます。投稿にはログインが必要です。',
                      zhHans: '草稿保持私密，仅在审核通过后公开。撰写需要登录。',
                      zhHant: '草稿維持私密，僅在審核通過後公開。撰寫需要登入。',
                    )
                  : _copy(
                      language,
                      ko: '$contextLabel의 관찰을 남길 수 있어요. 초안은 비공개로 저장되고 검수 승인 뒤에만 공개되며, 작성에는 로그인이 필요해요.',
                      en: 'Share an observation for $contextLabel. Drafts stay private, publish only after review, and writing requires sign-in.',
                      ja: '$contextLabelに関する観察を投稿できます。下書きは非公開で保存され、審査承認後にのみ公開されます。投稿にはログインが必要です。',
                      zhHans: '可以分享关于$contextLabel的观察。草稿保持私密，仅在审核通过后公开，撰写需要登录。',
                      zhHant: '可以分享關於$contextLabel的觀察。草稿維持私密，僅在審核通過後公開，撰寫需要登入。',
                    ),
              style: const TextStyle(
                color: LalaVisualColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key:
                    buttonKey ??
                    const ValueKey('local-signal-share-experience'),
                onPressed: onPressed,
                icon: Icon(
                  authenticated == false
                      ? Icons.login_rounded
                      : Icons.edit_note_rounded,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, LalaVisualTokens.actionHeight),
                ),
                label: Text(switch (authenticated) {
                  true => _copy(
                    language,
                    ko: '경험 초안 작성',
                    en: 'Write a private draft',
                    ja: '非公開の下書きを作成',
                    zhHans: '撰写私密草稿',
                    zhHant: '撰寫私密草稿',
                  ),
                  false => _copy(
                    language,
                    ko: '로그인하고 경험 공유',
                    en: 'Sign in to contribute',
                    ja: 'ログインして共有',
                    zhHans: '登录后分享',
                    zhHant: '登入後分享',
                  ),
                  null => _copy(
                    language,
                    ko: '경험 공유하기',
                    en: 'Share your experience',
                    ja: '体験を共有する',
                    zhHans: '分享体验',
                    zhHant: '分享體驗',
                  ),
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _apiLanguage(String language) => language == 'ko' ? 'ko' : 'en';

/// Safe error copy. A governed write-disabled rejection gets its own honest
/// message; everything else keeps the input-preserving generic retry copy.
String _safeRequestError(String language, Object error) {
  if (error is LalaApiException && error.code == 'LOCAL_SIGNALS_DISABLED') {
    return _copy(
      language,
      ko: '지금은 로컬 신호 작성을 받고 있지 않아요. 입력 내용은 화면에 남아 있어요.',
      en: 'Local Signal writing is not being accepted right now. Your input remains on this screen.',
      ja: '現在、ローカル信号の投稿は受け付けていません。入力内容は画面に残っています。',
      zhHans: '目前暂不接受本地信号撰写。输入内容仍保留在页面上。',
      zhHant: '目前暫不接受在地訊號撰寫。輸入內容仍保留在畫面上。',
    );
  }
  return _copy(
    language,
    ko: '요청을 완료하지 못했어요. 입력 내용은 화면에 남아 있어요.',
    en: 'The request failed. Your input remains on this screen.',
    ja: 'リクエストに失敗しました。入力内容は画面に残っています。',
    zhHans: '请求失败，输入内容仍保留在页面上。',
    zhHant: '請求失敗，輸入內容仍保留在畫面上。',
  );
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
