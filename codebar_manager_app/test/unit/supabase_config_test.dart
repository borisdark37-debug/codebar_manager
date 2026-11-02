import 'package:codebar_manager_app/core/config/api_config.dart';
import 'package:codebar_manager_app/core/config/supabase_config.dart';
import 'package:codebar_manager_app/core/services/api_client.dart';
import 'package:codebar_manager_app/core/services/auth_service.dart';
import 'package:codebar_manager_app/core/services/secure_stokage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class MockTestApiClient extends ApiClient {
  String? lastPath;
  dynamic lastData;

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) async {
    lastPath = path;
    lastData = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {
        'token': 'mock-test-token',
        'user': {
          'name': 'Capucine Bolo',
          'email': 'capucine@gmail.com',
          'role': 'super_admin',
        },
      } as T,
    );
  }
}

class TestInMemoryStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> saveToken(String token) async => _data['token'] = token;
  @override
  Future<String?> getToken() async => _data['token'];
  @override
  Future<bool> hasToken() async => _data.containsKey('token');
  @override
  Future<void> deleteToken() async => _data.remove('token');
  @override
  Future<void> saveAuthMode(String mode) async => _data['auth_mode'] = mode;
  @override
  Future<String?> getAuthMode() async => _data['auth_mode'];
  @override
  Future<void> saveUser({required String role, required String name, String? email}) async {
    _data['role'] = role;
    _data['name'] = name;
    if (email != null) _data['email'] = email;
  }
  @override
  Future<String?> getRole() async => _data['role'];
  @override
  Future<String?> getUserName() async => _data['name'];
  @override
  Future<String?> getUserEmail() async => _data['email'];
}

void main() {
  group('Supabase Configuration & Auth Service Tests', () {
    test('SupabaseConfig holds valid production URL and anon key', () {
      expect(SupabaseConfig.url, 'https://mpcpofrzuifoqcqrqlke.supabase.co');
      expect(SupabaseConfig.anonKey, 'sb_publishable_LxlHgIMSNTlCF3Q31C8GAA_1aHzFLHW');
    });

    test('ApiConfig is synchronized with Supabase project reference', () {
      expect(ApiConfig.supabaseUrl, 'https://mpcpofrzuifoqcqrqlke.supabase.co');
      expect(ApiConfig.supabaseAnonKey, 'sb_publishable_LxlHgIMSNTlCF3Q31C8GAA_1aHzFLHW');
      expect(ApiConfig.baseUrl, 'https://mpcpofrzuifoqcqrqlke.supabase.co/rest/v1');
    });

    test('AuthService logs in via API fallback when Supabase client is headless', () async {
      final mockApi = MockTestApiClient();
      final storage = TestInMemoryStorage();
      final authService = AuthService(mockApi, storage);

      await authService.login(
        email: 'capucine@gmail.com',
        password: 'Password123!',
        deviceName: 'TestDevice',
      );

      expect(await authService.isAuthenticated(), isTrue);
      expect(await authService.role(), 'super_admin');
      expect(await storage.getUserName(), 'Capucine Bolo');
      expect(await storage.getUserEmail(), 'capucine@gmail.com');
      expect(mockApi.lastPath, '/login');
    });

    test('AuthService logout clears session token and storage', () async {
      final mockApi = MockTestApiClient();
      final storage = TestInMemoryStorage();
      final authService = AuthService(mockApi, storage);

      await authService.login(
        email: 'borisdark37@gmail.com',
        password: 'Password123!',
        deviceName: 'TestDevice',
      );
      expect(await authService.isAuthenticated(), isTrue);

      await authService.logout();
      expect(await authService.isAuthenticated(), isFalse);
    });
  });
}
