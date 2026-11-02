class SupabaseConfig {
  SupabaseConfig._();

  /// URL officielle du projet Supabase Cloud CodeBar Manager
  static const String defaultUrl = 'https://mpcpofrzuifoqcqrqlke.supabase.co';

  /// Clé d'API publique / publishable (Anon)
  static const String defaultAnonKey =
      'sb_publishable_LxlHgIMSNTlCF3Q31C8GAA_1aHzFLHW';

  static String get url {
    const envUrl = String.fromEnvironment('SUPABASE_URL');
    return envUrl.isNotEmpty ? envUrl : defaultUrl;
  }

  static String get anonKey {
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    return envKey.isNotEmpty ? envKey : defaultAnonKey;
  }

  static String get publishableKey => anonKey;
}
