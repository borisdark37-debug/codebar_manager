import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage chiffré du token Sanctum et des préférences sensibles.
class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _roleKey = 'auth_role';
  static const _userNameKey = 'auth_user_name';
  static const _userEmailKey = 'auth_user_email';
  static const _authModeKey = 'auth_mode'; // 'local' | 'server'
  static const _themeModeKey = 'app_theme_mode'; // 'light' | 'dark' | 'system'

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> saveUser({
    required String role,
    required String name,
    String? email,
  }) async {
    await _storage.write(key: _roleKey, value: role);
    await _storage.write(key: _userNameKey, value: name);
    if (email != null && email.isNotEmpty) {
      await _storage.write(key: _userEmailKey, value: email);
    } else {
      await _storage.delete(key: _userEmailKey);
    }
  }

  Future<String?> getRole() => _storage.read(key: _roleKey);
  Future<String?> getUserName() => _storage.read(key: _userNameKey);
  Future<String?> getUserEmail() => _storage.read(key: _userEmailKey);

  Future<void> saveUserEmail(String email) =>
      _storage.write(key: _userEmailKey, value: email);

  /// Mode d'authentification actif : 'local' (super_admin) ou 'server' (autres).
  Future<String?> getAuthMode() => _storage.read(key: _authModeKey);

  Future<void> saveAuthMode(String mode) =>
      _storage.write(key: _authModeKey, value: mode);

  Future<String?> getThemeMode() => _storage.read(key: _themeModeKey);

  Future<void> saveThemeMode(String mode) =>
      _storage.write(key: _themeModeKey, value: mode);

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _userNameKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _authModeKey);
  }

  Future<bool> hasToken() async => (await getToken()) != null;
}
