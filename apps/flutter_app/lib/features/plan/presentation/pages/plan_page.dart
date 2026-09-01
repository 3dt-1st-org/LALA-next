// ONMU P1: 플랜 탭 본문 — 오늘의 일정(createDailyPlan) 표시.
// LalaAppConfig.fromEnvironment() + LalaApiBackend 로 백엔드를 구성하고,
// GeolocatorLalaLocationProvider 로 현재 위치를 잡아 일정을 생성한다.
// PlannerOverviewCard + PlanSlotTile 리스트 + InterventionToast 를 재사용.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_copy.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_state.dart';
import 'package:lala_next_app/features/home/home_view_helpers.dart'
    show interventionToastLabel;
import 'package:lala_next_app/features/intervention/widgets/intervention_toast.dart';
import 'package:lala_next_app/features/location/widgets/default_region_indicator.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/planner/planner_helpers.dart';
import 'package:lala_next_app/features/planner/spend_band_helpers.dart';
import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';
import 'package:lala_next_app/features/planner/widgets/planner_loading_card.dart';
import 'package:lala_next_app/features/planner/widgets/planner_overview_card.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';
import 'package:lala_next_app/shared/widgets/lala_skeleton.dart';

/// 플랜 탭: 하루 일정을 생성해 타임라인으로 보여준다.
class PlanPage extends StatefulWidget {
  const PlanPage({
    this.locationProvider,
    this.backendFactory,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.docentExperienceController,
    super.key,
  });

  /// 테스트 주입용 위치 프로바이더(기본 = Geolocator 하이브리드).
  final LalaLocationProvider? locationProvider;

  /// 테스트 주입용 백엔드 팩토리(기본 = LalaApiBackend).
  final LalaBackendFactory? backendFactory;

  /// API/좌표 config 주입용 선택적 시드(기본 = 컴파일타임 환경).
  /// UI 언어는 persisted [OnboardingState] 가 유일한 권위다.
  final LalaAppConfig initialConfig;

  /// 이슈 #120 §6: 앱 루트 단일 도슨트 경험 컨트롤러(선택 — 라우터가 주입).
  /// null 이면 '전체 듣기'/슬롯 재생 버튼을 만들지 않는다.
  final DocentExperienceController? docentExperienceController;

  @override
  State<PlanPage> createState() => _PlanPageState();
}

// Per-state honesty (playbook §2/§13.5): five distinct outcomes, never
// conflated. `loaded` is a real timeline (never a skeleton); `empty` is a
// genuine no-data result (never shares a message with a failure); `unavailable`
// is "could not reach the service" (network/timeout); `error` is "the service
// responded with an error". An API failure is never shown with the same copy as
// the empty no-data state.
enum _PlanLoadStatus { loading, loaded, empty, unavailable, error }

class _PlanPageState extends State<PlanPage> {
  late LalaAppConfig _baseConfig;
  late LalaAppConfig _config;
  late final LalaLocationProvider _locationProvider;
  late final LalaBackendFactory _backendFactory;
  late LalaBackend _backend;

  _PlanLoadStatus _status = _PlanLoadStatus.loading;
  LalaDailyPlan? _dailyPlan;
  LalaIntervention? _intervention;
  bool _interventionDismissed = false;

  // Active region context retained across onboarding/tabs (null = disclosed
  // default region). Seeded from the shared store so a manual/current choice
  // made elsewhere drives this tab's plan calls.
  RegionContext? _region = RegionContextStore.current;

  // Monotonic load token. A store-driven reload or a manual retry can start
  // while a device-location request is still in flight; only the newest load may
  // write results so a late response cannot clobber a newer context.
  int _loadGeneration = 0;
  late final VoidCallback _onRegionChanged;
  late final VoidCallback _onLanguageChanged;
  // Cross-tab plan SSOT (§13.4): adopts a timeline published by the map tab so
  // both tabs show the same plan without the plan tab refetching.
  late final VoidCallback _onPlanChanged;
  // V5-B VISIT: rebuild when a check-in toggles anywhere so the planned↔visited
  // badge reflects the persisted state in SlotVisitStore.
  late final VoidCallback _onVisitsChanged;

