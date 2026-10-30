import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gère l'authentification locale du super_admin.
/// Le mot de passe est stocké sous forme de hash SHA-256 avec salt.
/// Aucun appel réseau — fonctionne entièrement hors ligne.
class LocalAuthService {
  static const _storage = FlutterSecureStorage();

  static const _keyEmail = 'local_admin_email';
  static const _keySalt = 'local_admin_salt';
  static const _keyHash = 'local_admin_hash';
  static const _keySetup = 'local_admin_setup';
  static const _keyPlainPass = 'local_admin_plain_pass';

  /// Indique si le super_admin a déjà été configuré sur cet appareil.
  Future<bool> isSetup() async {
    return (await _storage.read(key: _keySetup)) == 'true';
  }

  /// Retourne l'email du super_admin local (ou null si non configuré).
  Future<String?> getEmail() => _storage.read(key: _keyEmail);

  /// Retourne le mot de passe local pour la migration serveur (ou null si déjà synchronisé).
  Future<String?> getPlainPassword() => _storage.read(key: _keyPlainPass);

  /// Met à jour manuellement le mot de passe en mémoire sécurisée.
  Future<void> savePlainPassword(String password) =>
      _storage.write(key: _keyPlainPass, value: password);

  /// Supprime le mot de passe en clair après synchronisation réussie.
  Future<void> clearPlainPassword() => _storage.delete(key: _keyPlainPass);

  /// Configure le super_admin local pour la première fois.
  /// [email] doit correspondre au compte super_admin sur le serveur.
  /// [password] est hashé avec un salt aléatoire avant stockage.
  Future<void> setup(String email, String password) async {
    final salt = _generateSalt(email);
    final hash = _hashPassword(password, salt);

    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
    await _storage.write(key: _keySetup, value: 'true');
    await _storage.write(key: _keyPlainPass, value: password);
  }

  /// Vérifie les identifiants locaux.
  /// Retourne true si [email] et [password] correspondent aux données stockées.
  Future<bool> verify(String email, String password) async {
    final storedEmail = await _storage.read(key: _keyEmail);
    if (storedEmail == null || storedEmail != email) return false;

    final salt = await _storage.read(key: _keySalt);
    final storedHash = await _storage.read(key: _keyHash);
    if (salt == null || storedHash == null) return false;

    return _hashPassword(password, salt) == storedHash;
  }

  /// Réinitialise le mot de passe du super_admin local à '0000'.
  Future<void> resetPassword() async {
    final email = await getEmail();
    if (email == null) return;
    final salt = _generateSalt('${email}_reset_${DateTime.now().millisecondsSinceEpoch}');
    final hash = _hashPassword('0000', salt);
    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
    await _storage.write(key: _keyPlainPass, value: '0000');
  }

  /// Change le mot de passe du super_admin local.
  Future<void> changePassword(String newPassword) async {
    final email = await getEmail();
    if (email == null) return;
    final salt = _generateSalt('${email}_change_${DateTime.now().millisecondsSinceEpoch}');
    final hash = _hashPassword(newPassword, salt);
    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
    await _storage.write(key: _keyPlainPass, value: newPassword);
  }

  /// Supprime les données locales du super_admin (réinitialisation).
  Future<void> clear() async {
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyHash);
    await _storage.delete(key: _keySetup);
    await _storage.delete(key: _keyPlainPass);
  }

  // --- Fonctions de hachage privées ---

  /// Génère un salt déterministe basé sur l'email + un timestamp.
  String _generateSalt(String email) {
    final raw = '$email-${DateTime.now().microsecondsSinceEpoch}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  String _hashPassword(String password, String salt) {
    final combined = '$salt:$password';
    return sha256.convert(utf8.encode(combined)).toString();
  }
}
