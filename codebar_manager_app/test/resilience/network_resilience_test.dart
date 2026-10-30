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

class ChaosMockApiClient extends ApiClient {
  final Future<Response<T>> Function<T>(String path, {dynamic data})? postHandler;
  final Future<Response<T>> Function<T>(String path, {Map<String, dynamic>? queryParameters})? getHandler;

  ChaosMockApiClient({this.postHandler, this.getHandler});

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) async {
    final handler = postHandler;
    if (handler != null) {
      return handler<T>(path, data: data);
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options}) async {
    final handler = getHandler;
    if (handler != null) {
      return handler<T>(path, queryParameters: queryParameters);
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'containsKey') return true;
    if (methodCall.method == 'read') return 'mock-token';
    return null;
  });

  late Directory tempDir;
  late Isar isar;
  late ProductRepository productRepo;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: false);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resilience_test_');
    isar = await Isar.open(
      [ProductSchema, AppSequenceSchema, AppUserSchema, SyncMutationSchema],
      directory: tempDir.path,
      name: 'resilience_db_${DateTime.now().microsecondsSinceEpoch}',
    );
    productRepo = ProductRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Network Resilience and Chaos Tests', () {
    test('Simulated connection timeout during push does not drop mutations and reports fatal error', () async {
      final product = await productRepo.create(
        name: 'Produit Résilience Timeout',
        format: '50ml',
        containment: 'Flacon',
        price: 25.0,
      );

      final chaosClient = ChaosMockApiClient(
        postHandler: <T>(path, {data}) async {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            type: DioExceptionType.connectionTimeout,
            error: 'Connection timed out after 5000ms',
          );
        },
      );

      final syncService = SyncService(isar, chaosClient, NotificationService());
      final result = await syncService.pushPending(forceOnline: true);

      expect(result.hasErrors, isTrue);
      expect(result.fatalError, isNotNull);

      // Les mutations dans l'Outbox doivent être scrupuleusement conservées en pending
      final mutations = await isar.syncMutations
          .filter()
          .entityIdEqualTo(product.uuid)
          .findAll();
      expect(mutations.length, 1);
      expect(mutations.first.status, MutationStatus.pending);
    });

    test('Simulated HTTP 500 Internal Server Error handled without application crash', () async {
      await productRepo.create(
        name: 'Produit 500 Error',
        format: '100ml',
        containment: 'Pot',
        price: 15.0,
      );

      final chaosClient = ChaosMockApiClient(
        postHandler: <T>(path, {data}) async {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 500,
              data: {'message': 'Database connection dead on server'},
            ),
          );
        },
      );

      final syncService = SyncService(isar, chaosClient, NotificationService());
      final result = await syncService.pushPending(forceOnline: true);

      expect(result.hasErrors, isTrue);
      expect(result.fatalError, contains('serveur'));
    });

    test('Corrupted or malformed JSON payload from server during pull is handled cleanly', () async {
      final chaosClient = ChaosMockApiClient(
        getHandler: <T>(path, {queryParameters}) async {
          return Response<T>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: <String, dynamic>{
              'status': 'corrupted_state',
              'products': 'not_a_list', // Type corrompu
            } as T,
          );
        },
      );

      final syncService = SyncService(isar, chaosClient, NotificationService());
      final result = await syncService.pullDelta(forceOnline: true);

      // Doit rapporter une erreur sans crasher
      expect(result.hasErrors, isTrue);
      expect(result.fatalError, isNotNull);
    });

    test('Simulated mid-push network connection drop retains all pending mutations safely', () async {
      final p1 = await productRepo.create(
        name: 'Produit Coupure Mi-Push 1',
        format: '30ml',
        containment: 'Flacon',
        price: 20.0,
      );
      final p2 = await productRepo.create(
        name: 'Produit Coupure Mi-Push 2',
        format: '50ml',
        containment: 'Tube',
        price: 15.0,
      );

      final chaosClient = ChaosMockApiClient(
        postHandler: <T>(path, {data}) async {
          // Simulation d'une interruption brutale de la connexion pendant l'envoi
          throw DioException(
            requestOptions: RequestOptions(path: path),
            type: DioExceptionType.connectionError,
            error: const SocketException('Connection reset by peer during transfer'),
          );
        },
      );

      final syncService = SyncService(isar, chaosClient, NotificationService());
      final result = await syncService.pushPending(forceOnline: true);

      expect(result.hasErrors, isTrue);
      expect(result.fatalError, isNotNull);

      // Les deux mutations doivent être scrupuleusement conservées en statut pending
      final p1Mutation = await isar.syncMutations.filter().entityIdEqualTo(p1.uuid).findFirst();
      expect(p1Mutation?.status, MutationStatus.pending);

      final p2Mutation = await isar.syncMutations.filter().entityIdEqualTo(p2.uuid).findFirst();
      expect(p2Mutation?.status, MutationStatus.pending);
    });
  });
}