  // 안내문은 unavailable/error 상태에서만 사용. empty(no-data) 는 별도 copy.
  String _failureMessage = '';

  @override
  void initState() {
    super.initState();
    _baseConfig = widget.initialConfig.copyWith(lang: OnboardingState.language);
    _config = _baseConfig;
    _locationProvider =
        widget.locationProvider ?? const GeolocatorLalaLocationProvider();
    _backendFactory = widget.backendFactory ?? LalaApiBackend.new;
    _backend = _backendFactory(_config);
    // React to a region choice made in onboarding or on another tab: rebuild the
    // backend from the shared coordinates WITHOUT re-requesting device location,
    // so a manual choice cannot be overwritten by a later location fetch.
    _onRegionChanged = () {
      if (!mounted) {
        return;
      }
      final next = RegionContextStore.current;
      // Ignore our own publishes and no-op notifications.
      if (next == _region) {
        return;
      }
      _reloadFromStore(next);
    };
    RegionContextStore.listenable.addListener(_onRegionChanged);
    _onLanguageChanged = () {
      if (!mounted) {
        return;
      }
      final next = OnboardingState.language;
      if (next == _language) {
        return;
      }
      _reloadForLanguage(next);
    };
    OnboardingState.languageListenable.addListener(_onLanguageChanged);
    // Plan: adopt a non-null timeline published by another tab (e.g. the map tab's
    // createDailyPlan). No-op-skip our own publishes (same instance) and external
    // clears (null) so our view is never wiped by another tab's transient null.
    _onPlanChanged = () {
      if (!mounted) {
        return;
      }
      final next = PlanContextStore.current;
      if (next == null || next == _dailyPlan) {
        return;
      }
      setState(() {
        _dailyPlan = next;
        _failureMessage = '';
        _status = _visibleSlotsFrom(next).isEmpty
            ? _PlanLoadStatus.empty
            : _PlanLoadStatus.loaded;
      });
    };
    PlanContextStore.listenable.addListener(_onPlanChanged);
    // V5-B VISIT: react to check-ins toggled on this or any other tab.
    _onVisitsChanged = () {
      if (!mounted) {
        return;
      }
      setState(() {});
    };
    SlotVisitStore.listenable.addListener(_onVisitsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    RegionContextStore.listenable.removeListener(_onRegionChanged);
    OnboardingState.languageListenable.removeListener(_onLanguageChanged);
    PlanContextStore.listenable.removeListener(_onPlanChanged);
    SlotVisitStore.listenable.removeListener(_onVisitsChanged);
    _backend.close();
    super.dispose();
  }

  String get _language => _config.lang;

  // True when the plan is built from the disclosed default region (no real
  // current/manual context). The UI must badge this honestly.
  bool get _regionIsDefault => _region == null;

  List<LalaPlanSlot> get _visibleSlots => _visibleSlotsFrom(_dailyPlan);

  List<LalaPlanSlot> _visibleSlotsFrom(LalaDailyPlan? dailyPlan) {
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return slots
        .where((slot) => hasVisiblePlanSlot(slot, _language))
        .toList(growable: false);
  }

  bool get _shouldShowInterventionToast =>
      _intervention != null &&
      _intervention!.shouldIntervene &&
      !_interventionDismissed;

  // V3-D: 트리터 종류를 한 줄 배지로 표시(KO/EN 배타). null/알 수 없음은 배지 없음.
  String? _interventionTriggerBadge(LalaIntervention intervention) {
    switch (intervention.triggerType) {
      case 'closure_detected':
        return lalaCopyMulti(
          _language,
          ko: '폐업 의심',
          en: 'Possible closure',
          ja: '休業の可能性',
          zhHans: '疑似停业',
          zhHant: '疑似停業',
        );
      case 'bad_weather_and_closure':
        return lalaCopyMulti(
          _language,
          ko: '날씨 + 폐업',
          en: 'Weather + closure',
          ja: '気象 + 休業',
          zhHans: '天气 + 停业',
          zhHant: '天氣 + 停業',
        );
      case 'bad_weather':
        return lalaCopyMulti(
          _language,
          ko: '날씨 변화',
          en: 'Weather change',
          ja: '気象の変化',
          zhHans: '天气变化',
          zhHant: '天氣變化',
        );
      default:
        return null;
    }
  }

  // 대체 장소(swap) 버튼 라벨. alternativeSlot 이 있을 때만. 위조 금지 — null 이면 null.
  String? _interventionSwapLabel(LalaIntervention intervention) {
    final alt = intervention.alternativeSlot;
    if (alt == null) {
      return null;
    }
    final name = alt.place != null
        ? placeDisplayName(alt.place!, _language)
        : alt.title;
    return lalaCopyMulti(
      _language,
      ko: '대체 ▸ $name',
      en: 'Swap ▸ $name',
      ja: '代替 ▸ $name',
      zhHans: '替换 ▸ $name',
      zhHant: '替換 ▸ $name',
    );
  }

  // swap 탭 — alternativeSlot 의 장소를 노출만 한다(스낵바). PlanContextStore 의
  // 슬롯 치환은 별도 후속 작업(V3-D 데이터 범위 밖). 위조/변이 없다.
  void _onSwapAlternative(LalaPlanSlot alternative) {
    if (!mounted) {
      return;
    }
    final name = alternative.place != null
        ? placeDisplayName(alternative.place!, _language)
        : alternative.title;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          lalaCopyMulti(
            _language,
            ko: '대체 장소 $name 을(를) 확인해 보세요.',
            en: 'Check the alternative: $name.',
            ja: '代替スポット $name をご確認ください。',
            zhHans: '请查看替代地点：$name。',
            zhHant: '請查看替代地點：$name。',
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _status = _PlanLoadStatus.loading;
      _failureMessage = '';
      _interventionDismissed = false;
    });

    var lat = _region?.lat ?? _baseConfig.lat;
    var lng = _region?.lng ?? _baseConfig.lng;
    // Why: only resolve live geolocation when no real context exists yet. A
    // context already in the store (a manual choice retained from onboarding, or
    // a current fix from another tab) is a deliberate selection that this tab's
    // initial device-location request must not overwrite. After-mount changes
    // arrive via _reloadFromStore, which never requests location.
    if (_region == null) {
      try {
        final result = await _locationProvider.requestCurrentLocation();
        // Stale guard: a store-driven reload or retry may have started while this
        // device-location request was in flight — discard so a late response
        // cannot overwrite a newer context.
        if (generation != _loadGeneration || !mounted) {
          return;
        }
        if (result.status == LalaLocationResultStatus.found &&
            result.location != null) {
          lat = result.location!.lat;
          lng = result.location!.lng;
          _region = RegionContext.current(lat: lat, lng: lng);
          RegionContextStore.set(_region);
        }
        // denied / permanentlyDenied / unavailable: 기존 컨텍스트(수동 선택 또는
        // 기본 지역)를 유지. 절대 임의의 위치를 끼워 넣지 않는다.
      } on Object {
        // 위치 미확정 시 현재 컨텍스트(수동 선택 또는 기본 지역)를 유지.
        if (generation != _loadGeneration || !mounted) {
          return;
        }
      }
    }

    _config = _baseConfig.copyWith(lat: lat, lng: lng);
    _backend.close();
    _backend = _backendFactory(_config);
    await _fetchPlan(generation);
  }

