// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'docent_script_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DocentScriptRequestCategoryEnum
    _$docentScriptRequestCategoryEnum_attraction =
    const DocentScriptRequestCategoryEnum._('attraction');
const DocentScriptRequestCategoryEnum
    _$docentScriptRequestCategoryEnum_restaurant =
    const DocentScriptRequestCategoryEnum._('restaurant');
const DocentScriptRequestCategoryEnum _$docentScriptRequestCategoryEnum_event =
    const DocentScriptRequestCategoryEnum._('event');
const DocentScriptRequestCategoryEnum
    _$docentScriptRequestCategoryEnum_cultureVenue =
    const DocentScriptRequestCategoryEnum._('cultureVenue');

DocentScriptRequestCategoryEnum _$docentScriptRequestCategoryEnumValueOf(
    String name) {
  switch (name) {
    case 'attraction':
      return _$docentScriptRequestCategoryEnum_attraction;
    case 'restaurant':
      return _$docentScriptRequestCategoryEnum_restaurant;
    case 'event':
      return _$docentScriptRequestCategoryEnum_event;
    case 'cultureVenue':
      return _$docentScriptRequestCategoryEnum_cultureVenue;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DocentScriptRequestCategoryEnum>
    _$docentScriptRequestCategoryEnumValues = BuiltSet<
        DocentScriptRequestCategoryEnum>(const <DocentScriptRequestCategoryEnum>[
  _$docentScriptRequestCategoryEnum_attraction,
  _$docentScriptRequestCategoryEnum_restaurant,
  _$docentScriptRequestCategoryEnum_event,
  _$docentScriptRequestCategoryEnum_cultureVenue,
]);

Serializer<DocentScriptRequestCategoryEnum>
    _$docentScriptRequestCategoryEnumSerializer =
    _$DocentScriptRequestCategoryEnumSerializer();

class _$DocentScriptRequestCategoryEnumSerializer
    implements PrimitiveSerializer<DocentScriptRequestCategoryEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'attraction': 'attraction',
    'restaurant': 'restaurant',
    'event': 'event',
    'cultureVenue': 'culture_venue',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'attraction': 'attraction',
    'restaurant': 'restaurant',
    'event': 'event',
    'culture_venue': 'cultureVenue',
  };

  @override
  final Iterable<Type> types = const <Type>[DocentScriptRequestCategoryEnum];
  @override
  final String wireName = 'DocentScriptRequestCategoryEnum';

  @override
  Object serialize(
          Serializers serializers, DocentScriptRequestCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DocentScriptRequestCategoryEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DocentScriptRequestCategoryEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DocentScriptRequest extends DocentScriptRequest {
  @override
  final String? address;
  @override
  final DocentScriptRequestCategoryEnum category;
  @override
  final num? cultureRelevanceScore;
  @override
  final num? demandDispersionScore;
  @override
  final int? distanceM;
  @override
  final String? dustGrade;
  @override
  final String? dustPm10;
  @override
  final String? dustPm10Grade;
  @override
  final String? dustPm25;
  @override
  final String? dustPm25Grade;
  @override
  final num? finalScore;
  @override
  final String? language;
  @override
  final num? localSpendingScore;
  @override
  final String? mode;
  @override
  final String placeId;
  @override
  final String? placeName;
  @override
  final String? regionEn;
  @override
  final String? regionKo;
  @override
  final num? smallMerchantFitScore;
  @override
  final String? source_;
  @override
  final String? upstreamSource;
  @override
  final num? weatherFitScore;
  @override
  final String? weatherIcon;
  @override
  final String? weatherOutdoorStatus;
  @override
  final String? weatherTemp;

  factory _$DocentScriptRequest(
          [void Function(DocentScriptRequestBuilder)? updates]) =>
      (DocentScriptRequestBuilder()..update(updates))._build();

  _$DocentScriptRequest._(
      {this.address,
      required this.category,
      this.cultureRelevanceScore,
      this.demandDispersionScore,
      this.distanceM,
      this.dustGrade,
      this.dustPm10,
      this.dustPm10Grade,
      this.dustPm25,
      this.dustPm25Grade,
      this.finalScore,
      this.language,
      this.localSpendingScore,
      this.mode,
      required this.placeId,
      this.placeName,
      this.regionEn,
      this.regionKo,
      this.smallMerchantFitScore,
      this.source_,
      this.upstreamSource,
      this.weatherFitScore,
      this.weatherIcon,
      this.weatherOutdoorStatus,
      this.weatherTemp})
      : super._();
  @override
  DocentScriptRequest rebuild(
          void Function(DocentScriptRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DocentScriptRequestBuilder toBuilder() =>
      DocentScriptRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DocentScriptRequest &&
        address == other.address &&
        category == other.category &&
        cultureRelevanceScore == other.cultureRelevanceScore &&
        demandDispersionScore == other.demandDispersionScore &&
        distanceM == other.distanceM &&
        dustGrade == other.dustGrade &&
        dustPm10 == other.dustPm10 &&
        dustPm10Grade == other.dustPm10Grade &&
        dustPm25 == other.dustPm25 &&
        dustPm25Grade == other.dustPm25Grade &&
        finalScore == other.finalScore &&
        language == other.language &&
        localSpendingScore == other.localSpendingScore &&
        mode == other.mode &&
        placeId == other.placeId &&
        placeName == other.placeName &&
        regionEn == other.regionEn &&
        regionKo == other.regionKo &&
        smallMerchantFitScore == other.smallMerchantFitScore &&
        source_ == other.source_ &&
        upstreamSource == other.upstreamSource &&
        weatherFitScore == other.weatherFitScore &&
        weatherIcon == other.weatherIcon &&
        weatherOutdoorStatus == other.weatherOutdoorStatus &&
        weatherTemp == other.weatherTemp;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, address.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, cultureRelevanceScore.hashCode);
    _$hash = $jc(_$hash, demandDispersionScore.hashCode);
    _$hash = $jc(_$hash, distanceM.hashCode);
    _$hash = $jc(_$hash, dustGrade.hashCode);
    _$hash = $jc(_$hash, dustPm10.hashCode);
    _$hash = $jc(_$hash, dustPm10Grade.hashCode);
    _$hash = $jc(_$hash, dustPm25.hashCode);
    _$hash = $jc(_$hash, dustPm25Grade.hashCode);
    _$hash = $jc(_$hash, finalScore.hashCode);
    _$hash = $jc(_$hash, language.hashCode);
    _$hash = $jc(_$hash, localSpendingScore.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, placeId.hashCode);
    _$hash = $jc(_$hash, placeName.hashCode);
    _$hash = $jc(_$hash, regionEn.hashCode);
    _$hash = $jc(_$hash, regionKo.hashCode);
    _$hash = $jc(_$hash, smallMerchantFitScore.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, upstreamSource.hashCode);
    _$hash = $jc(_$hash, weatherFitScore.hashCode);
    _$hash = $jc(_$hash, weatherIcon.hashCode);
    _$hash = $jc(_$hash, weatherOutdoorStatus.hashCode);
    _$hash = $jc(_$hash, weatherTemp.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DocentScriptRequest')
          ..add('address', address)
          ..add('category', category)
          ..add('cultureRelevanceScore', cultureRelevanceScore)
          ..add('demandDispersionScore', demandDispersionScore)
          ..add('distanceM', distanceM)
          ..add('dustGrade', dustGrade)
          ..add('dustPm10', dustPm10)
          ..add('dustPm10Grade', dustPm10Grade)
          ..add('dustPm25', dustPm25)
          ..add('dustPm25Grade', dustPm25Grade)
          ..add('finalScore', finalScore)
          ..add('language', language)
          ..add('localSpendingScore', localSpendingScore)
          ..add('mode', mode)
          ..add('placeId', placeId)
          ..add('placeName', placeName)
          ..add('regionEn', regionEn)
          ..add('regionKo', regionKo)
          ..add('smallMerchantFitScore', smallMerchantFitScore)
          ..add('source_', source_)
          ..add('upstreamSource', upstreamSource)
          ..add('weatherFitScore', weatherFitScore)
          ..add('weatherIcon', weatherIcon)
          ..add('weatherOutdoorStatus', weatherOutdoorStatus)
          ..add('weatherTemp', weatherTemp))
        .toString();
  }
}

class DocentScriptRequestBuilder
    implements Builder<DocentScriptRequest, DocentScriptRequestBuilder> {
  _$DocentScriptRequest? _$v;

  String? _address;
  String? get address => _$this._address;
  set address(String? address) => _$this._address = address;

  DocentScriptRequestCategoryEnum? _category;
  DocentScriptRequestCategoryEnum? get category => _$this._category;
  set category(DocentScriptRequestCategoryEnum? category) =>
      _$this._category = category;

  num? _cultureRelevanceScore;
  num? get cultureRelevanceScore => _$this._cultureRelevanceScore;
  set cultureRelevanceScore(num? cultureRelevanceScore) =>
      _$this._cultureRelevanceScore = cultureRelevanceScore;

  num? _demandDispersionScore;
  num? get demandDispersionScore => _$this._demandDispersionScore;
  set demandDispersionScore(num? demandDispersionScore) =>
      _$this._demandDispersionScore = demandDispersionScore;

  int? _distanceM;
  int? get distanceM => _$this._distanceM;
  set distanceM(int? distanceM) => _$this._distanceM = distanceM;

  String? _dustGrade;
  String? get dustGrade => _$this._dustGrade;
  set dustGrade(String? dustGrade) => _$this._dustGrade = dustGrade;

  String? _dustPm10;
  String? get dustPm10 => _$this._dustPm10;
  set dustPm10(String? dustPm10) => _$this._dustPm10 = dustPm10;

  String? _dustPm10Grade;
  String? get dustPm10Grade => _$this._dustPm10Grade;
  set dustPm10Grade(String? dustPm10Grade) =>
      _$this._dustPm10Grade = dustPm10Grade;

  String? _dustPm25;
  String? get dustPm25 => _$this._dustPm25;
  set dustPm25(String? dustPm25) => _$this._dustPm25 = dustPm25;

  String? _dustPm25Grade;
  String? get dustPm25Grade => _$this._dustPm25Grade;
  set dustPm25Grade(String? dustPm25Grade) =>
      _$this._dustPm25Grade = dustPm25Grade;

  num? _finalScore;
  num? get finalScore => _$this._finalScore;
  set finalScore(num? finalScore) => _$this._finalScore = finalScore;

  String? _language;
  String? get language => _$this._language;
  set language(String? language) => _$this._language = language;

  num? _localSpendingScore;
  num? get localSpendingScore => _$this._localSpendingScore;
  set localSpendingScore(num? localSpendingScore) =>
      _$this._localSpendingScore = localSpendingScore;

  String? _mode;
  String? get mode => _$this._mode;
  set mode(String? mode) => _$this._mode = mode;

  String? _placeId;
  String? get placeId => _$this._placeId;
  set placeId(String? placeId) => _$this._placeId = placeId;

  String? _placeName;
  String? get placeName => _$this._placeName;
  set placeName(String? placeName) => _$this._placeName = placeName;

  String? _regionEn;
  String? get regionEn => _$this._regionEn;
  set regionEn(String? regionEn) => _$this._regionEn = regionEn;

  String? _regionKo;
  String? get regionKo => _$this._regionKo;
  set regionKo(String? regionKo) => _$this._regionKo = regionKo;

  num? _smallMerchantFitScore;
  num? get smallMerchantFitScore => _$this._smallMerchantFitScore;
  set smallMerchantFitScore(num? smallMerchantFitScore) =>
      _$this._smallMerchantFitScore = smallMerchantFitScore;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _upstreamSource;
  String? get upstreamSource => _$this._upstreamSource;
  set upstreamSource(String? upstreamSource) =>
      _$this._upstreamSource = upstreamSource;

  num? _weatherFitScore;
  num? get weatherFitScore => _$this._weatherFitScore;
  set weatherFitScore(num? weatherFitScore) =>
      _$this._weatherFitScore = weatherFitScore;

  String? _weatherIcon;
  String? get weatherIcon => _$this._weatherIcon;
  set weatherIcon(String? weatherIcon) => _$this._weatherIcon = weatherIcon;

  String? _weatherOutdoorStatus;
  String? get weatherOutdoorStatus => _$this._weatherOutdoorStatus;
  set weatherOutdoorStatus(String? weatherOutdoorStatus) =>
      _$this._weatherOutdoorStatus = weatherOutdoorStatus;

  String? _weatherTemp;
  String? get weatherTemp => _$this._weatherTemp;
  set weatherTemp(String? weatherTemp) => _$this._weatherTemp = weatherTemp;

  DocentScriptRequestBuilder() {
    DocentScriptRequest._defaults(this);
  }

  DocentScriptRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _address = $v.address;
      _category = $v.category;
      _cultureRelevanceScore = $v.cultureRelevanceScore;
      _demandDispersionScore = $v.demandDispersionScore;
      _distanceM = $v.distanceM;
      _dustGrade = $v.dustGrade;
      _dustPm10 = $v.dustPm10;
      _dustPm10Grade = $v.dustPm10Grade;
      _dustPm25 = $v.dustPm25;
      _dustPm25Grade = $v.dustPm25Grade;
      _finalScore = $v.finalScore;
      _language = $v.language;
      _localSpendingScore = $v.localSpendingScore;
      _mode = $v.mode;
      _placeId = $v.placeId;
      _placeName = $v.placeName;
      _regionEn = $v.regionEn;
      _regionKo = $v.regionKo;
      _smallMerchantFitScore = $v.smallMerchantFitScore;
      _source_ = $v.source_;
      _upstreamSource = $v.upstreamSource;
      _weatherFitScore = $v.weatherFitScore;
      _weatherIcon = $v.weatherIcon;
      _weatherOutdoorStatus = $v.weatherOutdoorStatus;
      _weatherTemp = $v.weatherTemp;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DocentScriptRequest other) {
    _$v = other as _$DocentScriptRequest;
  }

  @override
  void update(void Function(DocentScriptRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DocentScriptRequest build() => _build();

  _$DocentScriptRequest _build() {
    final _$result = _$v ??
        _$DocentScriptRequest._(
          address: address,
          category: BuiltValueNullFieldError.checkNotNull(
              category, r'DocentScriptRequest', 'category'),
          cultureRelevanceScore: cultureRelevanceScore,
          demandDispersionScore: demandDispersionScore,
          distanceM: distanceM,
          dustGrade: dustGrade,
          dustPm10: dustPm10,
          dustPm10Grade: dustPm10Grade,
          dustPm25: dustPm25,
          dustPm25Grade: dustPm25Grade,
          finalScore: finalScore,
          language: language,
          localSpendingScore: localSpendingScore,
          mode: mode,
          placeId: BuiltValueNullFieldError.checkNotNull(
              placeId, r'DocentScriptRequest', 'placeId'),
          placeName: placeName,
          regionEn: regionEn,
          regionKo: regionKo,
          smallMerchantFitScore: smallMerchantFitScore,
          source_: source_,
          upstreamSource: upstreamSource,
          weatherFitScore: weatherFitScore,
          weatherIcon: weatherIcon,
          weatherOutdoorStatus: weatherOutdoorStatus,
          weatherTemp: weatherTemp,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
