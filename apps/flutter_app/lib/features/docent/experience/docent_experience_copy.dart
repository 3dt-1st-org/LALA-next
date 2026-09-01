// 이슈 #120 §4/§7: 도슨트 경험 문구 SSOT(5개 로케일, 색/문구로 상태를 이중 전달).
// 원시 exception/provider 오류 본문은 절대 여기로 들어오지 않는다 — 호출부가
// bounded copy 로만 매핑한다.
import '../../../shared/l10n/lala_copy.dart';
import 'docent_experience_state.dart';

/// 미니플레이어/플레이어 상태 한 줄 캡션(단계별 정직 문구).
String docentExperiencePhaseLabel(
  DocentExperiencePhase phase,
  String language,
) {
  switch (phase) {
    case DocentExperiencePhase.idle:
      return '';
    case DocentExperiencePhase.checkingReadiness:
    case DocentExperiencePhase.preparingScript:
    case DocentExperiencePhase.preparingAudio:
      return lalaCopyMulti(
        language,
        ko: '도슨트 준비 중',
        en: 'Preparing the guide',
        ja: 'ガイドを準備中',
        zhHans: '正在准备讲解',
        zhHant: '正在準備導覽',
      );
    case DocentExperiencePhase.ready:
      return lalaCopyMulti(
        language,
        ko: '재생 준비됨',
        en: 'Ready to play',
        ja: '再生準備完了',
        zhHans: '已就绪',
        zhHant: '已就緒',
      );
    case DocentExperiencePhase.playing:
      return lalaCopyMulti(
        language,
        ko: '재생 중',
        en: 'Playing',
        ja: '再生中',
        zhHans: '正在播放',
        zhHant: '正在播放',
      );
    case DocentExperiencePhase.paused:
      return lalaCopyMulti(
        language,
        ko: '일시정지',
        en: 'Paused',
        ja: '一時停止',
        zhHans: '已暂停',
        zhHant: '已暫停',
      );
    case DocentExperiencePhase.completed:
      return lalaCopyMulti(
        language,
        ko: '재생 완료',
        en: 'Finished',
        ja: '再生完了',
        zhHans: '播放完毕',
        zhHant: '播放完畢',
      );
    case DocentExperiencePhase.unavailable:
      return speechUnavailableMessage(language);
    case DocentExperiencePhase.failed:
      return lalaCopyMulti(
        language,
        ko: '준비하지 못했어요',
        en: 'Could not prepare',
        ja: '準備できませんでした',
        zhHans: '未能准备',
        zhHant: '未能準備',
      );
  }
}

/// readiness 가 음성 사용 불가로 보고한 정직한 unavailable 문구.
String speechUnavailableMessage(String language) {
  return lalaCopyMulti(
    language,
    ko: '음성 도슨트를 사용할 수 없어요',
    en: 'Voice docent is unavailable',
    ja: '音声ガイドはご利用いただけません',
    zhHans: '语音讲解暂不可用',
    zhHant: '語音導覽暫不可用',
  );
}

/// 스크립트 생성 실패 문구(서버 오류 본문 미노출).
String docentScriptFailureMessage(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 스크립트를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not prepare the docent script. Please try again shortly.',
    ja: 'ドセントスクリプトを準備できませんでした。しばらくしてからもう一度お試しください。',
    zhHans: '无法准备讲解词，请稍后重试。',
    zhHant: '無法準備導覽解說，請稍後重試。',
  );
}

/// 음성 변환 실패 문구(스크립트는 계속 볼 수 있다는 정직한 안내).
String docentAudioFailureMessageLocalized(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 음성을 준비하지 못했어요. 스크립트는 계속 볼 수 있습니다.',
    en: 'Could not prepare the docent audio. The script is still available.',
    ja: 'ドセント音声を準備できませんでした。スクリプトは引き続きご覧いただけます。',
    zhHans: '无法准备讲解语音，讲解词仍可查看。',
    zhHant: '無法準備導覽語音，導覽解說仍可查看。',
  );
}

/// 오디오 컨트롤 시맨틱 라벨(§7: 모든 오디오 컨트롤에 지역화 시맨틱).
String docentPlaySemanticLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 재생',
    en: 'Play docent',
    ja: 'ガイドを再生',
    zhHans: '播放讲解',
    zhHant: '播放導覽',
  );
}

String docentPauseSemanticLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 일시정지',
    en: 'Pause docent',
    ja: 'ガイドを一時停止',
    zhHans: '暂停讲解',
    zhHant: '暫停導覽',
  );
}

String docentRetrySemanticLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 다시 시도',
    en: 'Retry docent',
    ja: 'ガイドを再試行',
    zhHans: '重试讲解',
    zhHant: '重試導覽',
  );
}

String docentStopSemanticLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 정지',
    en: 'Stop docent',
    ja: 'ガイドを停止',
    zhHans: '停止讲解',
    zhHant: '停止導覽',
  );
}

