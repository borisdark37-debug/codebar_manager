import 'package:codebar_manager_app/core/services/secure_stokage_service.dart';
import 'package:dio/dio.dart';

import '../config/api_config.dart';

/// Client HTTP configuré pour l'API Laravel avec injection automatique
/// du token Sanctum sur chaque requête authentifiée.
class ApiClient {
  final Dio _dio;
  final SecureStorageService _storage;

  Dio get dio => _dio;

  ApiClient({Dio? dio, SecureStorageService? storage})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: ApiConfig.timeout,
                receiveTimeout: ApiConfig.timeout,
                sendTimeout: ApiConfig.timeout,
                headers: {'Accept': 'application/json'},
              ),
            ),
        _storage = storage ?? SecureStorageService() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _dio.post<T>(path, data: data, options: options);
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _dio.patch<T>(path, data: data, options: options);
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _dio.delete<T>(path, data: data, options: options);
  }
}