  /// 공유 store 의 컨텍스트로 백엔드를 재구성한다. 기기 위치를 다시 요청하지 않으므로,
  /// 온보딩/다른 탭의 수동 선택이 뒤늦은 위치 응답에 덮어씌워지지 않는다.
  void _reloadFromStore(RegionContext? context) {
    final generation = ++_loadGeneration;
    setState(() {
      _region = context;
      _status = _PlanLoadStatus.loading;
      _failureMessage = '';
      _interventionDismissed = false;
    });
    final lat = context?.lat ?? _baseConfig.lat;
    final lng = context?.lng ?? _baseConfig.lng;
    _config = _baseConfig.copyWith(lat: lat, lng: lng);
    _backend.close();
    _backend = _backendFactory(_config);
    _fetchPlan(generation);
  }

  /// Rebuilds the plan request and visible copy from the persisted language
  /// SSOT while retaining the active region and skipping geolocation.
  void _reloadForLanguage(String language) {
    final generation = ++_loadGeneration;
    setState(() {
      _baseConfig = _baseConfig.copyWith(lang: language);
      _config = _config.copyWith(lang: language);
      _status = _PlanLoadStatus.loading;
      _failureMessage = '';
      _interventionDismissed = false;
    });
    _backend.close();
    _backend = _backendFactory(_config);
    _fetchPlan(generation);
  }