/// 기계 source 식별자 → bounded 지역화 라벨(§6.3). 알 수 없는 값은 일반 라벨로.
String docentScriptSourceLabel(String source, String language) {
  final normalized = source.trim().toLowerCase();
  switch (normalized) {
    case 'rule_based_curation':
      return lalaCopyMulti(
        language,
        ko: 'LALA 큐레이션',
        en: 'LALA curation',
        ja: 'LALA キュレーション',
        zhHans: 'LALA 精选',
        zhHant: 'LALA 精選',
      );
    case 'db_cache':
      return lalaCopyMulti(
        language,
        ko: '저장된 도슨트',
        en: 'Saved guide',
        ja: '保存済みガイド',
        zhHans: '已保存讲解',
        zhHant: '已保存導覽',
      );
    case 'openai':
      return lalaCopyMulti(
        language,
        ko: 'AI 생성',
        en: 'AI generated',
        ja: 'AI 生成',
        zhHans: 'AI 生成',
        zhHant: 'AI 生成',
      );
    case '':
      return lalaCopyMulti(
        language,
        ko: 'AI 도슨트',
        en: 'AI docent',
        ja: 'AI ガイド',
        zhHans: 'AI 讲解',
        zhHant: 'AI 導覽',
      );
    default:
      // 알 수 없는 식별자를 그대로 크게 노출하지 않고 일반 라벨로 수렴시킨다.
      return lalaCopyMulti(
        language,
        ko: 'AI 도슨트',
        en: 'AI docent',
        ja: 'AI ガイド',
        zhHans: 'AI 讲解',
        zhHant: 'AI 導覽',
      );
  }
}

/// 미니플레이어 탭(전체 플레이어 열기) 시맨틱 라벨.
String docentOpenPlayerSemanticLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 플레이어 열기',
    en: 'Open the docent player',
    ja: 'ガイドプレーヤーを開く',
    zhHans: '打开讲解播放器',
    zhHant: '打開導覽播放器',
  );
}

/// 큐 진행 표기(1-based). 숫자만 쓰므로 로케일 변형 없이 하나의 문자열.
String docentMiniQueueProgress(int queueIndex, int queueLength) =>
    '${queueIndex + 1}/$queueLength';

/// 전체 플레이어 스크립트 섹션 제목.
String docentTranscriptSectionTitle(String language) {
  return lalaCopyMulti(
    language,
    ko: '도슨트 스크립트',
    en: 'Docent script',
    ja: 'ガイドスクリプト',
    zhHans: '讲解词',
    zhHant: '導覽解說',
  );
}

/// 운전기사용 한국어 이름 유틸리티 버튼 라벨(§6.3).
String docentDriverNameButtonLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '운전기사에게 보여주기',
    en: 'Show your driver',
    ja: '運転手さんに見せる',
    zhHans: '出示给司机',
    zhHant: '出示給司機',
  );
}

/// 한국어 이름 시트 캡션(이름 자체는 nameKo 원문 그대로 — 번역하지 않는다).
String docentDriverNameSheetCaption(String language) {
  return lalaCopyMulti(
    language,
    ko: '한국어 이름',
    en: 'Korean name',
    ja: '韓国語の名前',
    zhHans: '韩语名称',
    zhHant: '韓語名稱',
  );
}

/// grounding source_type 식별자 → bounded 지역화 라벨(§6.3). 원시 내부값을
/// 그대로 노출하지 않는다 — 알 수 없는 값은 출처 성격을 단정하지 않는 중립
/// 라벨로 수렴한다.
String docentGroundingSourceLabel(String source, String language) {
  final normalized = source.trim().toLowerCase();
  switch (normalized) {
    case 'place_profile':
      return lalaCopyMulti(
        language,
        ko: '장소 프로필',
        en: 'Place profile',
        ja: '場所プロフィール',
        zhHans: '场所资料',
        zhHant: '場所資料',
      );
    case 'culture_event':
      return lalaCopyMulti(
        language,
        ko: '문화 행사 정보',
        en: 'Culture event data',
        ja: '文化イベント情報',
        zhHans: '文化活动信息',
        zhHant: '文化活動資訊',
      );
    case 'place_mention':
      return lalaCopyMulti(
        language,
        ko: '장소 언급',
        en: 'Place mentions',
        ja: '場所への言及',
        zhHans: '地点提及',
        zhHant: '地點提及',
      );
    case 'community_post':
      return lalaCopyMulti(
        language,
        ko: '커뮤니티 게시물',
        en: 'Community post',
        ja: 'コミュニティ投稿',
        zhHans: '社区帖子',
        zhHant: '社群貼文',
      );
    case 'weather_context':
      return lalaCopyMulti(
        language,
        ko: '날씨 맥락',
        en: 'Weather context',
        ja: '天気コンテキスト',
        zhHans: '天气背景',
        zhHant: '天氣背景',
      );
    default:
      return lalaCopyMulti(
        language,
        ko: '참고 자료',
        en: 'Reference source',
        ja: '参考資料',
        zhHans: '参考资料',
        zhHant: '參考資料',
      );
  }
}

/// 일정 '전체 도슨트 듣기' 진입 버튼 라벨(보이는 슬롯 순서 큐 재생).
String docentPlayAllLabel(String language) {
  return lalaCopyMulti(
    language,
    ko: '전체 도슨트 듣기',
    en: 'Play the full guide',
    ja: 'ガイドをすべて再生',
    zhHans: '播放全部讲解',
    zhHant: '播放全部導覽',
  );
}

/// 생성 시점 라벨 — 파싱 가능한 generatedAt 에만 호출(파싱 불가면 호출부가 생략).
String docentGeneratedAtLabel(DateTime generatedAt, String language) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamped =
      '${generatedAt.year}.${two(generatedAt.month)}.${two(generatedAt.day)}';
  return lalaCopyMulti(
    language,
    ko: '$stamped 생성',
    en: 'Created $stamped',
    ja: '$stamped 生成',
    zhHans: '生成于 $stamped',
    zhHant: '生成於 $stamped',
  );
}
