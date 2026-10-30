import 'dart:convert';
import 'package:codebar_manager_app/core/database/collections/sync_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncMutation Model Unit Tests', () {
    test('SyncMutation initializes with valid default values', () {
      final now = DateTime.now();
      final mutation = SyncMutation.create(
        idempotencyKey: 'idemp-uuid-5555',
        entityType: 'product',
        entityId: 'prod-uuid-1',
        action: MutationAction.create,
        payloadJson: jsonEncode({'name': 'Savon'}),
        createdAt: now,
      );

      expect(mutation.idempotencyKey, 'idemp-uuid-5555');
      expect(mutation.entityType, 'product');
      expect(mutation.entityId, 'prod-uuid-1');
      expect(mutation.action, MutationAction.create);
      expect(mutation.status, MutationStatus.pending);
      expect(mutation.retryCount, 0);
      expect(mutation.lastError, isNull);
      expect(mutation.syncedAt, isNull);
    });

    test('SyncMutation copyWith increments retryCount and updates error status', () {
      final now = DateTime.now();
      final mutation = SyncMutation.create(
        idempotencyKey: 'idemp-retry-1',
        entityType: 'product',
        entityId: 'prod-uuid-1',
        action: MutationAction.update,
        payloadJson: '{}',
        createdAt: now,
      );

      final retry1 = mutation.copyWith(
        retryCount: 1,
        lastError: 'HTTP 503 Service Unavailable',
      );

      expect(retry1.retryCount, 1);
      expect(retry1.lastError, 'HTTP 503 Service Unavailable');
      expect(retry1.status, MutationStatus.pending);

      final synced = retry1.copyWith(
        status: MutationStatus.synced,
        syncedAt: now.add(const Duration(minutes: 1)),
      );

      expect(synced.status, MutationStatus.synced);
      expect(synced.syncedAt, isNotNull);
    });
  });
}
