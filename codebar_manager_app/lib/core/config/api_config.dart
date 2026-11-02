
class ApiConfig {
  ApiConfig._();

  /// URL de l'instance Supabase Cloud de production
  static const String supabaseUrl = 'https://mpcpofrzuifoqcqrqlke.supabase.co';

  /// Clé d'API publique / publishable Supabase (Anon Key)
  static const String supabaseAnonKey =
      'sb_publishable_LxlHgIMSNTlCF3Q31C8GAA_1aHzFLHW';

  /// URL de l'API REST de production hébergée sur Supabase PostgREST
  static const String liveBaseUrl = 'https://mpcpofrzuifoqcqrqlke.supabase.co/rest/v1';

  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    return liveBaseUrl;
  }

  /// Temps de réponse de 30 secondes pour toutes les requêtes (CRUD, sync, logs).
  static const Duration timeout = Duration(seconds: 30);

  /// Temps de réponse maximal de 20 secondes pour les requêtes de connexion / login.
  static const Duration loginTimeout = Duration(seconds: 20);
}
