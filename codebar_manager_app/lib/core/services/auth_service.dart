import 'package:codebar_manager_app/core/services/secure_stokage_service.dart';
import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _api;
  final SecureStorageService _storage;

  AuthService(this._api, this._storage);

  /// Authentifie l'utilisateur via le serveur et stocke le token Sanctum (timeout max 20 secondes).
  Future<void> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/login',
      data: {'email': email, 'password': password, 'device_name': deviceName},
      options: Options(
        sendTimeout: ApiConfig.loginTimeout,
        receiveTimeout: ApiConfig.loginTimeout,
      ),
    );

    final token = response.data?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('Réponse du serveur invalide : token manquant.');
    }
    await _storage.saveToken(token);
    await _storage.saveAuthMode('server');

    final user = response.data?['user'] as Map<String, dynamic>?;
    if (user != null) {
      await _storage.saveUser(
        role: user['role'] as String? ?? 'manager',
        name: user['name'] as String? ?? email,
        email: user['email'] as String? ?? email,
      );
    } else {
      await _storage.saveUser(
        role: 'manager',
        name: email,
        email: email,
      );
    }
  }

  Future<bool> isAuthenticated() => _storage.hasToken();
  Future<String?> role() => _storage.getRole();

  Future<void> logout() => _storage.deleteToken();
}