  Future<void> _fetchPlan(int generation) async {
    // 일정(필수)과 개입(intervention, 부가)을 병렬로 조회한다.
    // 일정 라인은 실패 사유를 버리지 않고 캡처 — unavailable(도달 실패)과
    // error(오류 응답)을 구분해 서로 다른 안내문을 내기 위함. 개입은 부가이므로
    // 여전히 null 로 흡수한다.
    Future<({LalaDailyPlan? plan, Object? failure})> loadPlan() async {
      try {
        return (plan: (await _backend.createDailyPlan()).data, failure: null);
      } on Object catch (failure) {
        return (plan: null, failure: failure);
      }
    }

    Future<LalaIntervention?> loadIntervention() async {
      try {
        return (await _backend.getIntervention()).data;
      } on Object {
        return null;
      }
    }

    final (loaded, intervention) = await (loadPlan(), loadIntervention()).wait;
    final plan = loaded.plan;

    if (generation != _loadGeneration || !mounted) {
      return;
    }
    if (plan == null) {
      // Why: the client throws LalaApiException for both unreachable
      // (NETWORK_ERROR/REQUEST_TIMEOUT/statusCode 0) and responded-error
      // (HTTP_4xx/5xx, ok:false envelope). Splitting on the code keeps an API
      // failure's copy distinct from the empty no-data message and from a
      // reachability failure.
      final status = _planFailureStatus(loaded.failure);
      setState(() {
        _failureMessage = _failureCopy(status);
        _status = status;
      });
      return;
    }
    setState(() {
      _dailyPlan = plan;
      _intervention = intervention;
      // loaded vs empty: a real plan with at least one visible slot is never a
      // skeleton; an empty visible list is a genuine no-data result, not a
      // failure.
      _status = _visibleSlotsFrom(plan).isEmpty
          ? _PlanLoadStatus.empty
          : _PlanLoadStatus.loaded;
    });
    // Cross-tab plan SSOT (§13.4): publish the generated plan so the map tab and
    // any other reader share this timeline instead of fetching independently.
    PlanContextStore.set(plan);
  }

  /// 도달 실패(unavailable)와 오류 응답(error)을 예외 코드로 구분한다.
  _PlanLoadStatus _planFailureStatus(Object? failure) {
    if (failure is LalaApiException) {
      final code = failure.code;
      final networkUnreachable =
          code == 'NETWORK_ERROR' ||
          code == 'REQUEST_TIMEOUT' ||
          failure.statusCode == 0;
      return networkUnreachable
          ? _PlanLoadStatus.unavailable
          : _PlanLoadStatus.error;
    }
    // 비-API 예외(직렬화/파싱 등)는 서비스 도달과 무관하므로 error 로 분류.
    return _PlanLoadStatus.error;
  }

  String _failureCopy(_PlanLoadStatus status) {
    return switch (status) {
      _PlanLoadStatus.unavailable => lalaCopyMulti(
        _language,
        ko: '일시적으로 서버에 연결할 수 없어요. 네트워크를 확인 후 다시 시도해 주세요.',
        en: 'Could not reach the service. Check your connection and try again.',
        ja: 'サーバーに一時的に接続できません。ネットワークを確認してもう一度お試しください。',
        zhHans: '暂时无法连接服务器，请检查网络后重试。',
        zhHant: '暫時無法連線伺服器，請檢查網路後重試。',
      ),
      _PlanLoadStatus.error => lalaCopyMulti(
        _language,
        ko: '일정을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
        en: 'Could not load the daily plan. Please try again shortly.',
        ja: 'プランを読み込めませんでした。しばらくしてからもう一度お試しください。',
        zhHans: '无法加载行程，请稍后重试。',
        zhHant: '無法載入行程，請稍後重試。',
      ),
      _PlanLoadStatus.loading ||
      _PlanLoadStatus.loaded ||
      _PlanLoadStatus.empty => '',
    };
  }

