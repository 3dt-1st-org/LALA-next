// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dust.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Dust extends Dust {
  @override
  final String grade;
  @override
  final String gradeKo;
  @override
  final String pm10;
  @override
  final String pm10Grade;
  @override
  final String pm10GradeKo;
  @override
  final String pm25;
  @override
  final String pm25Grade;
  @override
  final String pm25GradeKo;

  factory _$Dust([void Function(DustBuilder)? updates]) =>
      (DustBuilder()..update(updates))._build();

  _$Dust._(
      {required this.grade,
      required this.gradeKo,
      required this.pm10,
      required this.pm10Grade,
      required this.pm10GradeKo,
      required this.pm25,
      required this.pm25Grade,
      required this.pm25GradeKo})
      : super._();
  @override
  Dust rebuild(void Function(DustBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DustBuilder toBuilder() => DustBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Dust &&
        grade == other.grade &&
        gradeKo == other.gradeKo &&
        pm10 == other.pm10 &&
        pm10Grade == other.pm10Grade &&
        pm10GradeKo == other.pm10GradeKo &&
        pm25 == other.pm25 &&
        pm25Grade == other.pm25Grade &&
        pm25GradeKo == other.pm25GradeKo;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, grade.hashCode);
    _$hash = $jc(_$hash, gradeKo.hashCode);
    _$hash = $jc(_$hash, pm10.hashCode);
    _$hash = $jc(_$hash, pm10Grade.hashCode);
    _$hash = $jc(_$hash, pm10GradeKo.hashCode);
    _$hash = $jc(_$hash, pm25.hashCode);
    _$hash = $jc(_$hash, pm25Grade.hashCode);
    _$hash = $jc(_$hash, pm25GradeKo.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Dust')
          ..add('grade', grade)
          ..add('gradeKo', gradeKo)
          ..add('pm10', pm10)
          ..add('pm10Grade', pm10Grade)
          ..add('pm10GradeKo', pm10GradeKo)
          ..add('pm25', pm25)
          ..add('pm25Grade', pm25Grade)
          ..add('pm25GradeKo', pm25GradeKo))
        .toString();
  }
}

class DustBuilder implements Builder<Dust, DustBuilder> {
  _$Dust? _$v;

  String? _grade;
  String? get grade => _$this._grade;
  set grade(String? grade) => _$this._grade = grade;

  String? _gradeKo;
  String? get gradeKo => _$this._gradeKo;
  set gradeKo(String? gradeKo) => _$this._gradeKo = gradeKo;

  String? _pm10;
  String? get pm10 => _$this._pm10;
  set pm10(String? pm10) => _$this._pm10 = pm10;

  String? _pm10Grade;
  String? get pm10Grade => _$this._pm10Grade;
  set pm10Grade(String? pm10Grade) => _$this._pm10Grade = pm10Grade;

  String? _pm10GradeKo;
  String? get pm10GradeKo => _$this._pm10GradeKo;
  set pm10GradeKo(String? pm10GradeKo) => _$this._pm10GradeKo = pm10GradeKo;

  String? _pm25;
  String? get pm25 => _$this._pm25;
  set pm25(String? pm25) => _$this._pm25 = pm25;

  String? _pm25Grade;
  String? get pm25Grade => _$this._pm25Grade;
  set pm25Grade(String? pm25Grade) => _$this._pm25Grade = pm25Grade;

  String? _pm25GradeKo;
  String? get pm25GradeKo => _$this._pm25GradeKo;
  set pm25GradeKo(String? pm25GradeKo) => _$this._pm25GradeKo = pm25GradeKo;

  DustBuilder() {
    Dust._defaults(this);
  }

  DustBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _grade = $v.grade;
      _gradeKo = $v.gradeKo;
      _pm10 = $v.pm10;
      _pm10Grade = $v.pm10Grade;
      _pm10GradeKo = $v.pm10GradeKo;
      _pm25 = $v.pm25;
      _pm25Grade = $v.pm25Grade;
      _pm25GradeKo = $v.pm25GradeKo;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Dust other) {
    _$v = other as _$Dust;
  }

  @override
  void update(void Function(DustBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Dust build() => _build();

  _$Dust _build() {
    final _$result = _$v ??
        _$Dust._(
          grade: BuiltValueNullFieldError.checkNotNull(grade, r'Dust', 'grade'),
          gradeKo: BuiltValueNullFieldError.checkNotNull(
              gradeKo, r'Dust', 'gradeKo'),
          pm10: BuiltValueNullFieldError.checkNotNull(pm10, r'Dust', 'pm10'),
          pm10Grade: BuiltValueNullFieldError.checkNotNull(
              pm10Grade, r'Dust', 'pm10Grade'),
          pm10GradeKo: BuiltValueNullFieldError.checkNotNull(
              pm10GradeKo, r'Dust', 'pm10GradeKo'),
          pm25: BuiltValueNullFieldError.checkNotNull(pm25, r'Dust', 'pm25'),
          pm25Grade: BuiltValueNullFieldError.checkNotNull(
              pm25Grade, r'Dust', 'pm25Grade'),
          pm25GradeKo: BuiltValueNullFieldError.checkNotNull(
              pm25GradeKo, r'Dust', 'pm25GradeKo'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
