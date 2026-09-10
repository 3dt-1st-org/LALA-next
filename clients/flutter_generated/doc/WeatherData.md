# lala_next_flutter_client_generated.model.WeatherData

## Load the model package
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**airQualityOutdoorStatus** | **String** | Observed air-quality status derived only from the normalized dust grades (bad/very_bad → bad, good/normal → good); an unknown dust grade stays 'unknown'. | [optional] 
**dust** | [**Dust**](Dust.md) |  | 
**force** | **bool** |  | 
**forecast** | [**BuiltList&lt;ForecastItem&gt;**](ForecastItem.md) |  | 
**icon** | **String** |  | 
**lat** | **double** |  | 
**lng** | **double** |  | 
**location** | **String** |  | [optional] 
**locationMatch** | **bool** |  | [optional] 
**outdoorStatus** | **String** |  | 
**recordTime** | **String** |  | [optional] 
**source_** | **String** |  | 
**temp** | **String** |  | 
**weatherOutdoorStatus** | **String** | Observed weather-only status (KMA nowcast / DB weather flags without the dust flag); 'unknown' when no weather observation exists (an AirKorea-only response or a payload without the explicit provenance key) — never inferred from the merged outdoor_status. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


