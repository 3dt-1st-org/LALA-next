// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intervention_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const InterventionDataSource_Enum _$interventionDataSourceEnum_unavailable =
    const InterventionDataSource_Enum._('unavailable');
const InterventionDataSource_Enum
    _$interventionDataSourceEnum_publicMvpSnapshot =
    const InterventionDataSource_Enum._('publicMvpSnapshot');
const InterventionDataSource_Enum _$interventionDataSourceEnum_db =
    const InterventionDataSource_Enum._('db');
const InterventionDataSource_Enum _$interventionDataSourceEnum_mixed =
    const InterventionDataSource_Enum._('mixed');

InterventionDataSource_Enum _$interventionDataSourceEnumValueOf(String name) {
  switch (name) {
    case 'unavailable':
      return _$interventionDataSourceEnum_unavailable;
    case 'publicMvpSnapshot':
      return _$interventionDataSourceEnum_publicMvpSnapshot;
    case 'db':
      return _$interventionDataSourceEnum_db;
    case 'mixed':
      return _$interventionDataSourceEnum_mixed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<InterventionDataSource_Enum> _$interventionDataSourceEnumValues =
    BuiltSet<InterventionDataSource_Enum>(const <InterventionDataSource_Enum>[
  _$interventionDataSourceEnum_unavailable,
  _$interventionDataSourceEnum_publicMvpSnapshot,
  _$interventionDataSourceEnum_db,
  _$interventionDataSourceEnum_mixed,
]);

Serializer<InterventionDataSource_Enum> _$interventionDataSourceEnumSerializer =
    _$InterventionDataSource_EnumSerializer();

class _$InterventionDataSource_EnumSerializer
    implements PrimitiveSerializer<InterventionDataSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'unavailable': 'unavailable',
    'publicMvpSnapshot': 'public_mvp_snapshot',
    'db': 'db',
    'mixed': 'mixed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'unavailable': 'unavailable',
    'public_mvp_snapshot': 'publicMvpSnapshot',
    'db': 'db',
    'mixed': 'mixed',
  };

  @override
  final Iterable<Type> types = const <Type>[InterventionDataSource_Enum];
  @override
  final String wireName = 'InterventionDataSource_Enum';

  @override
  Object serialize(Serializers serializers, InterventionDataSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  InterventionDataSource_Enum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      InterventionDataSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$InterventionData extends InterventionData {
  @override
  final Coordinate center;
  @override
  final Place? place;
  @override
  final int radiusM;
  @override
  final String reason;
  @override
  final String recommendedAction;
  @override
  final bool shouldIntervene;
  @override
  final InterventionDataSource_Enum source_;

  factory _$InterventionData(
          [void Function(InterventionDataBuilder)? updates]) =>
      (InterventionDataBuilder()..update(updates))._build();

  _$InterventionData._(
      {required this.center,
      this.place,
      required this.radiusM,
      required this.reason,
      required this.recommendedAction,
      required this.shouldIntervene,
      required this.source_})
      : super._();
  @override
  InterventionData rebuild(void Function(InterventionDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InterventionDataBuilder toBuilder() =>
      InterventionDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InterventionData &&
        center == other.center &&
        place == other.place &&
        radiusM == other.radiusM &&
        reason == other.reason &&
        recommendedAction == other.recommendedAction &&
        shouldIntervene == other.shouldIntervene &&
        source_ == other.source_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, center.hashCode);
    _$hash = $jc(_$hash, place.hashCode);
    _$hash = $jc(_$hash, radiusM.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, recommendedAction.hashCode);
    _$hash = $jc(_$hash, shouldIntervene.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InterventionData')
          ..add('center', center)
          ..add('place', place)
          ..add('radiusM', radiusM)
          ..add('reason', reason)
          ..add('recommendedAction', recommendedAction)
          ..add('shouldIntervene', shouldIntervene)
          ..add('source_', source_))
        .toString();
  }
}

class InterventionDataBuilder
    implements Builder<InterventionData, InterventionDataBuilder> {
  _$InterventionData? _$v;

  CoordinateBuilder? _center;
  CoordinateBuilder get center => _$this._center ??= CoordinateBuilder();
  set center(CoordinateBuilder? center) => _$this._center = center;

  PlaceBuilder? _place;
  PlaceBuilder get place => _$this._place ??= PlaceBuilder();
  set place(PlaceBuilder? place) => _$this._place = place;

  int? _radiusM;
  int? get radiusM => _$this._radiusM;
  set radiusM(int? radiusM) => _$this._radiusM = radiusM;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  String? _recommendedAction;
  String? get recommendedAction => _$this._recommendedAction;
  set recommendedAction(String? recommendedAction) =>
      _$this._recommendedAction = recommendedAction;

  bool? _shouldIntervene;
  bool? get shouldIntervene => _$this._shouldIntervene;
  set shouldIntervene(bool? shouldIntervene) =>
      _$this._shouldIntervene = shouldIntervene;

  InterventionDataSource_Enum? _source_;
  InterventionDataSource_Enum? get source_ => _$this._source_;
  set source_(InterventionDataSource_Enum? source_) =>
      _$this._source_ = source_;

  InterventionDataBuilder() {
    InterventionData._defaults(this);
  }

  InterventionDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _center = $v.center.toBuilder();
      _place = $v.place?.toBuilder();
      _radiusM = $v.radiusM;
      _reason = $v.reason;
      _recommendedAction = $v.recommendedAction;
      _shouldIntervene = $v.shouldIntervene;
      _source_ = $v.source_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InterventionData other) {
    _$v = other as _$InterventionData;
  }

  @override
  void update(void Function(InterventionDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InterventionData build() => _build();

  _$InterventionData _build() {
    _$InterventionData _$result;
    try {
      _$result = _$v ??
          _$InterventionData._(
            center: center.build(),
            place: _place?.build(),
            radiusM: BuiltValueNullFieldError.checkNotNull(
                radiusM, r'InterventionData', 'radiusM'),
            reason: BuiltValueNullFieldError.checkNotNull(
                reason, r'InterventionData', 'reason'),
            recommendedAction: BuiltValueNullFieldError.checkNotNull(
                recommendedAction, r'InterventionData', 'recommendedAction'),
            shouldIntervene: BuiltValueNullFieldError.checkNotNull(
                shouldIntervene, r'InterventionData', 'shouldIntervene'),
            source_: BuiltValueNullFieldError.checkNotNull(
                source_, r'InterventionData', 'source_'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'center';
        center.build();
        _$failedField = 'place';
        _place?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'InterventionData', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
