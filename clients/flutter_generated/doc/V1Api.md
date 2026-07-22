# lala_next_flutter_client_generated.api.V1Api

## Load the API package
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**dailyPlanApiV1PlansDailyPost**](V1Api.md#dailyplanapiv1plansdailypost) | **POST** /api/v1/plans/daily | Daily Plan
[**deleteMeApiV1MeDelete**](V1Api.md#deletemeapiv1medelete) | **DELETE** /api/v1/me | Delete Me
[**docentAudioApiV1DocentsAudioPost**](V1Api.md#docentaudioapiv1docentsaudiopost) | **POST** /api/v1/docents/audio | Docent Audio
[**docentScriptApiV1DocentsScriptPost**](V1Api.md#docentscriptapiv1docentsscriptpost) | **POST** /api/v1/docents/script | Docent Script
[**interventionApiV1PlansInterventionGet**](V1Api.md#interventionapiv1plansinterventionget) | **GET** /api/v1/plans/intervention | Intervention
[**meApiV1MeGet**](V1Api.md#meapiv1meget) | **GET** /api/v1/me | Me
[**placesApiV1PlacesGet**](V1Api.md#placesapiv1placesget) | **GET** /api/v1/places | Places
[**weatherApiV1WeatherGet**](V1Api.md#weatherapiv1weatherget) | **GET** /api/v1/weather | Weather


# **dailyPlanApiV1PlansDailyPost**
> DailyPlanSuccessEnvelope dailyPlanApiV1PlansDailyPost(dailyPlanRequest, xAPIKey, authorization)

Daily Plan

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
// TODO Configure API key authorization: MigrationApiKey
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKeyPrefix = 'Bearer';

final api = LalaNextFlutterClientGenerated().getV1Api();
final DailyPlanRequest dailyPlanRequest = ; // DailyPlanRequest | 
final String xAPIKey = xAPIKey_example; // String | 
final String authorization = authorization_example; // String | 

try {
    final response = api.dailyPlanApiV1PlansDailyPost(dailyPlanRequest, xAPIKey, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->dailyPlanApiV1PlansDailyPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **dailyPlanRequest** | [**DailyPlanRequest**](DailyPlanRequest.md)|  | 
 **xAPIKey** | **String**|  | [optional] 
 **authorization** | **String**|  | [optional] 

### Return type

[**DailyPlanSuccessEnvelope**](DailyPlanSuccessEnvelope.md)

### Authorization

[MigrationApiKey](../README.md#MigrationApiKey), [BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteMeApiV1MeDelete**
> deleteMeApiV1MeDelete(accountDeletionRequest)

Delete Me

Deletes the account for an OAuth identity issued by the current configured LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted.

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';

final api = LalaNextFlutterClientGenerated().getV1Api();
final AccountDeletionRequest accountDeletionRequest = ; // AccountDeletionRequest | 

try {
    api.deleteMeApiV1MeDelete(accountDeletionRequest);
} catch on DioException (e) {
    print('Exception when calling V1Api->deleteMeApiV1MeDelete: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **accountDeletionRequest** | [**AccountDeletionRequest**](AccountDeletionRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[OAuthBearerAuth](../README.md#OAuthBearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **docentAudioApiV1DocentsAudioPost**
> Uint8List docentAudioApiV1DocentsAudioPost(docentAudioRequest, xAPIKey, authorization)

Docent Audio

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
// TODO Configure API key authorization: MigrationApiKey
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKeyPrefix = 'Bearer';

final api = LalaNextFlutterClientGenerated().getV1Api();
final DocentAudioRequest docentAudioRequest = ; // DocentAudioRequest | 
final String xAPIKey = xAPIKey_example; // String | 
final String authorization = authorization_example; // String | 

try {
    final response = api.docentAudioApiV1DocentsAudioPost(docentAudioRequest, xAPIKey, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->docentAudioApiV1DocentsAudioPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **docentAudioRequest** | [**DocentAudioRequest**](DocentAudioRequest.md)|  | 
 **xAPIKey** | **String**|  | [optional] 
 **authorization** | **String**|  | [optional] 

### Return type

[**Uint8List**](Uint8List.md)

### Authorization

[MigrationApiKey](../README.md#MigrationApiKey), [BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: audio/mpeg, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **docentScriptApiV1DocentsScriptPost**
> DocentScriptSuccessEnvelope docentScriptApiV1DocentsScriptPost(docentScriptRequest, xAPIKey, authorization)

Docent Script

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
// TODO Configure API key authorization: MigrationApiKey
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKeyPrefix = 'Bearer';

final api = LalaNextFlutterClientGenerated().getV1Api();
final DocentScriptRequest docentScriptRequest = ; // DocentScriptRequest | 
final String xAPIKey = xAPIKey_example; // String | 
final String authorization = authorization_example; // String | 

try {
    final response = api.docentScriptApiV1DocentsScriptPost(docentScriptRequest, xAPIKey, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->docentScriptApiV1DocentsScriptPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **docentScriptRequest** | [**DocentScriptRequest**](DocentScriptRequest.md)|  | 
 **xAPIKey** | **String**|  | [optional] 
 **authorization** | **String**|  | [optional] 

### Return type

[**DocentScriptSuccessEnvelope**](DocentScriptSuccessEnvelope.md)

### Authorization

[MigrationApiKey](../README.md#MigrationApiKey), [BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **interventionApiV1PlansInterventionGet**
> InterventionSuccessEnvelope interventionApiV1PlansInterventionGet(lat, lng, radiusM, xAPIKey, authorization)

Intervention

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
// TODO Configure API key authorization: MigrationApiKey
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKeyPrefix = 'Bearer';

final api = LalaNextFlutterClientGenerated().getV1Api();
final num lat = 8.14; // num | 
final num lng = 8.14; // num | 
final int radiusM = 56; // int | 
final String xAPIKey = xAPIKey_example; // String | 
final String authorization = authorization_example; // String | 

try {
    final response = api.interventionApiV1PlansInterventionGet(lat, lng, radiusM, xAPIKey, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->interventionApiV1PlansInterventionGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **lat** | **num**|  | 
 **lng** | **num**|  | 
 **radiusM** | **int**|  | [optional] [default to 10000]
 **xAPIKey** | **String**|  | [optional] 
 **authorization** | **String**|  | [optional] 

### Return type

[**InterventionSuccessEnvelope**](InterventionSuccessEnvelope.md)

### Authorization

[MigrationApiKey](../README.md#MigrationApiKey), [BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **meApiV1MeGet**
> MeSuccessEnvelope meApiV1MeGet()

Me

Returns the local account for an OAuth identity issued by the current configured LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted.

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';

final api = LalaNextFlutterClientGenerated().getV1Api();

try {
    final response = api.meApiV1MeGet();
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->meApiV1MeGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**MeSuccessEnvelope**](MeSuccessEnvelope.md)

### Authorization

[OAuthBearerAuth](../README.md#OAuthBearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **placesApiV1PlacesGet**
> PlacesSuccessEnvelope placesApiV1PlacesGet(lat, lng, radiusM, category, lang, language, includeScores, limit, xAPIKey, authorization)

Places

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
// TODO Configure API key authorization: MigrationApiKey
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKeyPrefix = 'Bearer';

final api = LalaNextFlutterClientGenerated().getV1Api();
final num lat = 8.14; // num | 
final num lng = 8.14; // num | 
final int radiusM = 56; // int | 
final String category = category_example; // String | 
final String lang = lang_example; // String | 
final String language = language_example; // String | 
final bool includeScores = true; // bool | 
final int limit = 56; // int | 
final String xAPIKey = xAPIKey_example; // String | 
final String authorization = authorization_example; // String | 

try {
    final response = api.placesApiV1PlacesGet(lat, lng, radiusM, category, lang, language, includeScores, limit, xAPIKey, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->placesApiV1PlacesGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **lat** | **num**|  | 
 **lng** | **num**|  | 
 **radiusM** | **int**|  | [optional] [default to 1000]
 **category** | **String**|  | [optional] [default to 'all']
 **lang** | **String**|  | [optional] [default to 'ko']
 **language** | **String**|  | [optional] 
 **includeScores** | **bool**|  | [optional] [default to false]
 **limit** | **int**|  | [optional] [default to 60]
 **xAPIKey** | **String**|  | [optional] 
 **authorization** | **String**|  | [optional] 

### Return type

[**PlacesSuccessEnvelope**](PlacesSuccessEnvelope.md)

### Authorization

[MigrationApiKey](../README.md#MigrationApiKey), [BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **weatherApiV1WeatherGet**
> WeatherSuccessEnvelope weatherApiV1WeatherGet(lat, lng, force, xAPIKey, authorization)

Weather

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
// TODO Configure API key authorization: MigrationApiKey
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('MigrationApiKey').apiKeyPrefix = 'Bearer';

final api = LalaNextFlutterClientGenerated().getV1Api();
final num lat = 8.14; // num | 
final num lng = 8.14; // num | 
final bool force = true; // bool | 
final String xAPIKey = xAPIKey_example; // String | 
final String authorization = authorization_example; // String | 

try {
    final response = api.weatherApiV1WeatherGet(lat, lng, force, xAPIKey, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling V1Api->weatherApiV1WeatherGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **lat** | **num**|  | 
 **lng** | **num**|  | 
 **force** | **bool**|  | [optional] [default to false]
 **xAPIKey** | **String**|  | [optional] 
 **authorization** | **String**|  | [optional] 

### Return type

[**WeatherSuccessEnvelope**](WeatherSuccessEnvelope.md)

### Authorization

[MigrationApiKey](../README.md#MigrationApiKey), [BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

