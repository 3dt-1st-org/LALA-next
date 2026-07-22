// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'docent_audio_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DocentAudioRequest extends DocentAudioRequest {
  @override
  final String? language;
  @override
  final String script;

  factory _$DocentAudioRequest(
          [void Function(DocentAudioRequestBuilder)? updates]) =>
      (DocentAudioRequestBuilder()..update(updates))._build();

  _$DocentAudioRequest._({this.language, required this.script}) : super._();
  @override
  DocentAudioRequest rebuild(
          void Function(DocentAudioRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DocentAudioRequestBuilder toBuilder() =>
      DocentAudioRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DocentAudioRequest &&
        language == other.language &&
        script == other.script;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, language.hashCode);
    _$hash = $jc(_$hash, script.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DocentAudioRequest')
          ..add('language', language)
          ..add('script', script))
        .toString();
  }
}

class DocentAudioRequestBuilder
    implements Builder<DocentAudioRequest, DocentAudioRequestBuilder> {
  _$DocentAudioRequest? _$v;

  String? _language;
  String? get language => _$this._language;
  set language(String? language) => _$this._language = language;

  String? _script;
  String? get script => _$this._script;
  set script(String? script) => _$this._script = script;

  DocentAudioRequestBuilder() {
    DocentAudioRequest._defaults(this);
  }

  DocentAudioRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _language = $v.language;
      _script = $v.script;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DocentAudioRequest other) {
    _$v = other as _$DocentAudioRequest;
  }

  @override
  void update(void Function(DocentAudioRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DocentAudioRequest build() => _build();

  _$DocentAudioRequest _build() {
    final _$result = _$v ??
        _$DocentAudioRequest._(
          language: language,
          script: BuiltValueNullFieldError.checkNotNull(
              script, r'DocentAudioRequest', 'script'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
