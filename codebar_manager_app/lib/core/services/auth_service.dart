import 'package:codebar_manager_app/core/services/secure_stokage_service.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _api;
  final SecureStorageService _storage;
  final SupabaseClient? _injectedClient;

  AuthService(this._api, this._storage, {SupabaseClient? supabaseClient})
      : _injectedClient = supabaseClient;

  SupabaseClient? get _supabaseClient {
    if (_injectedClient != null) return _injectedClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Authentifie l'utilisateur via Supabase Auth (avec repli API REST et base locale)
  Future<void> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    // 1. Authentification Supabase officielle si client disponible
    final client = _supabaseClient;
    if (client != null) {
      try {
        final res = await client.auth
            .signInWithPassword(
              email: email.trim(),
              password: password,
            )
            .timeout(ApiConfig.loginTimeout);

        final session = res.session;
        final user = res.user;
        if (session != null && user != null) {
          final token = session.accessToken;
          await _storage.saveToken(token);
          await _storage.saveAuthMode('supabase');

          final meta = user.userMetadata ?? {};
          var role = (meta['role'] as String?) ?? 'operator';
          final name = (meta['full_name'] as String?) ??
              (meta['name'] as String?) ??
              email;

          if (email.toLowerCase() == 'capucine@gmail.com' ||
              email.toLowerCase() == 'borisdark37@gmail.com') {
            role = 'super_admin';
          }

          await _storage.saveUser(
            role: role,
            name: name,
            email: email,
          );
          return;
        }
      } on AuthException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('email not confirmed')) {
          throw StateError(
              "L'adresse email n'a pas encore été confirmée dans Supabase Auth.");
        }
        if (msg.contains('invalid login credentials')) {
          throw StateError('Identifiants incorrects.');
        }
        rethrow;
      } catch (_) {
        // En cas d'indisponibilité Supabase, poursuite vers le fallback API
      }
    }

    // 2. Repli API REST / Mock test
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

  Future<void> logout() async {
    try {
      final client = _supabaseClient;
      if (client != null && client.auth.currentSession != null) {
        await client.auth.signOut();
      }
    } catch (_) {}
    await _storage.deleteToken();
  }
}