  String _todayLabel() {
    final now = DateTime.now();
    // V6(계약 §6): ko 는 기존 KO 형식, en 은 ISO+EN 요일, ja/zh 는 ISO+현지 요일.
    switch (normalizeLalaLanguage(_language)) {
      case 'ko':
        final weekdaysKo = <String>['월', '화', '수', '목', '금', '토', '일'];
        return '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 '
            '${now.day.toString().padLeft(2, '0')}일 ${weekdaysKo[now.weekday - 1]}';
      case 'ja':
        const weekdaysJa = ['月', '火', '水', '木', '金', '土', '日'];
        return '${now.year}-${now.month.toString().padLeft(2, '0')}'
            '-${now.day.toString().padLeft(2, '0')} ${weekdaysJa[now.weekday - 1]}';
      case 'zh-Hans':
        const weekdaysHans = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        return '${now.year}-${now.month.toString().padLeft(2, '0')}'
            '-${now.day.toString().padLeft(2, '0')} ${weekdaysHans[now.weekday - 1]}';
      case 'zh-Hant':
        const weekdaysHant = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
        return '${now.year}-${now.month.toString().padLeft(2, '0')}'
            '-${now.day.toString().padLeft(2, '0')} ${weekdaysHant[now.weekday - 1]}';
      case 'en':
        final weekdaysEn = <String>[
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ];
        return '${now.year}-${now.month.toString().padLeft(2, '0')}'
            '-${now.day.toString().padLeft(2, '0')} ${weekdaysEn[now.weekday - 1]}';
    }
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlanHeader(
              title: lalaCopyMulti(
                _language,
                ko: '오늘 일정',
                en: 'Today\'s Plan',
                ja: '今日のプラン',
                zhHans: '今日计划',
                zhHant: '今日計畫',
              ),
              dateLabel: _todayLabel(),
              language: _language,
              onCalendar: _load,
            ),
            if (_regionIsDefault) DefaultRegionIndicator(language: _language),
            if (_shouldShowInterventionToast)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: InterventionToast(
                  label: interventionToastLabel(_intervention!, _language),
                  language: _language,
                  triggerBadge: _interventionTriggerBadge(_intervention!),
                  swapLabel: _interventionSwapLabel(_intervention!),
                  onSwap: _intervention!.alternativeSlot != null
                      ? () => _onSwapAlternative(_intervention!.alternativeSlot!)
                      : null,
                  regenerateLabel: lalaCopyMulti(
                    _language,
                    ko: '일정 다시 짜기',
                    en: 'Regenerate',
                    ja: 'プランを作り直す',
                    zhHans: '重新生成',
                    zhHant: '重新產生',
                  ),
                  onRegenerate: _load,
                  noAlternativeLabel: _intervention!.alternativeSlot == null
                      ? lalaCopyMulti(
                          _language,
                          ko: '지금은 대체 장소가 없어요.',
                          en: 'No alternative right now.',
                          ja: '現在代替スポットはありません。',
                          zhHans: '暂时没有替代地点。',
                          zhHant: '暫時沒有替代地點。',
                        )
                      : null,
                  onOpenPlanner: () {
                    if (!mounted) {
                      return;
                    }
                    setState(() => _interventionDismissed = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                          lalaCopyMulti(
                            _language,
                            ko: '일정을 확인해 보세요.',
                            en: 'Review today\'s plan below.',
                            ja: '下のプランをご確認ください。',
                            zhHans: '请在下方查看今日计划。',
                            zhHant: '請在下方查看今日計畫。',
                          ),
                        ),
                      ),
                    );
                  },
                  onDismiss: () {
                    if (mounted) {
                      setState(() => _interventionDismissed = true);
                    }
                  },
                ),
              ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_status) {
      case _PlanLoadStatus.loading:
        return _PlanLoadingView(language: _language);
      case _PlanLoadStatus.unavailable:
        return _PlanFailureView(
          key: const ValueKey('plan-unavailable-view'),
          kind: _PlanFailureKind.unavailable,
          message: _failureMessage,
          language: _language,
          onRetry: _load,
        );
      case _PlanLoadStatus.error:
        return _PlanFailureView(
          key: const ValueKey('plan-error-view'),
          kind: _PlanFailureKind.error,
          message: _failureMessage,
          language: _language,
          onRetry: _load,
        );
      case _PlanLoadStatus.empty:
        return _PlanEmptyView(language: _language, onRegenerate: _load);
      case _PlanLoadStatus.loaded:
        return _PlanContent(
          dailyPlan: _dailyPlan,
          visibleSlots: _visibleSlots,
          language: _language,
          loading: false,
          onRegenerate: _load,
          docentController: widget.docentExperienceController,
        );
    }
  }
}

