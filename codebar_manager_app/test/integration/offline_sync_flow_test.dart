import 'dart:io';
import 'package:codebar_manager_app/core/database/collections/app_sequence.dart';
import 'package:codebar_manager_app/core/database/collections/app_user.dart';
import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:codebar_manager_app/core/database/collections/sync_mutation.dart';
import 'package:codebar_manager_app/core/services/api_client.dart';
import 'package:codebar_manager_app/core/services/notification_service.dart';
import 'package:codebar_manager_app/core/services/product_repository.dart';
import 'package:codebar_manager_app/core/services/sync_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

class FlowTestApiClient extends ApiClient {
  final Map<String, dynamic> Function(String path, dynamic data)? postCallback;
  final Map<String, dynamic> Function(String path, Map<String, dynamic>? queryParams)? getCallback;

  FlowTestApiClient({this.postCallback, this.getCallback});

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) async {
    if (postCallback != null) {
      final res = postCallback!(path, data);
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: res as T,
        statusCode: 200,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: <String, dynamic>{} as T,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (getCallback != null) {
      final res = getCallback!(path, queryParameters);
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: res as T,
        statusCode: 200,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: <String, dynamic>{} as T,
      statusCode: 200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> secureStorageMock = {'token': 'valid-sanctum-token'};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'read') {
      final key = methodCall.arguments['key'];
      return secureStorageMock[key];
    }
    if (methodCall.method == 'write') {
      final key = methodCall.arguments['key'];
      final val = methodCall.arguments['value'];
      secureStorageMock[key] = val;
      return true;
    }
    if (methodCall.method == 'containsKey') {
      final key = methodCall.arguments['key'];
      return secureStorageMock.containsKey(key);
    }
    return null;
  });

  late Directory tempDir;
  late Isar isar;
  late ProductRepository productRepo;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: false);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flow_test_');
    isar = await Isar.open(
      [ProductSchema, AppSequenceSchema, AppUserSchema, SyncMutationSchema],
      directory: tempDir.path,
      name: 'flow_db_${DateTime.now().microsecondsSinceEpoch}',
    );
    productRepo = ProductRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Offline-to-Online End-to-End Flow Tests', () {
    test('Offline product creation -> Push to server -> Outbox synced -> Pull delta reconciliation', () async {
      // 1. Étape Hors-ligne : Création locale d'un produit
      final localProd = await productRepo.create(
        name: 'Baume Réparateur Nuit',
        format: '50ml',
        containment: 'Pot verre',
        price: 32.0,
        quantity: 12,
      );

      expect(localProd.internalCode, 'CAP-0001');
      expect(localProd.syncStatus, SyncStatus.pending);

      // Vérification que la mutation est bien en attente dans l'Outbox
      final pendingMutations = await isar.syncMutations
          .filter()
          .statusEqualTo(MutationStatus.pending)
          .findAll();
      expect(pendingMutations.length, 1);
      expect(pendingMutations.first.entityId, localProd.uuid);

      // 2. Étape En-ligne : Push vers Laravel
      final apiClient = FlowTestApiClient(
        postCallback: (path, data) {
          if (path.contains('/sync/push') || path.contains('/sync')) {
            return {
              'status': 'success',
              'server_time': DateTime.now().toIso8601String(),
              'results': [
                {
                  'idempotency_key': pendingMutations.first.idempotencyKey,
                  'uuid': localProd.uuid,
                  'status': 'synced',
                }
              ],
            };
          }
          if (path.contains('/migrate-super-admin')) {
            return {
              'token': 'mock-migrated-token',
              'user': {'role': 'super_admin'},
            };
          }
          return {};
        },
        getCallback: (path, queryParams) {
          if (path.contains('/health')) {
            return {'status': 'ok'};
          }
          if (path.contains('/sync/pull')) {
            return {
              'status': 'success',
              'server_time': DateTime.now().toIso8601String(),
              'products': [
                {
                  'uuid': 'server-prod-uuid-99',
                  'internal_code': 'CAP-SERVER-99',
                  'name': 'Produit Découvert Serveur',
                  'format': '100ml',
                  'containment': 'Flacon',
                  'price': 19.99,
                  'quantity': 5,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                }
              ],
              'tombstones': {
                'products': <String>[],
                'force_deleted_products': <String>[],
                'users': <String>[],
              },
            };
          }
          return {};
        },
      );

      final syncService = SyncService(isar, apiClient, NotificationService());

      // Exécution du push
      final pushResult = await syncService.pushPending(forceOnline: true);
      expect(pushResult.hasErrors, isFalse);

      // Vérification que la mutation Outbox locale est passée à synced
      final syncedMutations = await isar.syncMutations
          .filter()
          .statusEqualTo(MutationStatus.synced)
          .findAll();
      expect(syncedMutations.length, 1);

      // 3. Exécution du pull delta
      final pullResult = await syncService.pullDelta(forceOnline: true);
      expect(pullResult.hasErrors, isFalse);

      // Vérification que le nouveau produit provenant du serveur a été persisté localement
      final serverProduct = await isar.products
          .filter()
          .uuidEqualTo('server-prod-uuid-99')
          .findFirst();
      expect(serverProduct, isNotNull);
      expect(serverProduct?.name, 'Produit Découvert Serveur');
      expect(serverProduct?.internalCode, 'CAP-SERVER-99');
    });
  });
}
