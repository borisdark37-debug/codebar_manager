import 'dart:convert';
import 'package:codebar_manager_app/core/database/collections/sync_mutation.dart';
import 'package:codebar_manager_app/core/services/api_client.dart';
import 'package:codebar_manager_app/core/services/sync_service.dart';
import 'package:codebar_manager_app/features/sync/providers/sync_poviders.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApiClient extends ApiClient {
  final Map<String, dynamic> Function(String path, dynamic data)? postHandler;
  final Map<String, dynamic> Function(String path, Map<String, dynamic>? queryParams)? getHandler;

  FakeApiClient({this.postHandler, this.getHandler});

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) async {
    if (postHandler != null) {
      final res = postHandler!(path, data);
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
    if (getHandler != null) {
      final res = getHandler!(path, queryParameters);
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

class FakeSyncService implements SyncService {
  final Future<SyncResult> Function({bool forceOnline})? onSynchronize;
  final Future<SyncResult> Function({bool forceOnline})? onPush;
  final Future<SyncResult> Function({bool forceOnline})? onPull;

  FakeSyncService({
    this.onSynchronize,
    this.onPush,
    this.onPull,
  });

  @override
  Future<SyncResult> synchronize({bool forceOnline = false}) async {
    if (onSynchronize != null) return onSynchronize!(forceOnline: forceOnline);
    return SyncResult(synced: 5);
  }

  @override
  Future<SyncResult> pushPending({bool forceOnline = false}) async {
    if (onPush != null) return onPush!(forceOnline: forceOnline);
    return SyncResult(synced: 3, pushed: 3);
  }

  @override
  Future<SyncResult> pullDelta({bool forceOnline = false}) async {
    return pullAll(forceOnline: forceOnline);
  }

  @override
  Future<SyncResult> pullAll({bool forceOnline = false}) async {
    if (onPull != null) return onPull!(forceOnline: forceOnline);
    return SyncResult(synced: 2);
  }

  @override
  Future<DateTime?> getLastSyncAt() async => DateTime(2026, 10, 27, 14, 0);

  @override
  Future<bool> checkServerHealth() async => true;

  @override
  Future<bool> reconcileSuperAdmin() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SyncMutation Outbox Model Tests', () {
    test('SyncMutation initializes with correct pending status and serializes cleanly', () {
      final now = DateTime.now();
      final mutation = SyncMutation.create(
        idempotencyKey: 'idemp-1234',
        entityType: 'product',
        entityId: 'uuid-abcd',
        action: MutationAction.create,
        payloadJson: jsonEncode({
          'uuid': 'uuid-abcd',
          'internal_code': 'CAP-0001',
          'name': 'Test Outbox Product',
        }),
        createdAt: now,
      );

      expect(mutation.idempotencyKey, 'idemp-1234');
      expect(mutation.entityType, 'product');
      expect(mutation.entityId, 'uuid-abcd');
      expect(mutation.action, MutationAction.create);
      expect(mutation.status, MutationStatus.pending);
      expect(mutation.retryCount, 0);

      final decoded = jsonDecode(mutation.payloadJson) as Map<String, dynamic>;
      expect(decoded['name'], 'Test Outbox Product');
    });

    test('SyncMutation copyWith updates status, error and timestamp', () {
      final now = DateTime.now();
      final mutation = SyncMutation.create(
        idempotencyKey: 'idemp-1234',
        entityType: 'product',
        entityId: 'uuid-abcd',
        action: MutationAction.create,
        payloadJson: '{}',
        createdAt: now,
      );

      final synced = mutation.copyWith(
        status: MutationStatus.synced,
        syncedAt: now.add(const Duration(seconds: 1)),
      );

      expect(synced.status, MutationStatus.synced);
      expect(synced.syncedAt, isNotNull);
      expect(synced.lastError, isNull);

      final failed = mutation.copyWith(
        status: MutationStatus.failed,
        lastError: 'Conflict with server timestamp',
      );

      expect(failed.status, MutationStatus.failed);
      expect(failed.lastError, 'Conflict with server timestamp');
    });
  });

  group('SyncResult Computation Tests', () {
    test('SyncResult computes isFullSuccess correctly', () {
      final successResult = SyncResult(
        pushed: 4,
        synced: 4,
        conflicts: 0,
        errors: 0,
      );
      expect(successResult.isFullSuccess, isTrue);
      expect(successResult.hasErrors, isFalse);

      final emptyResult = SyncResult(
        pushed: 0,
        synced: 0,
        conflicts: 0,
        errors: 0,
      );
      expect(emptyResult.isFullSuccess, isTrue);

      final partialResult = SyncResult(
        pushed: 4,
        synced: 3,
        conflicts: 1,
        errors: 0,
      );
      expect(partialResult.isFullSuccess, isFalse);
      expect(partialResult.hasErrors, isTrue);

      final errorResult = SyncResult(
        fatalError: 'Connexion réseau impossible',
      );
      expect(errorResult.isFullSuccess, isFalse);
      expect(errorResult.hasErrors, isTrue);
    });
  });

  group('Online SyncController & StateNotifier Tests', () {
    test('SyncController synchronize moves from syncing to done with result', () async {
      final fakeService = FakeSyncService(
        onSynchronize: ({bool forceOnline = false}) async {
          return SyncResult(pushed: 2, synced: 2, serverTime: DateTime(2026, 10, 27, 14, 30));
        },
      );

      final container = ProviderContainer(
        overrides: [
          syncServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(syncControllerProvider.notifier);

      final res = await controller.synchronize(forceOnline: true);

      expect(res.isFullSuccess, isTrue);
      expect(res.synced, 2);

      final finalState = container.read(syncControllerProvider);
      expect(finalState.phase, SyncPhase.done);
      expect(finalState.lastResult?.synced, 2);
      expect(finalState.fatalMessage, isNull);
    });

    test('SyncController synchronize handles fatal errors cleanly without crash', () async {
      final fakeService = FakeSyncService(
        onSynchronize: ({bool forceOnline = false}) async {
          return SyncResult(fatalError: 'Serveur central indisponible (503)');
        },
      );

      final container = ProviderContainer(
        overrides: [
          syncServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(syncControllerProvider.notifier);
      final res = await controller.synchronize(forceOnline: true);

      expect(res.hasErrors, isTrue);
      final finalState = container.read(syncControllerProvider);
      expect(finalState.phase, SyncPhase.error);
      expect(finalState.fatalMessage, contains('Serveur central indisponible'));
    });

    test('SyncController pushPending and pullAll with forceOnline execute online calls', () async {
      bool pushCalled = false;
      bool pullCalled = false;

      final fakeService = FakeSyncService(
        onPush: ({bool forceOnline = false}) async {
          pushCalled = true;
          return SyncResult(pushed: 3, synced: 3);
        },
        onPull: ({bool forceOnline = false}) async {
          pullCalled = true;
          return SyncResult(synced: 1);
        },
      );

      final container = ProviderContainer(
        overrides: [
          syncServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(syncControllerProvider.notifier);

      await controller.pushPending(forceOnline: true);
      expect(pushCalled, isTrue);
      expect(container.read(syncControllerProvider).phase, SyncPhase.done);

      await controller.pullAll(forceOnline: true);
      expect(pullCalled, isTrue);
      expect(container.read(syncControllerProvider).phase, SyncPhase.done);
    });

    test('User mutation serialization and password update outbox payload', () {
      final now = DateTime.now();
      final mutation = SyncMutation.create(
        idempotencyKey: 'user-idemp-1',
        entityType: 'user',
        entityId: 'admin@example.com',
        action: MutationAction.update,
        payloadJson: jsonEncode({
          'name': 'Admin User',
          'email': 'admin@example.com',
          'role': 'admin',
          'password': 'newPassword2026',
        }),
        createdAt: now,
      );

      expect(mutation.entityType, 'user');
      expect(mutation.entityId, 'admin@example.com');
      expect(mutation.action, MutationAction.update);

      final payload = jsonDecode(mutation.payloadJson) as Map<String, dynamic>;
      expect(payload['email'], 'admin@example.com');
      expect(payload['password'], 'newPassword2026');
      expect(payload['role'], 'admin');
    });

    test('SyncItemResult tracks conflict and error messages properly', () {
      final conflictItem = SyncItemResult(
        'prod-uuid-1',
        SyncItemStatus.conflict,
        message: 'La version serveur est plus récente.',
      );
      expect(conflictItem.status, SyncItemStatus.conflict);
      expect(conflictItem.message, contains('plus récente'));

      final syncedItem = SyncItemResult('user-email@test.com', SyncItemStatus.synced);
      expect(syncedItem.status, SyncItemStatus.synced);
      expect(syncedItem.message, isNull);
    });
  });
}
