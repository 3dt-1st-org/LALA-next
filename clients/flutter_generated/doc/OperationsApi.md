# lala_next_flutter_client_generated.api.OperationsApi

## Load the API package
```dart
import 'package:lala_next_flutter_client_generated/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**healthzHealthzGet**](OperationsApi.md#healthzhealthzget) | **GET** /healthz | Healthz
[**metricsMetricsGet**](OperationsApi.md#metricsmetricsget) | **GET** /metrics | Metrics
[**readyzReadyzGet**](OperationsApi.md#readyzreadyzget) | **GET** /readyz | Readyz


# **healthzHealthzGet**
> HealthzSuccessEnvelope healthzHealthzGet()

Healthz

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';

final api = LalaNextFlutterClientGenerated().getOperationsApi();

try {
    final response = api.healthzHealthzGet();
    print(response);
} catch on DioException (e) {
    print('Exception when calling OperationsApi->healthzHealthzGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**HealthzSuccessEnvelope**](HealthzSuccessEnvelope.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **metricsMetricsGet**
> String metricsMetricsGet()

Metrics

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';

final api = LalaNextFlutterClientGenerated().getOperationsApi();

try {
    final response = api.metricsMetricsGet();
    print(response);
} catch on DioException (e) {
    print('Exception when calling OperationsApi->metricsMetricsGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

**String**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: text/plain

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **readyzReadyzGet**
> ReadyzSuccessEnvelope readyzReadyzGet()

Readyz

### Example
```dart
import 'package:lala_next_flutter_client_generated/api.dart';

final api = LalaNextFlutterClientGenerated().getOperationsApi();

try {
    final response = api.readyzReadyzGet();
    print(response);
} catch on DioException (e) {
    print('Exception when calling OperationsApi->readyzReadyzGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ReadyzSuccessEnvelope**](ReadyzSuccessEnvelope.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

