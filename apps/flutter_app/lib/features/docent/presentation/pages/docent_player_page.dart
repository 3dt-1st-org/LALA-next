// 이슈 #120 §6.3: 전체 화면 도슨트 플레이어(메인 쉘 외부 push 라우트).
// source/generatedAt/grounding 은 실제 스크립트 필드가 있을 때만 렌더한다 —
// duration·seek·챕터·인용 퍼센트처럼 지원되지 않거나 없는 정보는 만들지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../../shared/l10n/place_labels.dart';
import '../../../place/place_helpers.dart';
import '../../../place/widgets/place_image.dart';
import '../../docent_helpers.dart';
import '../../experience/docent_experience_controller.dart';
import '../../experience/docent_experience_copy.dart';
import '../../experience/docent_experience_state.dart';
import '../../../onboarding/onboarding_state.dart';

class DocentPlayerPage extends StatelessWidget {
  const DocentPlayerPage({super.key, required this.controller});

  final DocentExperienceController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (BuildContext context, String language, Widget? _) {
        return ValueListenableBuilder<DocentExperienceState>(
          valueListenable: controller.state,
          builder:
              (BuildContext context, DocentExperienceState state, Widget? _) {
                final place = state.place;
                if (place == null) {
                  // 세션이 이미 정지/비었으면 빈 배경만(가짜 콘텐츠 금지). AppBar 의
                  // 자동 back 버튼으로 항상 탈출구를 남긴다 — 빈 Scaffold 에 갇히지 않게.
                  return Scaffold(
                    appBar: AppBar(),
                    body: const SizedBox.shrink(),
                  );
                }
                return Scaffold(
                  appBar: AppBar(
                    title: Text(
                      placeDisplayName(place, language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _DocentVerifiedImage(place: place),
                      const SizedBox(height: 12),
                      _DocentPlayerHeader(
                        place: place,
                        language: language,
                        state: state,
                      ),
                      const SizedBox(height: 12),
                      _DocentPlaybackCard(
                        controller: controller,
                        language: language,
                        state: state,
                        onStop: () => _stopDocentSession(context, controller),
                      ),
                      const SizedBox(height: 16),
                      _DocentTranscriptCard(state: state, language: language),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  // 정지는 세션 종료(state.place → null)라 이 페이지를 빈 Scaffold 로 남긴다 —
  // 이전 화면으로 돌려보내 빈 페이지에 갇히지 않게 한다.
  void _stopDocentSession(
    BuildContext context,
    DocentExperienceController controller,
  ) {
    unawaited(controller.stop());
    if (context.canPop()) {
      context.pop();
    }
  }
}

/// 검증된 공식 이미지 16:9. 없으면 중성 빈 슬롯(임의 사진 금지 — 맵 레일과 동일 규칙).
class _DocentVerifiedImage extends StatelessWidget {
  const _DocentVerifiedImage({required this.place});

  final LalaPlace place;

  @override
  Widget build(BuildContext context) {
    final hasImage = hasOfficialPlaceImage(place);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: hasImage
            ? PlaceImage(
                place: place,
                width: double.infinity,
                height: double.infinity,
              )
            : const ColoredBox(
                color: Color(0xFFEDF2F7),
                child: Center(
                  child: Icon(
                    Icons.photo_camera_front_outlined,
                    size: 32,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
      ),
    );
  }
}

/// 장소명 + 운전기사용 한국어 이름 유틸리티 + source/생성시각/grounding 칩.
class _DocentPlayerHeader extends StatelessWidget {
  const _DocentPlayerHeader({
    required this.place,
    required this.language,
    required this.state,
  });

  final LalaPlace place;
  final String language;
  final DocentExperienceState state;

  @override
  Widget build(BuildContext context) {
    final displayName = placeDisplayName(place, language);
    final nameKo = place.nameKo?.trim();
    // 외국어 표시명에서는 한국어 원문도 함께 보여준다. 기사님 유틸리티는 실제
    // nameKo 가 있으면 현재 UI 언어와 관계없이 제공한다(§6.3의 유일한 숨김 조건).
    final driverName = nameKo != null && nameKo.isNotEmpty ? nameKo : null;
    final showKoreanName = driverName != null && driverName != displayName;
    final script = state.script;
    final chips = <Widget>[
      if (script != null)
        _DocentMetaChip(
          label: docentScriptSourceLabel(script.source, language),
        ),
      if (script?.generatedAt != null)
        ..._generatedAtChip(script!.generatedAt!, language),
      ..._groundingChips(
        script?.groundingSources ?? const <String>[],
        language,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        if (showKoreanName) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            driverName,
            key: const ValueKey('docent-korean-place-name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        if (chips.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
        if (driverName != null) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('docent-driver-name-button'),
              onPressed: () => _showDriverNameSheet(context, driverName),
              icon: const Icon(Icons.local_taxi_outlined, size: 18),
              label: Text(
                docentDriverNameButtonLabel(language),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF744210),
                side: const BorderSide(color: Color(0xFFF5C842)),
                backgroundColor: const Color(0xFFFFFBEB),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // generatedAt 은 파싱 가능할 때만 라벨로 노출(파싱 불가 = honest 생략).
  List<Widget> _generatedAtChip(String raw, String language) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return const <Widget>[];
    }
    return <Widget>[
      _DocentMetaChip(label: docentGeneratedAtLabel(parsed, language)),
    ];
  }

  // grounding 은 bounded 지역화 라벨로만 — 원시 내부 식별자를 노출하지 않는다.
  // 없으면 아무것도 만들지 않는다.
  List<Widget> _groundingChips(List<String> sources, String language) {
    return <Widget>[
      for (final source in sources)
        if (source.trim().isNotEmpty)
          _DocentMetaChip(
            label: docentGroundingSourceLabel(source, language),
            grounding: true,
          ),
    ];
  }

  void _showDriverNameSheet(BuildContext context, String driverName) {
    // 기사님 시트에는 실제 주소도 함께 — 있을 때만(없으면 라인을 만들지 않는다).
    final address = place.address.trim();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                docentDriverNameSheetCaption(language),
                style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
              ),
              const SizedBox(height: 8),
              // 기사님에게 보여주는 용도 — 한국어 원문을 크게, 번역하지 않는다.
              Text(
                driverName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (address.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  address,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DocentMetaChip extends StatelessWidget {
  const _DocentMetaChip({required this.label, this.grounding = false});

  final String label;
  final bool grounding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: grounding ? const Color(0xFFF1F5F9) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: grounding ? const Color(0xFFE2E8F0) : const Color(0xFFF5C842),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF744210),
        ),
      ),
    );
  }
}

/// 재생 상태 + 재생/일시정지/정지 컨트롤. 앰버 토큰은 tour_audio_bar 계열 재사용.
/// seek 슬라이더/진행바/남은 시간은 제공하지 않는다(플레이어가 지원하지 않음).
class _DocentPlaybackCard extends StatelessWidget {
  const _DocentPlaybackCard({
    required this.controller,
    required this.language,
    required this.state,
    required this.onStop,
  });

  final DocentExperienceController controller;
  final String language;
  final DocentExperienceState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final queuePrefix = state.queueActive
        ? '${docentMiniQueueProgress(state.queueIndex, state.queue.length)} · '
        : '';
    final caption =
        state.safeMessage ?? docentExperiencePhaseLabel(state.phase, language);
    final isPlaying = state.phase == DocentExperiencePhase.playing;
    final isPreparing = state.preparing;
    final isRetry =
        state.phase == DocentExperiencePhase.unavailable ||
        state.phase == DocentExperiencePhase.failed;
    final toggleLabel = isRetry
        ? docentRetrySemanticLabel(language)
        : isPlaying
        ? docentPauseSemanticLabel(language)
        : docentPlaySemanticLabel(language);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5C842)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$queuePrefix$caption',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF744210),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: Semantics(
              label: toggleLabel,
              button: true,
              child: IconButton(
                onPressed: isPreparing
                    ? null
                    : () => controller.toggleControl(),
                icon: isPreparing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isRetry
                            ? Icons.refresh_rounded
                            : isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: const Color(0xFFC87F11),
                      ),
                padding: EdgeInsets.zero,
                tooltip: toggleLabel,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: Semantics(
              label: docentStopSemanticLabel(language),
              button: true,
              child: IconButton(
                onPressed: onStop,
                icon: const Icon(Icons.stop_rounded, color: Color(0xFFC87F11)),
                padding: EdgeInsets.zero,
                tooltip: docentStopSemanticLabel(language),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 단일 언어 스크립트 전문(스크롤 가능). 이 언어로 쓸 수 있는 스크립트가 없으면
/// 섹션 전체를 honest 하게 생략한다 — 빈 문구로 채우지 않는다.
class _DocentTranscriptCard extends StatelessWidget {
  const _DocentTranscriptCard({required this.state, required this.language});

  final DocentExperienceState state;
  final String language;

  @override
  Widget build(BuildContext context) {
    final script = state.script;
    final text = script == null
        ? null
        : usableDocentScript(script.script, language);
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          docentTranscriptSectionTitle(language),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(fontSize: 15, height: 1.5)),
      ],
    );
  }
}
