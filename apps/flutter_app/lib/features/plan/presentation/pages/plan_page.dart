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
import 'package:lala_next_app/features/home/home_view_helpers.dart'
    show interventionToastLabel;
import 'package:lala_next_app/features/intervention/widgets/intervention_toast.dart';
import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/planner/planner_helpers.dart';
import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';
import 'package:lala_next_app/features/planner/widgets/planner_loading_card.dart';
import 'package:lala_next_app/features/planner/widgets/planner_overview_card.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// 플랜 탭: 하루 일정을 생성해 타임라인으로 보여준다.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

enum _PlanLoadStatus { loading, data, error }

class _PlanPageState extends State<PlanPage> {
  late final LalaAppConfig _baseConfig;
  late LalaAppConfig _config;
  late final LalaLocationProvider _locationProvider;
  late LalaBackend _backend;

  _PlanLoadStatus _status = _PlanLoadStatus.loading;
  LalaDailyPlan? _dailyPlan;
  LalaIntervention? _intervention;
  bool _interventionDismissed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseConfig = LalaAppConfig.fromEnvironment();
    _config = _baseConfig;
    _locationProvider = const GeolocatorLalaLocationProvider();
    _backend = LalaApiBackend(_config);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _backend.close();
    super.dispose();
  }

  String get _language => _config.lang;

  List<LalaPlanSlot> get _visibleSlots {
    final slots = _dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return slots
        .where((slot) => hasVisiblePlanSlot(slot, _language))
        .toList(growable: false);
  }

  bool get _shouldShowInterventionToast =>
      _intervention != null &&
      _intervention!.shouldIntervene &&
      !_interventionDismissed;

  Future<void> _load() async {
    setState(() {
      _status = _PlanLoadStatus.loading;
      _error = null;
      _interventionDismissed = false;
    });

    var lat = _baseConfig.lat;
    var lng = _baseConfig.lng;
    try {
      final result = await _locationProvider.requestCurrentLocation();
      if (result.status == LalaLocationResultStatus.found &&
          result.location != null) {
        lat = result.location!.lat;
        lng = result.location!.lng;
      }
    } on Object {
      // 위치 미확정 시 기본 위치(LalaAppConfig)로 폴백.
    }

    _config = _baseConfig.copyWith(lat: lat, lng: lng);
    _backend.close();
    _backend = LalaApiBackend(_config);

    // 일정(필수)과 개입(intervention, 부가)을 병렬로 조회한다.
    // 각 라인은 독립된 try/catch 로 실패를 null 로 흡수한다.
    Future<LalaDailyPlan?> loadPlan() async {
      try {
        return (await _backend.createDailyPlan()).data;
      } on Object {
        return null;
      }
    }

    Future<LalaIntervention?> loadIntervention() async {
      try {
        return (await _backend.getIntervention()).data;
      } on Object {
        return null;
      }
    }

    final (plan, intervention) = await (loadPlan(), loadIntervention()).wait;

    if (!mounted) {
      return;
    }
    if (plan == null) {
      setState(() {
        _error = _fallbackErrorMessage();
        _status = _PlanLoadStatus.error;
      });
      return;
    }
    setState(() {
      _dailyPlan = plan;
      _intervention = intervention;
      _status = _PlanLoadStatus.data;
    });
  }

  String _fallbackErrorMessage() {
    return lalaCopy(
      _language,
      ko: '일정을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
      en: 'Could not load the daily plan. Please try again shortly.',
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    final weekdaysKo = <String>['월', '화', '수', '목', '금', '토', '일'];
    final weekdaysEn = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    if (isLalaEnglish(_language)) {
      return '${now.year}-${now.month.toString().padLeft(2, '0')}'
          '-${now.day.toString().padLeft(2, '0')} ${weekdaysEn[now.weekday - 1]}';
    }
    return '${now.year}년 ${now.month.toString().padLeft(2, '0')}월 '
        '${now.day.toString().padLeft(2, '0')}일 ${weekdaysKo[now.weekday - 1]}';
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
              title: lalaCopy(_language, ko: '오늘 일정', en: 'Today\'s Plan'),
              dateLabel: _todayLabel(),
            ),
            if (_shouldShowInterventionToast)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: InterventionToast(
                  label: interventionToastLabel(_intervention!, _language),
                  language: _language,
                  onOpenPlanner: () {
                    if (!mounted) {
                      return;
                    }
                    setState(() => _interventionDismissed = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content: Text(
                          lalaCopy(
                            _language,
                            ko: '일정을 확인해 보세요.',
                            en: 'Review today\'s plan below.',
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
      case _PlanLoadStatus.error:
        return _PlanErrorView(message: _error!, onRetry: _load);
      case _PlanLoadStatus.data:
        return _PlanContent(
          dailyPlan: _dailyPlan,
          visibleSlots: _visibleSlots,
          language: _language,
          loading: false,
          onRegenerate: _load,
        );
    }
  }
}

/// 헤더(제목 + 오늘 날짜 + 새로고침).
class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.title, required this.dateLabel});

  final String title;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
          Icon(
            Icons.calendar_today_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 22,
          ),
        ],
      ),
    );
  }
}

/// 로딩 본문(PlannerLoadingCard 1장 — 중복 렌더 금지).
class _PlanLoadingView extends StatelessWidget {
  const _PlanLoadingView({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        PlannerLoadingCard(language: language),
      ],
    );
  }
}

/// 에러 본문(메시지 + 재시도).
class _PlanErrorView extends StatelessWidget {
  const _PlanErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 36,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('재시도'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 일정 본문(개요 카드 + 슬롯 리스트 / 빈 상태).
class _PlanContent extends StatelessWidget {
  const _PlanContent({
    required this.dailyPlan,
    required this.visibleSlots,
    required this.language,
    required this.loading,
    required this.onRegenerate,
  });

  final LalaDailyPlan? dailyPlan;
  final List<LalaPlanSlot> visibleSlots;
  final String language;
  final bool loading;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    if (dailyPlan == null || visibleSlots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyPlaceState(language: language),
              const SizedBox(height: 12),
              Text(
                lalaCopy(
                  language,
                  ko: '오늘 일정을 준비 중이에요.',
                  en: 'Today\'s plan is being prepared.',
                ),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  lalaCopy(language, ko: '일정 다시 만들기', en: 'Regenerate plan'),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2B6CB0),
                  side: const BorderSide(color: Color(0xFFB9D4F3)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final weather = dailyPlan!.weather;
    return ListView(
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
        const SizedBox(height: 12),
        ...visibleSlots.map(
          (slot) => Padding(
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
                      lalaCopy(
                        language,
                        ko: '지도 탭에서 동선을 확인해 보세요.',
                        en: 'Check the route on the Map tab.',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
