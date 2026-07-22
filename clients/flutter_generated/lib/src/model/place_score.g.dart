// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place_score.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PlaceScoreDataBasisEnum
    _$placeScoreDataBasisEnum_analyticsPeriodPlaceScoreSnapshots =
    const PlaceScoreDataBasisEnum._('analyticsPeriodPlaceScoreSnapshots');
const PlaceScoreDataBasisEnum _$placeScoreDataBasisEnum_publicMvpSnapshot =
    const PlaceScoreDataBasisEnum._('publicMvpSnapshot');

PlaceScoreDataBasisEnum _$placeScoreDataBasisEnumValueOf(String name) {
  switch (name) {
    case 'analyticsPeriodPlaceScoreSnapshots':
      return _$placeScoreDataBasisEnum_analyticsPeriodPlaceScoreSnapshots;
    case 'publicMvpSnapshot':
      return _$placeScoreDataBasisEnum_publicMvpSnapshot;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlaceScoreDataBasisEnum> _$placeScoreDataBasisEnumValues =
    BuiltSet<PlaceScoreDataBasisEnum>(const <PlaceScoreDataBasisEnum>[
  _$placeScoreDataBasisEnum_analyticsPeriodPlaceScoreSnapshots,
  _$placeScoreDataBasisEnum_publicMvpSnapshot,
]);

Serializer<PlaceScoreDataBasisEnum> _$placeScoreDataBasisEnumSerializer =
    _$PlaceScoreDataBasisEnumSerializer();

class _$PlaceScoreDataBasisEnumSerializer
    implements PrimitiveSerializer<PlaceScoreDataBasisEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'analyticsPeriodPlaceScoreSnapshots': 'analytics.place_score_snapshots',
    'publicMvpSnapshot': 'public_mvp_snapshot',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'analytics.place_score_snapshots': 'analyticsPeriodPlaceScoreSnapshots',
    'public_mvp_snapshot': 'publicMvpSnapshot',
  };

  @override
  final Iterable<Type> types = const <Type>[PlaceScoreDataBasisEnum];
  @override
  final String wireName = 'PlaceScoreDataBasisEnum';

  @override
  Object serialize(Serializers serializers, PlaceScoreDataBasisEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlaceScoreDataBasisEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlaceScoreDataBasisEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PlaceScore extends PlaceScore {
  @override
  final PlaceScoreComponents components;
  @override
  final PlaceScoreDataBasisEnum dataBasis;
  @override
  final JsonObject features;
  @override
  final double finalScore;
  @override
  final String formulaVersion;

  factory _$PlaceScore([void Function(PlaceScoreBuilder)? updates]) =>
      (PlaceScoreBuilder()..update(updates))._build();

  _$PlaceScore._(
      {required this.components,
      required this.dataBasis,
      required this.features,
      required this.finalScore,
      required this.formulaVersion})
      : super._();
  @override
  PlaceScore rebuild(void Function(PlaceScoreBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaceScoreBuilder toBuilder() => PlaceScoreBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaceScore &&
        components == other.components &&
        dataBasis == other.dataBasis &&
        features == other.features &&
        finalScore == other.finalScore &&
        formulaVersion == other.formulaVersion;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, components.hashCode);
    _$hash = $jc(_$hash, dataBasis.hashCode);
    _$hash = $jc(_$hash, features.hashCode);
    _$hash = $jc(_$hash, finalScore.hashCode);
    _$hash = $jc(_$hash, formulaVersion.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaceScore')
          ..add('components', components)
          ..add('dataBasis', dataBasis)
          ..add('features', features)
          ..add('finalScore', finalScore)
          ..add('formulaVersion', formulaVersion))
        .toString();
  }
}

class PlaceScoreBuilder implements Builder<PlaceScore, PlaceScoreBuilder> {
  _$PlaceScore? _$v;

  PlaceScoreComponentsBuilder? _components;
  PlaceScoreComponentsBuilder get components =>
      _$this._components ??= PlaceScoreComponentsBuilder();
  set components(PlaceScoreComponentsBuilder? components) =>
      _$this._components = components;

  PlaceScoreDataBasisEnum? _dataBasis;
  PlaceScoreDataBasisEnum? get dataBasis => _$this._dataBasis;
  set dataBasis(PlaceScoreDataBasisEnum? dataBasis) =>
      _$this._dataBasis = dataBasis;

  JsonObject? _features;
  JsonObject? get features => _$this._features;
  set features(JsonObject? features) => _$this._features = features;

  double? _finalScore;
  double? get finalScore => _$this._finalScore;
  set finalScore(double? finalScore) => _$this._finalScore = finalScore;

  String? _formulaVersion;
  String? get formulaVersion => _$this._formulaVersion;
  set formulaVersion(String? formulaVersion) =>
      _$this._formulaVersion = formulaVersion;

  PlaceScoreBuilder() {
    PlaceScore._defaults(this);
  }

  PlaceScoreBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _components = $v.components.toBuilder();
      _dataBasis = $v.dataBasis;
      _features = $v.features;
      _finalScore = $v.finalScore;
      _formulaVersion = $v.formulaVersion;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaceScore other) {
    _$v = other as _$PlaceScore;
  }

  @override
  void update(void Function(PlaceScoreBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaceScore build() => _build();

  _$PlaceScore _build() {
    _$PlaceScore _$result;
    try {
      _$result = _$v ??
          _$PlaceScore._(
            components: components.build(),
            dataBasis: BuiltValueNullFieldError.checkNotNull(
                dataBasis, r'PlaceScore', 'dataBasis'),
            features: BuiltValueNullFieldError.checkNotNull(
                features, r'PlaceScore', 'features'),
            finalScore: BuiltValueNullFieldError.checkNotNull(
                finalScore, r'PlaceScore', 'finalScore'),
            formulaVersion: BuiltValueNullFieldError.checkNotNull(
                formulaVersion, r'PlaceScore', 'formulaVersion'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'components';
        components.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PlaceScore', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