/// 헤더(제목 + 오늘 날짜 + 달력 액션). 달력 아이콘은 44dp 타겟 + 시맨틱/툴팁.
class _PlanHeader extends StatelessWidget {
  const _PlanHeader({
    required this.title,
    required this.dateLabel,
    required this.language,
    required this.onCalendar,
  });

  final String title;
  final String dateLabel;
  final String language;

  /// 달력/캘린더 액션 — 오늘 일정을 다시 불러온다.
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: lalaCopyMulti(
              language,
              ko: '달력',
              en: 'Calendar',
              ja: 'カレンダー',
              zhHans: '日历',
              zhHant: '日曆',
            ),
            onPressed: onCalendar,
            icon: const Icon(Icons.calendar_today_rounded),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

/// 로딩 본문: '준비 중' 카드 정확히 한 장 + 중성 타임라인 스켈레톤(중복 카드 금지).
class _PlanLoadingView extends StatelessWidget {
  const _PlanLoadingView({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    // 시맨틱: 로딩 상태를 화면 읽기 사용자에게 알린다(진행률/단계 주장 없이).
    return Semantics(
      container: true,
      label: lalaCopyMulti(
        language,
        ko: '일정을 준비하고 있어요',
        en: 'Preparing your plan',
        ja: 'プランを準備しています',
        zhHans: '正在准备您的计划',
        zhHant: '正在準備您的計畫',
      ),
      child: ListView(
        key: const ValueKey('plan-loading-view'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          PlannerLoadingCard(language: language),
          const SizedBox(height: 16),
          const _PlannerTimelineSkeleton(),
        ],
      ),
    );
  }
}

/// 일정 응답 대기 중 타임라인 스켈레톤(3 슬롯). 시간/순서/내용은 발명하지 않는다.
class _PlannerTimelineSkeleton extends StatelessWidget {
  const _PlannerTimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('plan-timeline-skeleton'),
      children: List<Widget>.generate(3, (index) {
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const <Widget>[
              LalaSkeleton(width: 48, height: 14, radius: 7),
              SizedBox(width: 12),
              Expanded(child: LalaSkeleton(height: 40, radius: 8)),
            ],
          ),
        );
      }),
    );
  }
}

/// 실패 본문(unavailable / error). 두 상태는 서로 다른 아이콘·카피로 구분되며,
/// 빈 상태(no-data)의 카피와 절대 겹치지 않는다. 색상만으로 상태를 알리지 않도록
/// 아이콘 + 텍스트 쌍을 항상 함께 표시한다(§13.5 접근성).
enum _PlanFailureKind { unavailable, error }

class _PlanFailureView extends StatelessWidget {
  const _PlanFailureView({
    super.key,
    required this.kind,
    required this.message,
    required this.language,
    required this.onRetry,
  });

