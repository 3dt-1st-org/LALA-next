import 'package:flutter/material.dart';
import '../../auth/auth_controller.dart';
import '../../core/location/lala_location.dart';
import '../../core/location/region_context.dart';
import '../../manual_location_options.dart';
import '../../onboarding_screen.dart';
import '../location/widgets/manual_location_sheet.dart';
import '../preferences/data/travel_preferences_store.dart';
import '../preferences/domain/travel_preferences.dart';
import '../settings/data/privacy_settings_store.dart';
import 'onboarding_state.dart';

/// Adapts the retained local artwork and flow to the shared account stores.
class LocalOnboardingPage extends StatelessWidget {
  const LocalOnboardingPage({
    super.key,
    required this.locationProvider,
    this.authController,
  });
  final LalaLocationProvider locationProvider;
  final LalaAuthController? authController;

  @override
  Widget build(BuildContext context) => OnboardingScreen(
    initialLanguage: switch (OnboardingState.language) {
      'zh-Hans' => 'zh-CN',
      'zh-Hant' => 'zh-TW',
      _ => OnboardingState.language,
    },
    onSignIn: authController?.config.enabled == true
        ? () async {
            await authController!.signIn();
            return authController!.state.authenticated;
          }
        : null,
    onRequestLocation: () async {
      final result = await locationProvider.requestCurrentLocation();
      if (result.status == LalaLocationResultStatus.found &&
          result.location != null) {
        await RegionContextStore.setAndFlush(
          RegionContext.current(
            lat: result.location!.lat,
            lng: result.location!.lng,
          ),
        );
        await PrivacySettingsStore.instance.setLocationRecommendationsEnabled(
          true,
        );
        return OnboardingLocationStatus.granted;
      }
      return result.status == LalaLocationResultStatus.unavailable
          ? OnboardingLocationStatus.unavailable
          : OnboardingLocationStatus.denied;
    },
    onSelectDestination: (language) =>
        showModalBottomSheet<ManualLocationOption>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => ManualLocationSheet(language: language),
        ),
    onComplete: completeLocalOnboarding,
  );
}

Future<void> completeLocalOnboarding(OnboardingResult result) async {
  final store = TravelPreferencesStore.instance;
  await store.ensureLoaded();
  final interests = <TravelInterest>{};
  for (final style in result.travelStyles) {
    interests.addAll(switch (style) {
      'history' => {TravelInterest.history},
      'food' => {TravelInterest.localFood},
      'nature' => {TravelInterest.nature},
      'kculture' => {TravelInterest.shopping},
      'market' => {TravelInterest.market},
      _ => <TravelInterest>{},
    });
  }
  await store.save(
    store.value.copyWith(
      interests: interests,
      docentAutoplay: result.autoDocent,
      narrationSpeed: result.playbackSpeed,
    ),
  );
  OnboardingState.selectTouristType(
    result.country == 'KR'
        ? OnboardingTouristType.localTourist
        : OnboardingTouristType.foreignTourist,
  );
  OnboardingState.selectLanguage(switch (result.language) {
    'zh-CN' => 'zh-Hans',
    'zh-TW' => 'zh-Hant',
    _ => result.language,
  });
  if (result.destination != null) {
    await RegionContextStore.setAndFlush(
      RegionContext.manual(result.destination!),
    );
  }
  await OnboardingState.completeAndFlush();
}
