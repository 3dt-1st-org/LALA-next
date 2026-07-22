// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
// _Dashboard -> public Dashboard. 하단 시트/오버레이를 조합하는 presentational 컴포지터.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/map_sheet_visibility.dart';
import 'package:lala_next_app/features/docent/docent_helpers.dart';
import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/home/widgets/map_draggable_sheet.dart';
import 'package:lala_next_app/features/intervention/widgets/intervention_toast.dart';
import 'package:lala_next_app/features/location/widgets/location_consent_overlay.dart';
import 'package:lala_next_app/features/location/widgets/location_start_prompt_overlay.dart';
import 'package:lala_next_app/features/location/widgets/location_startup_overlay.dart';
import 'package:lala_next_app/features/map/domain/active_map_sheet.dart';
import 'package:lala_next_app/features/map/map_helpers.dart';
import 'package:lala_next_app/features/map/widgets/floating_map_controls.dart';
import 'package:lala_next_app/features/map/widgets/legacy_map_canvas.dart';
import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';
import 'package:lala_next_app/features/map/widgets/map_place_carousel_overlay.dart';
import 'package:lala_next_app/features/map/widgets/map_toast.dart';
import 'package:lala_next_app/features/map/widgets/map_utility_control_row.dart';
import 'package:lala_next_app/features/map/widgets/top_map_chrome.dart';
import 'package:lala_next_app/features/tour/widgets/tour_map_pill.dart';
import 'package:lala_next_app/features/weather/weather_helpers.dart';
import 'package:lala_next_app/kakao_map_view.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/smoke_state.dart';

const String _buildSha = String.fromEnvironment('LALA_BUILD_SHA');