  final _PlanFailureKind kind;
  final String message;
  final String language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isUnavailable = kind == _PlanFailureKind.unavailable;
    // 아이콘과 색상을 함께 써 색상 단독 신호를 피한다.
    final icon = isUnavailable
        ? Icons.wifi_off_rounded
        : Icons.error_outline_rounded;
    final accent = isUnavailable
        ? const Color(0xFF475569)
        : const Color(0xFFB45309);
    final retryLabel = lalaCopyMulti(
      language,
      ko: '다시 시도',
      en: 'Retry',
      ja: '再試行',
      zhHans: '重试',
      zhHant: '重試',
    );
    // 시맨틱: 화면 읽기 사용자에게 상태 종류까지 전달.
    final semanticsLabel = lalaCopyMulti(
      language,
      ko: isUnavailable ? '서버 연결 불가. $message' : '일정 불러오기 실패. $message',
      en: isUnavailable
          ? 'Service unreachable. $message'
          : 'Failed to load plan. $message',
      ja: isUnavailable
          ? 'サーバーに接続できません。$message'
          : 'プランの読み込みに失敗しました。$message',
      zhHans: isUnavailable ? '无法连接服务器。$message' : '加载行程失败。$message',
      zhHant: isUnavailable ? '無法連線伺服器。$message' : '載入行程失敗。$message',
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: accent),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: semanticsLabel,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 최소 44dp 터치 타겟: 버튼 기본 최소 높이를 보장한다.
            _MinTouchTarget(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2B6CB0),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 빈 상태(no-data): 일정은 정상 로드되었으나 표시할 슬롯이 없다. 실패 카피와
/// 구분되는 고유 안내문을 쓰며, '준비 중' 로딩 상태와도 섞이지 않는다.
class _PlanEmptyView extends StatelessWidget {
  const _PlanEmptyView({required this.language, required this.onRegenerate});

