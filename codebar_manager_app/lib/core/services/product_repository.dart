import 'dart:convert';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../database/collections/product.dart';
import '../database/collections/sync_mutation.dart';
import 'code_generator_service.dart';
import 'image_compression_service.dart';
import 'sync_service.dart';

class ProductRepository {
  final Isar _isar;
  final CodeGeneratorService _codeGen;
  final SyncService? _syncService;
  static const _uuid = Uuid();

  ProductRepository(this._isar, {SyncService? syncService})
      : _codeGen = CodeGeneratorService(_isar),
        _syncService = syncService;

  Future<void> _triggerOnlineSync() async {
    final sync = _syncService;
    if (sync != null && !SyncService.offlineMode) {
      try {
        await sync.pushPending(forceOnline: true).timeout(const Duration(seconds: 30));
      } catch (_) {
        // Mode Online-first résilient : repli local automatique avec enregistrement Outbox
      }
    }
  }

  Map<String, dynamic> _productToMap(Product p) => {
        'uuid': p.uuid,
        'internal_code': p.internalCode,
        'name': p.name,
        'format': p.format,
        'containment': p.containment,
        'price': p.price,
        'quantity': p.quantity,
        'image_base64': p.imageBase64,
        'created_at': p.createdAt.toUtc().toIso8601String(),
        'updated_at': p.updatedAt.toUtc().toIso8601String(),
        'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
      };

  Future<Product> create({
    required String name,
    required String format,
    required String containment,
    double price = 0,
    int quantity = 0,
    String? imageBase64,
  }) async {
    final compressedImage = imageBase64 != null
        ? await ImageCompressionService.compressBase64(imageBase64)
        : null;
    final uuid = _codeGen.generateUuid();
    final internalCode = await _codeGen.reserveNextInternalCode();
    final now = DateTime.now();

    final product = Product.create(
      uuid: uuid,
      internalCode: internalCode,
      name: name,
      format: format,
      containment: containment,
      price: price,
      quantity: quantity,
      imageBase64: compressedImage,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'product',
      entityId: product.uuid,
      action: MutationAction.create,
      payloadJson: jsonEncode(_productToMap(product)),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.products.put(product);
      await _isar.syncMutations.put(mutation);
    });
    await _triggerOnlineSync();
    return product;
  }

  Future<Product> update(
    Product product, {
    required String name,
    required String format,
    required String containment,
    double price = 0,
    int quantity = 0,
    String? imageBase64,
  }) async {
    final compressedImage = imageBase64 != null
        ? await ImageCompressionService.compressBase64(imageBase64)
        : null;
    final now = DateTime.now();
    final updated = product.copyWith(
      name: name,
      format: format,
      containment: containment,
      price: price,
      quantity: quantity,
      imageBase64: compressedImage,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'product',
      entityId: updated.uuid,
      action: MutationAction.update,
      payloadJson: jsonEncode(_productToMap(updated)),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.products.put(updated);
      await _isar.syncMutations.put(mutation);
    });
    await _triggerOnlineSync();
    return updated;
  }

  /// Soft-delete : marque le produit comme supprimé et journalise la mutation outbox.
  Future<void> softDelete(Product product) async {
    final now = DateTime.now();
    final updated = product.copyWith(
      deletedAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'product',
      entityId: updated.uuid,
      action: MutationAction.delete,
      payloadJson: jsonEncode(_productToMap(updated)),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.products.put(updated);
      await _isar.syncMutations.put(mutation);
    });
    await _triggerOnlineSync();
  }

  /// Restaure un produit supprimé (soft-delete → actif).
  Future<void> restore(Product product) async {
    final now = DateTime.now();
    final restored = product.copyWith(
      clearDeletedAt: true,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'product',
      entityId: restored.uuid,
      action: MutationAction.update,
      payloadJson: jsonEncode(_productToMap(restored)),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.products.put(restored);
      await _isar.syncMutations.put(mutation);
    });
    await _triggerOnlineSync();
  }

  /// Restaure tous les produits supprimés.
  Future<void> restoreAll() async {
    final deleted = await listDeleted();
    if (deleted.isEmpty) return;
    final now = DateTime.now();
    await _isar.writeTxn(() async {
      for (final p in deleted) {
        final restored = p.copyWith(
          clearDeletedAt: true,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        );
        final mutation = SyncMutation.create(
          idempotencyKey: _uuid.v4(),
          entityType: 'product',
          entityId: restored.uuid,
          action: MutationAction.update,
          payloadJson: jsonEncode(_productToMap(restored)),
          createdAt: now,
        );
        await _isar.products.put(restored);
        await _isar.syncMutations.put(mutation);
      }
    });
    await _triggerOnlineSync();
  }

  /// Suppression définitive d'un produit depuis la corbeille.
  /// Journalise une mutation 'permanentDelete' pour répercussion côté serveur.
  Future<void> deletePermanently(Product product) async {
    final now = DateTime.now();
    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'product',
      entityId: product.uuid,
      action: MutationAction.permanentDelete,
      payloadJson: jsonEncode({'uuid': product.uuid}),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.syncMutations.put(mutation);
      await _isar.products.delete(product.isarId);
    });
    await _triggerOnlineSync();
  }

  /// Vide complètement la corbeille (suppression définitive de tous les éléments).
  Future<void> clearTrash() async {
    final deleted = await listDeleted();
    if (deleted.isEmpty) return;
    final now = DateTime.now();
    await _isar.writeTxn(() async {
      for (final p in deleted) {
        final mutation = SyncMutation.create(
          idempotencyKey: _uuid.v4(),
          entityType: 'product',
          entityId: p.uuid,
          action: MutationAction.permanentDelete,
          payloadJson: jsonEncode({'uuid': p.uuid}),
          createdAt: now,
        );
        await _isar.syncMutations.put(mutation);
        await _isar.products.delete(p.isarId);
      }
    });
    await _triggerOnlineSync();
  }

  /// Liste les produits en corbeille (soft-deleted).
  Future<List<Product>> listDeleted() async {
    return _isar.products
        .filter()
        .deletedAtIsNotNull()
        .sortByDeletedAtDesc()
        .findAll();
  }

  /// Stream réactif de la corbeille.
  Stream<List<Product>> watchDeleted() {
    return _isar.products
        .filter()
        .deletedAtIsNotNull()
        .sortByDeletedAtDesc()
        .watch(fireImmediately: true);
  }

  /// Recherche un produit par son code interne (ex: CAP-0001).
  Future<Product?> findByInternalCode(String code) async {
    return _isar.products
        .filter()
        .internalCodeEqualTo(code)
        .findFirst();
  }

  Future<List<Product>> listAll() async {
    return _isar.products
        .filter()
        .deletedAtIsNull()
        .sortByInternalCode()
        .findAll();
  }

  /// Stream réactif : émet à chaque modification de la collection.
  Stream<List<Product>> watchAll() {
    return _isar.products.filter().deletedAtIsNull().sortByInternalCode().watch(
      fireImmediately: true,
    );
  }

  /// Stream du nombre d'enregistrements en attente de synchronisation.
  Stream<int> watchPendingCount() {
    return _isar.products
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .watch(fireImmediately: true)
        .map((list) => list.length);
  }

  Future<int> countPending() async {
    return _isar.products
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .count();
  }
}
