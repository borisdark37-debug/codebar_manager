import 'package:isar/isar.dart';

import '../../utils/fast_hash.dart';

part 'sync_mutation.g.dart';

enum MutationAction {
  create,
  update,
  delete,
  permanentDelete,
}

enum MutationStatus {
  pending,
  synced,
  failed,
}

/// Collection Isar servant de journal transactionnel local (Transactional Outbox)
/// pour chaque opération effectuée hors-ligne ou en ligne.
@collection
class SyncMutation {
  Id get isarId => fastHash(idempotencyKey);

  @Index(unique: true, replace: true)
  late String idempotencyKey; // UUIDv4

  @Index()
  late String entityType; // 'product' | 'user'

  @Index()
  late String entityId; // UUID ou email de l'entité

  @enumerated
  late MutationAction action;

  late String payloadJson; // Données JSON sérialisées

  @Index()
  late DateTime createdAt;

  @enumerated
  late MutationStatus status;

  int retryCount = 0;
  String? lastError;
  DateTime? syncedAt;

  SyncMutation();

  SyncMutation.create({
    required this.idempotencyKey,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payloadJson,
    required this.createdAt,
    this.status = MutationStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.syncedAt,
  });

  SyncMutation copyWith({
    String? payloadJson,
    MutationStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? syncedAt,
  }) {
    return SyncMutation.create(
      idempotencyKey: idempotencyKey,
      entityType: entityType,
      entityId: entityId,
      action: action,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}