  final String language;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final message = lalaCopyMulti(
      language,
      // Why: the plan already loaded — an empty slot list is an empty result,
      // not a "preparing" or failure state. Copy is distinct from both the
      // loading card and any failure message.
      ko: '표시할 일정이 없어요.',
      en: 'No plan slots to show.',
      ja: '表示できるプランがありません。',
      zhHans: '暂无可显示的行程。',
      zhHant: '暫無可顯示的行程。',
    );
    final actionLabel = lalaCopyMulti(
      language,
      ko: '일정 다시 만들기',
      en: 'Regenerate plan',
      ja: 'プランを作り直す',
      zhHans: '重新生成计划',
      zhHant: '重新產生計畫',
    );
    final semanticsLabel = lalaCopyMulti(
      language,
      ko: '빈 일정. $message',
      en: 'Empty plan. $message',
      ja: '空のプラン。$message',
      zhHans: '空行程。$message',
      zhHant: '空行程。$message',
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyPlaceState(language: language),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: semanticsLabel,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _MinTouchTarget(
              child: OutlinedButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2B6CB0),
                  side: const BorderSide(color: Color(0xFFB9D4F3)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 일정 본문(개요 카드 + 실제 슬롯 리스트). 로드된 상태 전용 — 빈/실패 분기는
/// _buildBody 에서 별도 위젯으로 분리되었다.
class _PlanContent extends StatelessWidget {
  const _PlanContent({
    required this.dailyPlan,
    required this.visibleSlots,
    required this.language,
    required this.loading,
    required this.onRegenerate,
    this.docentController,
  });

  final LalaDailyPlan? dailyPlan;
  final List<LalaPlanSlot> visibleSlots;
  final String language;
  final bool loading;
  final VoidCallback onRegenerate;

  /// 이슈 #120 §6: 일정 도슨트 진입(선택). null 이면 관련 버튼을 만들지 않는다.
  final DocentExperienceController? docentController;

  // 이 큐가 현재 재생 중인 큐인지 — placeId 순서가 정확히 같을 때만.
  bool _isCurrentQueue(DocentExperienceState state, List<LalaPlace> places) {
    if (!state.queueActive || state.queue.length != places.length) {
      return false;
    }
    for (var i = 0; i < places.length; i++) {
      if (state.queue[i].placeId != places[i].placeId) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final weather = dailyPlan?.weather;
    // 이슈 #120 §6: 큐 순서 = 보이는 슬롯 순서 그대로(장소 없는 슬롯은 건너뛴다).
    final queuePlaces = <LalaPlace>[
      for (final slot in visibleSlots)
        if (slot.place != null) slot.place!,
    ];
    return ListView(
      key: const ValueKey('plan-content'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: PlannerOverviewCard(
              language: language,
              weather: weather,
              dailyPlan: dailyPlan,
              visibleSlotCount: visibleSlots.length,
              loading: loading,
              onRegenerate: onRegenerate,
            ),
          ),
        ),
        // 이슈 #120 §6: '전체 도슨트 듣기' — 개요 바로 아래. 같은 큐가 재생 중이면
        // 정지로 전환(재탭 재시작이 아니라 정직한 stop).
        if (docentController != null && queuePlaces.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ValueListenableBuilder<DocentExperienceState>(
              valueListenable: docentController!.state,
              builder: (
                BuildContext context,
                DocentExperienceState state,
                Widget? _,
              ) {
                final active = _isCurrentQueue(state, queuePlaces);
                return _MinTouchTarget(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('plan-docent-play-all'),
                      onPressed: () {
                        if (active) {
                          unawaited(docentController!.stop());
                        } else {
                          unawaited(docentController!.playQueue(queuePlaces));
                        }
                      },
                      icon: Icon(
                        active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 20,
                        color: const Color(0xFFC87F11),
                      ),
                      label: Text(
                        active
                            ? docentStopSemanticLabel(language)
                            : docentPlayAllLabel(language),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF744210),
                        side: const BorderSide(color: Color(0xFFF5C842)),
                        backgroundColor: const Color(0xFFFFFBEB),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        ...visibleSlots.map((slot) {
          // V5-B VISIT/SPEND: per-slot visit status (persisted in SlotVisitStore)
          // and offline category-band estimate. planDate is the UTC date key
          // (contract A1/D1: one plan per user per day).
          final planDate = utcPlanDate();
          final band = spendBandFor(slot, language);
          return Padding(
            key: ValueKey('plan-slot-${slot.place?.placeId ?? slot.period}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: PlanSlotTile(
              slot: slot,
              language: language,
              onSelectPlace: (_) {
                // P1: 플랜 탭 내 별도 상세 화면은 아직 연결되지 않았다.
                // 탭 피드백으로 새로고침 없이 토스트로 장소명만 확인한다.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text(
                      lalaCopyMulti(
                        language,
                        ko: '지도 탭에서 동선을 확인해 보세요.',
                        en: 'Check the route on the Map tab.',
                        ja: '地図タブでルートをご確認ください。',
                        zhHans: '请在地图标签页查看路线。',
                        zhHant: '請在地圖分頁查看路線。',
                      ),
                    ),
                  ),
                );
              },
              visitStatus: SlotVisitStore.statusFor(planDate, slot.period),
              onToggleVisit:
                  () => SlotVisitStore.toggle(planDate, slot.period),
              spendBand: band,
              spendUnavailable: band == null,
              onPlayDocent: docentController == null || slot.place == null
                  ? null
                  : () => unawaited(
                      docentController!.playPlace(slot.place!),
                    ),
            ),
          );
        }),
      ],
    );
  }
}

/// 접근성(§13.5): 버튼의 최소 터치 타겟(44dp)을 보장한다. 버튼 자체의
/// minimumSize 로 충분하더라도, 인접 여백이 좁은 컨테이너 안에서 타겟이
/// 찌그러지지 않도록 한 번 더 44dp 높이를 고정한다.
class _MinTouchTarget extends StatelessWidget {
  const _MinTouchTarget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: child,
    );
  }
}

/// V5-B: today's UTC date as the plan key `YYYY-MM-DD` (contract A1/D1 — one plan
/// per user per day, UTC date key). Used to scope visit statuses in SlotVisitStore.
String utcPlanDate() {
  final utc = DateTime.now().toUtc();
  return '${utc.year.toString().padLeft(4, '0')}'
      '-${utc.month.toString().padLeft(2, '0')}'
      '-${utc.day.toString().padLeft(2, '0')}';
}
