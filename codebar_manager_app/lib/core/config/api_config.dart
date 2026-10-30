
class ApiConfig {
  ApiConfig._();

  /// URL de l'API de production hébergée sur Render Cloud
  static const String liveBaseUrl = 'https://codebar-manager-backend.onrender.com/api';

  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // Backend Render en production par défaut (accessible depuis Android, iOS, Windows, Mac, Linux et Web)
    return liveBaseUrl;
  }

  /// Temps de réponse de 30 secondes pour toutes les requêtes (CRUD, sync, logs).
  static const Duration timeout = Duration(seconds: 30);

  /// Temps de réponse maximal de 20 secondes pour les requêtes de connexion / login.
  static const Duration loginTimeout = Duration(seconds: 20);
}
