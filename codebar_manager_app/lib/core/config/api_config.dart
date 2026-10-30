import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Émulateur Android standard : 10.0.2.2 pointe vers le localhost de la machine hôte
      return 'http://10.0.2.2:8000/api';
    }

    // Application Windows / Desktop / Web
    return 'http://127.0.0.1:8000/api';
  }

  /// Temps de réponse de 30 secondes pour toutes les requêtes (CRUD, sync, logs).
  static const Duration timeout = Duration(seconds: 30);

  /// Temps de réponse maximal de 20 secondes pour les requêtes de connexion / login.
  static const Duration loginTimeout = Duration(seconds: 20);
}