const List<LalaPlace> _bundledStartupPlaces = <LalaPlace>[
  LalaPlace(
    placeId: 'tour-api-2469037',
    name: '히말라야정원',
    category: 'restaurant',
    lat: 37.2635931591,
    lng: 127.0338939523,
    address: '경기도 수원시 팔달구 권광로180번길 19 (인계동) 2층',
    distanceM: 470,
    source: 'db',
    nameKo: '히말라야정원',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/38/3563938_image2_1.jpg',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
  LalaPlace(
    placeId: 'tour-api-129191',
    name: '나혜석거리',
    category: 'attraction',
    lat: 37.2640208974,
    lng: 127.0344383354,
    address: '경기도 수원시 팔달구 권광로188번길 25-2 (인계동)',
    distanceM: 520,
    source: 'db',
    nameKo: '나혜석거리',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/99/3400899_image2_1.JPG',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
  LalaPlace(
    placeId: 'tour-api-130489',
    name: '경기아트센터',
    category: 'culture_venue',
    lat: 37.2614073374,
    lng: 127.0359410498,
    address: '경기도 수원시 팔달구 효원로307번길 20 (인계동)',
    distanceM: 695,
    source: 'db',
    nameKo: '경기아트센터',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/50/3055250_image2_1.JPG',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
  LalaPlace(
    placeId: 'tour-api-3517333',
    name: '제3회 발달장애인 문화예술페스티벌',
    category: 'event',
    lat: 37.2614073374,
    lng: 127.0359410498,
    address: '경기도 수원시 팔달구 효원로307번길 20 (인계동)',
    distanceM: 695,
    source: 'db',
    nameKo: '제3회 발달장애인 문화예술페스티벌',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/32/3517332_image2_1.jpeg',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
];

class Dashboard extends StatelessWidget {
  const Dashboard({super.key,
    required this.loading,
    required this.error,
    required this.health,
    required this.readiness,
    required this.places,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.tourAudio,
    required this.audioLoading,
    required this.audioError,
    required this.tourAudioLoading,
    required this.tourAudioError,
    required this.authMode,
    required this.kakaoJavascriptKey,
    required this.selectedCategory,
    required this.selectedPlaceId,
    required this.activeSheet,
    required this.uiLanguage,
    required this.voiceEnabled,
    required this.autoDocentEnabled,
    required this.showEvidence,
    required this.savedPlaceIds,
    required this.detailDocentPlayedPlaceIds,
    required this.interventionToastDismissed,
    required this.locationConsentEnabled,
    required this.locationRequestInFlight,
    required this.locationFallbackNoticeVisible,
    required this.locationStartPromptVisible,
    required this.recommendationRailExpanded,
    required this.recommendationRecoveryPending,
    required this.recommendationRecoveryAttempt,
    required this.focusedClusterMemberIds,
    required this.mapFocusLat,
    required this.mapFocusLng,
    required this.mapLevel,
    required this.onSelectCategory,
    required this.onSelectPlace,
    required this.onSelectCluster,
    required this.onCameraIdle,
    required this.onClearPlaceSelection,
    required this.onToggleRecommendationRail,
    required this.onOpenSheet,
    required this.onCloseSheet,
    required this.onToggleVoice,
    required this.onToggleAutoDocent,
    required this.onToggleEvidence,
    required this.onToggleSavedPlace,
    required this.onDismissInterventionToast,
    required this.onFetchAudio,
    required this.onFetchTourAudio,
    required this.onRefresh,
    required this.onRefreshWeather,
    required this.onReturnToLocation,
    required this.onOpenSettings,
    required this.onOpenManualLocation,
    required this.onRetryLocation,
    required this.onStartLocation,
  });

  final bool loading;
  final String? error;
  final LalaEnvelope<Map<String, dynamic>>? health;
  final LalaEnvelope<LalaReadiness>? readiness;
  final LalaEnvelope<LalaPlacesResponse>? places;
  final LalaEnvelope<LalaWeather>? weather;
  final LalaEnvelope<LalaIntervention>? intervention;
  final LalaEnvelope<LalaDailyPlan>? dailyPlan;
  final LalaEnvelope<LalaDocentScript>? docentScript;
  final LalaAudioResponse? docentAudio;
  final LalaAudioResponse? tourAudio;
  final bool audioLoading;
  final String? audioError;
  final bool tourAudioLoading;
  final String? tourAudioError;
  final LalaAuthMode authMode;
  final String kakaoJavascriptKey;
  final String selectedCategory;
  final String? selectedPlaceId;
  final ActiveMapSheet? activeSheet;
  final String uiLanguage;
  final bool voiceEnabled;
  final bool autoDocentEnabled;
  final bool showEvidence;
  final Set<String> savedPlaceIds;
  final Set<String> detailDocentPlayedPlaceIds;
  final bool interventionToastDismissed;
  final bool locationConsentEnabled;
  final bool locationRequestInFlight;
  final bool locationFallbackNoticeVisible;
  final bool locationStartPromptVisible;
  final bool recommendationRailExpanded;
  final bool recommendationRecoveryPending;
  final int recommendationRecoveryAttempt;
  final List<String> focusedClusterMemberIds;
  final double? mapFocusLat;
  final double? mapFocusLng;
  final int mapLevel;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<LalaPlace> onSelectPlace;
  final ValueChanged<KakaoMapPlace> onSelectCluster;
  final ValueChanged<KakaoMapCamera> onCameraIdle;
  final VoidCallback onClearPlaceSelection;
  final VoidCallback onToggleRecommendationRail;
  final ValueChanged<ActiveMapSheet> onOpenSheet;
  final VoidCallback onCloseSheet;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleAutoDocent;
  final VoidCallback onToggleEvidence;
  final ValueChanged<String> onToggleSavedPlace;
  final VoidCallback onDismissInterventionToast;
  final VoidCallback onFetchAudio;
  final VoidCallback onFetchTourAudio;
  final VoidCallback onRefresh;
  final VoidCallback onRefreshWeather;
  final VoidCallback onReturnToLocation;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenManualLocation;
  final VoidCallback onRetryLocation;
  final VoidCallback onStartLocation;

  @override
  Widget build(BuildContext context) {
    // ONMU P0: 시트 활성화 여부를 빌드 이후(post-frame)에 쉘에 전파 → 하단 네비게이션
    // 바를 숨긴다. 시트가 네비게이션 바 위까지 덮어 콘텐츠(예: 점수/근거 버튼)가
    // 가려지지 않도록 한다. post-frame 콜백으로 빌드 중 리빌드를 유발하지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = activeSheet != null;
      if (lalaMapSheetActive.value != active) {
        lalaMapSheetActive.value = active;
      }
    });
    final apiPlaces = places?.data?.places ?? const <LalaPlace>[];
    final hasLivePlaces = apiPlaces.isNotEmpty;
    final effectiveSource = hasLivePlaces ? places?.data?.source : 'db';
    final visibleError = localizedUiMessage(error, uiLanguage);
    final showBundledStartupPlaces = !hasLivePlaces && visibleError == null;
    final displayedError = visibleError == null
        ? null
        : recommendationStatusMessage(
            uiLanguage,
            recoveryPending: recommendationRecoveryPending,
          );
    final allPlaces = hasLivePlaces
        ? apiPlaces
        : showBundledStartupPlaces
        ? _bundledStartupPlaces
        : const <LalaPlace>[];
    final filteredTopPlaces = filterPlaces(allPlaces, selectedCategory);
    final topPlaces = prioritizeClusterMembers(
      filteredTopPlaces,
      focusedClusterMemberIds,
    );
    final tourPlaces = restaurantTourPlaces(allPlaces);
    final topPlace =
        placeById(topPlaces, selectedPlaceId) ?? featuredPlace(topPlaces);
    final activeDocent = docentScript?.data;
    final activeDailyPlan = dailyPlan?.data;
    final currentWeather = publicWeatherOrNull(weather?.data);
    final activeIntervention = intervention?.data;
    final liveSpeechEnabled = isLiveSpeechEnabled(readiness?.data);
    publishLalaSmokeState({
      'buildSha': _buildSha,
      'apiPlacesCount': apiPlaces.length,
      'topPlacesCount': topPlaces.length,
      'usingBundledStartupPlaces': showBundledStartupPlaces,
      'selectedCategory': selectedCategory,
      'locationFallbackNoticeVisible': locationFallbackNoticeVisible,
      'locationManualSelectAvailable':
          locationFallbackNoticeVisible && !locationRequestInFlight,
      'locationRequestInFlight': locationRequestInFlight,
      'locationStartPromptVisible': locationStartPromptVisible,
      'manualLocationOptionCount': manualLocationOptions.length,
      'weatherVisible': currentWeather != null,
      'weatherSource': currentWeather?.source ?? '',
      'weatherHasPm10': currentWeather?.dust.pm10 != null,
      'weatherHasPm25': currentWeather?.dust.pm25 != null,
      'visibleError': visibleError ?? '',
      'displayedError': displayedError ?? '',
      'recommendationRecoveryPending': recommendationRecoveryPending,
      'recommendationRecoveryAttempt': recommendationRecoveryAttempt,
      'mapLevel': mapLevel,
    });
    void selectPlaceById(String placeId) {
      final place = placeById(topPlaces, placeId);
      if (place != null) {
        onSelectPlace(place);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        final compactMapChrome =
            !isWide &&
            (constraints.maxWidth <= 430 || constraints.maxHeight < 760);
        final floatingPillTop = isWide
            ? 264.0
            : compactMapChrome
            ? 242.0
            : 266.0;
        final locationFallbackTop =
            topPlaces.isNotEmpty && recommendationRailExpanded
            ? isWide
                  ? 286.0
                  : compactMapChrome
                  ? 246.0
                  : 282.0
            : isWide
            ? 232.0
            : 220.0;
        final bottomDockHeight = isWide
            ? 218.0
            : constraints.maxHeight < 700
            ? 164.0
            : compactMapChrome
            ? 224.0
            : 238.0;
        final floatingControlsBottom = bottomDockHeight + 16;
        return Stack(
          children: [
            Positioned.fill(
              child: LegacyMapCanvas(
                places: topPlaces,
                selectedPlace: topPlace,
                weather: currentWeather,
                kakaoJavascriptKey: kakaoJavascriptKey,
                language: uiLanguage,
                mapFocusLat: mapFocusLat,
                mapFocusLng: mapFocusLng,
                mapLevel: mapLevel,
                onSelectPlaceId: selectPlaceById,
                onSelectCluster: onSelectCluster,
                onCameraIdle: onCameraIdle,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: TopMapChrome(
                loading: loading,
                language: uiLanguage,
                selectedCategory: selectedCategory,
                onSelectCategory: onSelectCategory,
                onOpenSettings: onOpenSettings,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: isWide ? 76 : 68,
              child: Center(
                child: SizedBox(
                  width: isWide
                      ? math.min(780.0, constraints.maxWidth - 32)
                      : constraints.maxWidth - 32,
                  child: MapPlaceCarouselOverlay(
                    places: topPlaces,
                    source: effectiveSource,
                    language: uiLanguage,
                    selectedPlaceId: topPlace?.placeId,
                    explicitSelectedPlaceId: selectedPlaceId,
                    expanded: recommendationRailExpanded,
                    compact: compactMapChrome,
                    onSelectPlace: onSelectPlace,
                    onReselectSelectedPlace: onClearPlaceSelection,
                    onToggleExpanded: onToggleRecommendationRail,
                  ),
                ),
              ),
            ),
            if (selectedCategory == 'restaurant' && tourPlaces.isNotEmpty)
              Positioned(
                right: 16,
                top: 52,
                child: TourMapPill(
                  places: tourPlaces,
                  language: uiLanguage,
                  onPressed: () => onOpenSheet(ActiveMapSheet.tour),
                ),
              ),
            if (displayedError != null)
              Positioned(
                left: 16,
                right: isWide ? null : 16,
                top: isWide ? 88 : 118,
                child: SizedBox(
                  width: isWide ? 420 : null,
                  child: MapToast(
                    icon: Icons.error_outline,
                    label: displayedError,
                    actionLabel: lalaCopy(
                      uiLanguage,
                      ko: '지금 다시 시도',
                      en: 'Retry now',
                    ),
                    onAction: onRefresh,
                    color: Theme.of(context).colorScheme.errorContainer,
                  ),
                ),
              ),
            if (displayedError == null &&
                locationFallbackNoticeVisible &&
                !locationRequestInFlight)
              Positioned(
                left: 16,
                right: isWide ? null : 16,
                top: locationFallbackTop,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: MapToast(
                      actionKey: const ValueKey('location-fallback-retry'),
                      secondaryActionKey: const ValueKey(
                        'location-manual-select',
                      ),
                      icon: Icons.my_location_outlined,
                      label: lalaCopy(
                        uiLanguage,
                        ko: '현재 위치를 확인해야 추천을 볼 수 있어요',
                        en: 'Location permission is needed for recommendations',
                      ),
                      actionLabel: lalaCopy(uiLanguage, ko: '재시도', en: 'Retry'),
                      onAction: onRetryLocation,
                      secondaryActionLabel: lalaCopy(
                        uiLanguage,
                        ko: '지역 선택',
                        en: 'Choose area',
                      ),
                      onSecondaryAction: onOpenManualLocation,
                      color: Colors.white.withValues(alpha: 0.94),
                    ),
                  ),
                ),
              ),
            if (displayedError == null &&
                activeIntervention?.shouldIntervene == true &&
                !interventionToastDismissed)
              Positioned(
                left: 16,
                right: 16,
                top: isWide ? 92 : 110,
                child: Center(
                  child: InterventionToast(
                    label: interventionToastLabel(
                      activeIntervention!,
                      uiLanguage,
                    ),
                    language: uiLanguage,
                    onOpenPlanner: () => onOpenSheet(ActiveMapSheet.planner),
                    onDismiss: onDismissInterventionToast,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: isWide
                      ? math.min(760.0, constraints.maxWidth - 32)
                      : constraints.maxWidth,
                  child: MapBottomDock(
                    isWide: isWide,
                    places: topPlaces,
                    source: effectiveSource,
                    topPlace: topPlace,
                    uiLanguage: uiLanguage,
                    height: bottomDockHeight,
                    docentScript: activeDocent?.placeId == topPlace?.placeId
                        ? activeDocent?.script
                        : null,
                    docentAudio: docentAudio,
                    docentAction:
                        activeIntervention?.recommendedAction ??
                        (activeDailyPlan?.slots.isEmpty == false
                            ? activeDailyPlan?.slots.first.title
                            : null),
                    audioLoading: audioLoading,
                    audioError: localizedUiMessage(audioError, uiLanguage),
                    canFetchAudio:
                        liveSpeechEnabled &&
                        activeDocent?.placeId == topPlace?.placeId &&
                        hasUsableDocentScript(
                          activeDocent?.script,
                          uiLanguage,
                        ) &&
                        !audioLoading &&
                        topPlace != null &&
                        !detailDocentPlayedPlaceIds.contains(topPlace.placeId),
                    showEvidence: showEvidence,
                    error: displayedError,
                    recommendationRecoveryPending:
                        recommendationRecoveryPending,
                    onFetchAudio: onFetchAudio,
                    onAddToPlan: () => onOpenSheet(ActiveMapSheet.planner),
                    onOpenDetail: () => onOpenSheet(ActiveMapSheet.detail),
                    onRefresh: onRefresh,
                    onToggleEvidence: onToggleEvidence,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: floatingControlsBottom,
              child: Center(
                child: FloatingMapControls(
                  voiceEnabled: voiceEnabled,
                  autoDocentEnabled: autoDocentEnabled,
                  language: uiLanguage,
                  onToggleVoice: onToggleVoice,
                  onToggleAutoDocent: onToggleAutoDocent,
                  onReturnToLocation: onReturnToLocation,
                ),
              ),
            ),
            if (!locationFallbackNoticeVisible)
              Positioned(
                left: 16,
                right: 16,
                top: floatingPillTop,
                child: Center(
                  child: SizedBox(
                    width: isWide
                        ? math.min(760.0, constraints.maxWidth - 32)
                        : constraints.maxWidth - 32,
                    child: MapUtilityControlRow(
                      dailyPlan: activeDailyPlan,
                      weather: currentWeather,
                      language: uiLanguage,
                      onOpenPlanner: () => onOpenSheet(ActiveMapSheet.planner),
                      onOpenWeather: () {
                        onOpenSheet(ActiveMapSheet.weather);
                        onRefreshWeather();
                      },
                    ),
                  ),
                ),
              ),
            if (activeSheet != null)
              Positioned.fill(
                child: MapDraggableSheet(
                  activeSheet: activeSheet!,
                  place: topPlace,
                  places: tourPlaces,
                  weather: currentWeather,
                  language: uiLanguage,
                  loading: loading,
                  intervention: intervention?.data,
                  dailyPlan: dailyPlan?.data,
                  docentScript: docentScript?.data,
                  docentAudio: docentAudio,
                  tourAudio: tourAudio,
                  audioLoading: audioLoading,
                  audioError: localizedUiMessage(audioError, uiLanguage),
                  tourAudioLoading: tourAudioLoading,
                  tourAudioError: localizedUiMessage(
                    tourAudioError,
                    uiLanguage,
                  ),
                  liveSpeechEnabled: liveSpeechEnabled,
                  source: effectiveSource,
                  showEvidence: showEvidence,
                  savedPlaceIds: savedPlaceIds,
                  detailDocentPlayedPlaceIds: detailDocentPlayedPlaceIds,
                  onToggleEvidence: onToggleEvidence,
                  onToggleSavedPlace: onToggleSavedPlace,
                  onAddToPlan: () => onOpenSheet(ActiveMapSheet.planner),
                  onFetchAudio: onFetchAudio,
                  onFetchTourAudio: onFetchTourAudio,
                  onSelectPlace: onSelectPlace,
                  onRefresh: onRefresh,
                  onClose: onCloseSheet,
                ),
              ),
            if (locationStartPromptVisible)
              Positioned.fill(
                child: LocationStartPromptOverlay(
                  language: uiLanguage,
                  onStartLocation: onStartLocation,
                ),
              ),
            if (!locationStartPromptVisible && !locationConsentEnabled)
              Positioned.fill(
                child: LocationConsentOverlay(
                  language: uiLanguage,
                  onOpenSettings: onOpenSettings,
                  onRetryLocation: onRetryLocation,
                ),
              ),
            if (locationRequestInFlight && places == null)
              Positioned.fill(
                child: LocationStartupOverlay(language: uiLanguage),
              ),
          ],
        );
      },
    );
  }
}
