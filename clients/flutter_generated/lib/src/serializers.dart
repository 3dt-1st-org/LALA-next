//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:lala_next_flutter_client_generated/src/date_serializer.dart';
import 'package:lala_next_flutter_client_generated/src/model/date.dart';

import 'package:lala_next_flutter_client_generated/src/model/account_deletion_request.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_error.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_error_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_meta.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/coordinate.dart';
import 'package:lala_next_flutter_client_generated/src/model/daily_plan_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/daily_plan_request.dart';
import 'package:lala_next_flutter_client_generated/src/model/daily_plan_slot.dart';
import 'package:lala_next_flutter_client_generated/src/model/daily_plan_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/docent_audio_request.dart';
import 'package:lala_next_flutter_client_generated/src/model/docent_script_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/docent_script_request.dart';
import 'package:lala_next_flutter_client_generated/src/model/docent_script_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/dust.dart';
import 'package:lala_next_flutter_client_generated/src/model/forecast_item.dart';
import 'package:lala_next_flutter_client_generated/src/model/http_validation_error.dart';
import 'package:lala_next_flutter_client_generated/src/model/healthz_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/healthz_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/intervention_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/intervention_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/me_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/me_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/place.dart';
import 'package:lala_next_flutter_client_generated/src/model/place_score.dart';
import 'package:lala_next_flutter_client_generated/src/model/place_score_components.dart';
import 'package:lala_next_flutter_client_generated/src/model/places_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/places_query.dart';
import 'package:lala_next_flutter_client_generated/src/model/places_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/readiness_checks.dart';
import 'package:lala_next_flutter_client_generated/src/model/readyz_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/readyz_success_envelope.dart';
import 'package:lala_next_flutter_client_generated/src/model/runtime_mode.dart';
import 'package:lala_next_flutter_client_generated/src/model/validation_error.dart';
import 'package:lala_next_flutter_client_generated/src/model/validation_error_loc_inner.dart';
import 'package:lala_next_flutter_client_generated/src/model/weather_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/weather_success_envelope.dart';

part 'serializers.g.dart';

@SerializersFor([
  AccountDeletionRequest,
  ApiError,
  ApiErrorEnvelope,
  ApiMeta,
  ApiSuccessEnvelope,
  Coordinate,
  DailyPlanData,
  DailyPlanRequest,
  DailyPlanSlot,
  DailyPlanSuccessEnvelope,
  DocentAudioRequest,
  DocentScriptData,
  DocentScriptRequest,
  DocentScriptSuccessEnvelope,
  Dust,
  ForecastItem,
  HTTPValidationError,
  HealthzData,
  HealthzSuccessEnvelope,
  InterventionData,
  InterventionSuccessEnvelope,
  MeData,
  MeSuccessEnvelope,
  Place,
  PlaceScore,
  PlaceScoreComponents,
  PlacesData,
  PlacesQuery,
  PlacesSuccessEnvelope,
  ReadinessChecks,
  ReadyzData,
  ReadyzSuccessEnvelope,
  RuntimeMode,
  ValidationError,
  ValidationErrorLocInner,
  WeatherData,
  WeatherSuccessEnvelope,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer()))
    .build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
