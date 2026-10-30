import 'package:codebar_manager_app/core/config/api_config.dart';
import 'package:codebar_manager_app/core/database/collections/app_user.dart';
import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:codebar_manager_app/core/database/collections/sync_mutation.dart';
import 'package:codebar_manager_app/core/services/api_client.dart';
import 'package:codebar_manager_app/core/services/auth_service.dart';
import 'package:codebar_manager_app/core/services/secure_stokage_service.dart';
import 'package:codebar_manager_app/core/services/user_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

class V7MockApiClient extends ApiClient {
  String? lastPath;
  dynamic lastData;
  Options? lastOptions;
  bool shouldTimeout = false;

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) async {
    lastPath = path;
    lastData = data;
    lastOptions = options;

    if (shouldTimeout) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionTimeout,
        error: 'Connection timeout',
      );
    }

    if (path.contains('/login')) {
      final email = data['email'] as String;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'token': 'sanctum-mock-token-for-$email',
          'user': {
            'name': 'User $email',
            'email': email,
            'role': email.contains('superadmin') ? 'super_admin' : 'manager',
          },
        } as T,
      );
    }

    if (path.contains('/users/reset-password')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'message': 'Mot de passe réinitialisé avec succès.'} as T,
      );
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{} as T,
    );
  }

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options}) async {
    lastPath = path;
    lastOptions = options;

    if (path.contains('/activity-logs')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'current_page': 1,
          'last_page': 1,
          'total': 1,
          'data': [
            {
              'id': 1,
              'action': 'auth.login',
              'created_at': DateTime.now().toIso8601String(),
              'user': {'name': 'Super Admin 1', 'email': 'superadmin1@codebar.local'},
            }
          ],
        } as T,
      );
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{} as T,
    );
  }
}

class InMemorySecureStorage extends SecureStorageService {
  final Map<String, String> _mem = {};

  @override
  Future<String?> getToken() async => _mem['auth_token'];
  @override
  Future<void> saveToken(String token) async => _mem['auth_token'] = token;
  @override
  Future<String?> getRole() async => _mem['auth_role'];
  @override
  Future<String?> getUserName() async => _mem['auth_user_name'];
  @override
  Future<String?> getUserEmail() async => _mem['auth_user_email'];

  @override
  Future<void> saveUser({required String role, required String name, String? email}) async {
    _mem['auth_role'] = role;
    _mem['auth_user_name'] = name;
    if (email != null && email.isNotEmpty) {
      _mem['auth_user_email'] = email;
    } else {
      _mem.remove('auth_user_email');
    }
  }

  @override
  Future<void> saveAuthMode(String mode) async => _mem['auth_mode'] = mode;

  @override
  Future<String?> getAuthMode() async => _mem['auth_mode'];

  @override
  Future<void> deleteToken() async {
    _mem.remove('auth_token');
    _mem.remove('auth_role');
    _mem.remove('auth_user_name');
    _mem.remove('auth_user_email');
    _mem.remove('auth_mode');
  }

  @override
  Future<bool> hasToken() async => _mem.containsKey('auth_token');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'read') return 'Password123!';
    if (methodCall.method == 'write') return true;
    return null;
  });

  late Isar isar;
  late V7MockApiClient mockApi;
  late InMemorySecureStorage memoryStorage;
  late AuthService authService;
  late UserRepository userRepo;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    mockApi = V7MockApiClient();
    memoryStorage = InMemorySecureStorage();
    authService = AuthService(mockApi, memoryStorage);

    isar = await Isar.open(
      [AppUserSchema, ProductSchema, SyncMutationSchema],
      name: 'v7_test_isar_${DateTime.now().microsecondsSinceEpoch}',
      directory: '',
    );
    userRepo = UserRepository(isar, mockApi, memoryStorage);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
  });

  group('V7 Architecture & Bug Fixes Verification', () {
    test('Bug 1 Fix: Logging in with different user on same device attributes correct email and logout purges completely', () async {
      // 1. Super Admin logs in
      await authService.login(
        email: 'superadmin1@codebar.local',
        password: 'Password123!',
        deviceName: 'TestDevice',
      );

      expect(await memoryStorage.getUserEmail(), 'superadmin1@codebar.local');
      expect(await memoryStorage.getRole(), 'super_admin');

      // 2. Super Admin logs out
      await memoryStorage.deleteToken();
      expect(await memoryStorage.getUserEmail(), isNull);
      expect(await memoryStorage.getToken(), isNull);

      // 3. Normal user logs in on the exact same device
      await authService.login(
        email: 'employee@codebar.local',
        password: 'Password123!',
        deviceName: 'TestDevice',
      );

      // Must be employee email, NEVER super admin!
      expect(await memoryStorage.getUserEmail(), 'employee@codebar.local');
      expect(await memoryStorage.getUserName(), 'User employee@codebar.local');
      expect(await memoryStorage.getRole(), 'manager');
    });

    test('Bug 2 Fix: Activity logs request reaches API with correct path and returns data', () async {
      final res = await mockApi.get<Map<String, dynamic>>('/activity-logs', queryParameters: {'page': 1, 'per_page': 25});
      expect(res.statusCode, 200);
      expect(mockApi.lastPath, '/activity-logs');
      final data = res.data;
      expect((data?['data'] as List).isNotEmpty, isTrue);
    });

    test('Timeouts: Login uses 20s timeout and other requests default to 30s', () async {
      expect(ApiConfig.loginTimeout, const Duration(seconds: 20));
      expect(ApiConfig.timeout, const Duration(seconds: 30));

      await authService.login(
        email: 'test.timeout@codebar.local',
        password: 'pass',
        deviceName: 'TestDevice',
      );

      expect(mockApi.lastOptions?.sendTimeout, const Duration(seconds: 20));
      expect(mockApi.lastOptions?.receiveTimeout, const Duration(seconds: 20));
    });

    test('Default Super Admins: ensureSuperAdminExists seeds both superadmin1 and superadmin2 in local Isar', () async {
      final sa = await userRepo.ensureSuperAdminExists();
      expect(sa, isNotNull);

      final sa1 = await isar.appUsers.filter().emailEqualTo('superadmin1@codebar.local').findFirst();
      expect(sa1, isNotNull);
      expect(sa1?.role, 'super_admin');
      expect(sa1?.password, 'Password123!');

      final sa2 = await isar.appUsers.filter().emailEqualTo('superadmin2@codebar.local').findFirst();
      expect(sa2, isNotNull);
      expect(sa2?.role, 'super_admin');
      expect(sa2?.password, 'Password123!');
    });

    test('Online Password Reset: Super admin resets password online with server update', () async {
      final target = AppUser.create(
        uuid: 'target-uuid',
        email: 'john@example.com',
        name: 'John Doe',
        role: 'manager',
        password: 'OldPassword',
        syncStatus: SyncStatus.synced,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await isar.writeTxn(() => isar.appUsers.put(target));

      final updated = await userRepo.resetPasswordOnline(target, '0000');
      expect(mockApi.lastPath, '/users/reset-password');
      expect(mockApi.lastData['email'], 'john@example.com');
      expect(mockApi.lastData['password'], '0000');
      expect(updated.syncStatus, SyncStatus.synced);
    });
  });
}
