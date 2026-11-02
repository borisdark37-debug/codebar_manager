import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../database/collections/app_sequence.dart';
import '../database/collections/app_user.dart';
import '../database/collections/product.dart';
import '../database/collections/sync_mutation.dart';
import 'api_client.dart';
import 'local_auth_service.dart';
import 'notification_service.dart';
import 'secure_stokage_service.dart';

enum SyncItemStatus { synced, conflict, error }

class SyncItemResult {
  final String uuid;
  final SyncItemStatus status;
  final String? message;

  SyncItemResult(this.uuid, this.status, {this.message});
}

class SyncResult {
  final int pushed;
  final int synced;
  final int conflicts;
  final int errors;
  final List<SyncItemResult> items;
  final String? fatalError;
  final DateTime? serverTime;

  SyncResult({
    this.pushed = 0,
    this.synced = 0,
    this.conflicts = 0,
    this.errors = 0,
    this.items = const [],
    this.fatalError,
    this.serverTime,
  });

  bool get isFullSuccess =>
      fatalError == null && (pushed == 0 || synced == pushed) && errors == 0 && conflicts == 0;

  bool get hasErrors => conflicts > 0 || errors > 0 || fatalError != null;
}

class SyncService {
  final Isar _isar;
  final ApiClient _api;
  final NotificationService _notifications;
  final SupabaseClient? _injectedClient;
  static const _uuid = Uuid();

  // ⚠️ Exactement TROIS paramètres positionnels (respect de l'architecture).
  SyncService(
    this._isar,
    this._api,
    this._notifications, {
    SupabaseClient? supabaseClient,
  }) : _injectedClient = supabaseClient;

  SupabaseClient? get _supabaseClient {
    if (_injectedClient != null) return _injectedClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Mode hors-ligne : désactivé par défaut (Online-first).
  /// Le repli offline prend le relais uniquement lorsque le serveur ne répond pas ou plus.
  static bool offlineMode = false;

  static void setOfflineMode(bool value) {
    offlineMode = value;
  }

  Timer? _autoSyncTimer;
  bool _isAutoSyncRunning = false;

  /// Démarre le polling automatique périodique en tâche de fond (toutes les 8 secondes).
  /// Permet l'actualisation quasi-instantanée des données chez tous les utilisateurs connectés.
  void startAutoSync({Duration interval = const Duration(seconds: 8)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) async {
      if (_isAutoSyncRunning) return;
      _isAutoSyncRunning = true;
      try {
        await syncCycle();
      } catch (_) {
        // En cas de coupure réseau, le repli local reste actif sans perturber l'utilisateur
      } finally {
        _isAutoSyncRunning = false;
      }
    });
  }

  /// Arrête le polling automatique en arrière-plan.
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Exécute un cycle complet : pousse les modifications locales en attente vers le serveur
  /// puis récupère immédiatement les nouveautés du serveur.
  Future<SyncResult> syncCycle({bool forceOnline = true}) async {
    final pushRes = await pushPending(forceOnline: forceOnline);
    final pullRes = await pullAll(forceOnline: forceOnline);
    return pullRes.hasErrors ? pullRes : pushRes;
  }

  /// Retourne la date de la dernière synchronisation réussie (ou null).
  Future<DateTime?> getLastSyncAt() async {
    final seq = await _isar.appSequences.get(0);
    return seq?.lastSyncAt;
  }

  /// Enregistre l'instant courant ou l'horodatage serveur comme "dernière synchronisation réussie".
  Future<void> _recordLastSync([DateTime? serverTime]) async {
    final syncTimestamp = serverTime ?? DateTime.now();
    await _isar.writeTxn(() async {
      var seq = await _isar.appSequences.get(0);
      seq ??= AppSequence()
        ..id = 0
        ..lastProductNumber = 0
        ..updatedAt = DateTime.now();
      seq.lastSyncAt = syncTimestamp;
      seq.updatedAt = DateTime.now();
      await _isar.appSequences.put(seq);
    });
  }

  /// Vérifie la disponibilité du serveur central (Supabase Cloud ou API).
  Future<bool> checkServerHealth() async {
    final client = _supabaseClient;
    if (client != null) {
      try {
        await client.from('products').select('id').limit(1);
        return true;
      } catch (_) {}
    }
    try {
      final res = await _api.get<Map<String, dynamic>>('/health');
      return res.statusCode == 200 && res.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Réconciliation automatique du Super Administrateur créé en mode local
  /// vers le serveur Laravel pour acquérir un token Sanctum valide sans intervention manuelle.
  Future<bool> reconcileSuperAdmin() async {
    final storage = SecureStorageService();
    final hasToken = await storage.hasToken();
    if (hasToken) return true;

    final superAdmin = await _isar.appUsers.filter().roleEqualTo('super_admin').findFirst();
    final localAuth = LocalAuthService();
    final password = superAdmin?.password ?? await localAuth.getPlainPassword();
    final email = superAdmin?.email ?? await localAuth.getEmail();

    if (email == null || password == null) return false;

    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/migrate-super-admin',
        data: {
          'name': superAdmin?.name ?? 'Super Admin',
          'email': email,
          'password': password,
          'device_name': 'CodeBar Manager Desktop/Mobile',
        },
      );

      final token = res.data?['token'] as String?;
      if (token != null && token.isNotEmpty) {
        await storage.saveToken(token);
        await storage.saveAuthMode('server');
        await storage.saveUser(
          role: 'super_admin',
          name: superAdmin?.name ?? 'Super Admin',
          email: email,
        );
        if (superAdmin != null) {
          final updated = superAdmin.copyWith(
            syncStatus: SyncStatus.synced,
            clearPassword: true,
            updatedAt: DateTime.now(),
          );
          await _isar.writeTxn(() => _isar.appUsers.put(updated));
        }
        return true;
      }
    } catch (_) {
      // Ignorer l'erreur réseau si le serveur n'est pas encore joignable
    }
    return false;
  }

  /// Pousse le lot ordonné de mutations locales vers le serveur avec clés d'idempotence.
  Future<SyncResult> pushPending({bool forceOnline = false}) async {
    if (offlineMode && !forceOnline) {
      return SyncResult(
        fatalError:
            'Mode Hors-ligne : La synchronisation serveur est temporairement désactivée. Vos modifications sont conservées en base locale.',
      );
    }

    try {
      // Réconciliation transparente du compte Super Admin si nécessaire
      await reconcileSuperAdmin();

      // 1. Récupération des mutations en attente dans le journal Outbox
      final pendingMutations = await _isar.syncMutations
          .filter()
          .statusEqualTo(MutationStatus.pending)
          .sortByCreatedAt()
          .findAll();

      // 2. Récupération des produits en attente de synchronisation
      final pendingProducts = await _isar.products
          .filter()
          .syncStatusEqualTo(SyncStatus.pending)
          .findAll();

      // Si aucune modification locale n'est en attente
      if (pendingMutations.isEmpty && pendingProducts.isEmpty) {
        return SyncResult();
      }

      // Compléter les mutations pour les produits en attente qui n'auraient pas encore d'entrée Outbox
      final List<Map<String, dynamic>> mutationsPayload = [];
      final Set<String> coveredUuids = {};

      for (final m in pendingMutations) {
        try {
          final data = jsonDecode(m.payloadJson) as Map<String, dynamic>;
          mutationsPayload.add({
            'idempotency_key': m.idempotencyKey,
            'entity_type': m.entityType,
            'action': _mutationActionToString(m.action),
            'data': data,
            'client_timestamp': m.createdAt.toUtc().toIso8601String(),
          });
          coveredUuids.add(m.entityId);
        } catch (_) {}
      }

      for (final p in pendingProducts) {
        if (!coveredUuids.contains(p.uuid)) {
          final mutationKey = _uuid.v4();
          final action = p.deletedAt != null ? MutationAction.delete : MutationAction.create;
          final pJson = _productToJson(p);
          final mut = SyncMutation.create(
            idempotencyKey: mutationKey,
            entityType: 'product',
            entityId: p.uuid,
            action: action,
            payloadJson: jsonEncode(pJson),
            createdAt: p.updatedAt,
          );
          await _isar.writeTxn(() => _isar.syncMutations.put(mut));
          mutationsPayload.add({
            'idempotency_key': mutationKey,
            'entity_type': 'product',
            'action': _mutationActionToString(action),
            'data': pJson,
            'client_timestamp': p.updatedAt.toUtc().toIso8601String(),
          });
          coveredUuids.add(p.uuid);
        }
      }

      final client = _supabaseClient;
      if (client != null) {
        int synced = 0, conflicts = 0, errors = 0;
        final items = <SyncItemResult>[];
        final now = DateTime.now();

        for (final m in pendingMutations) {
          try {
            final data = jsonDecode(m.payloadJson) as Map<String, dynamic>;
            final uuid = m.entityId;

            if (m.entityType == 'product') {
              if (m.action == MutationAction.delete) {
                await client.from('products').update({
                  'deleted_at': now.toUtc().toIso8601String(),
                  'updated_at': now.toUtc().toIso8601String(),
                }).eq('id', uuid);
              } else if (m.action == MutationAction.permanentDelete) {
                await client.from('products').delete().eq('id', uuid);
              } else {
                final Map<String, dynamic> row = {
                  'id': uuid,
                  'name': data['name'],
                  'format': data['format'] ?? '',
                  'category': data['format'] ?? '',
                  'containment': data['containment'] ?? '',
                  'price': data['price'] ?? 0,
                  'quantity': data['quantity'] ?? 0,
                  'stock': data['quantity'] ?? 0,
                  'image_base64': data['image_base64'],
                  'created_at': data['created_at'] ?? now.toUtc().toIso8601String(),
                  'updated_at': now.toUtc().toIso8601String(),
                };
                if (data['internal_code'] != null && (data['internal_code'] as String).isNotEmpty) {
                  row['internal_code'] = data['internal_code'];
                }
                if (data['deleted_at'] != null) {
                  row['deleted_at'] = data['deleted_at'];
                }
                await client.from('products').upsert(row);
              }

              final product = await _isar.products.filter().uuidEqualTo(uuid).findFirst();
              if (product != null) {
                await _isar.writeTxn(() => _isar.products.put(product.copyWith(syncStatus: SyncStatus.synced)));
              }
            } else if (m.entityType == 'user') {
              final Map<String, dynamic> prof = {
                'email': data['email'],
                'full_name': data['name'],
                'role': data['role'] ?? 'operator',
                'is_active': data['is_active'] ?? true,
                'created_by': data['created_by'],
                'updated_at': now.toUtc().toIso8601String(),
              };
              await client.from('profiles').upsert(prof, onConflict: 'email');
              final user = await _isar.appUsers.filter().emailEqualTo(uuid).findFirst();
              if (user != null) {
                await _isar.writeTxn(() => _isar.appUsers.put(user.copyWith(syncStatus: SyncStatus.synced, clearPassword: true)));
              }
            }

            await _isar.writeTxn(() => _isar.syncMutations.put(m.copyWith(status: MutationStatus.synced, syncedAt: now)));
            synced++;
            items.add(SyncItemResult(uuid, SyncItemStatus.synced));
          } catch (e) {
            errors++;
            items.add(SyncItemResult(m.entityId, SyncItemStatus.error, message: e.toString()));
          }
        }

        for (final p in pendingProducts) {
          if (!coveredUuids.contains(p.uuid)) {
            try {
              final Map<String, dynamic> row = {
                'id': p.uuid,
                'internal_code': p.internalCode,
                'name': p.name,
                'format': p.format,
                'category': p.format,
                'containment': p.containment,
                'price': p.price,
                'quantity': p.quantity,
                'stock': p.quantity,
                'image_base64': p.imageBase64,
                'created_at': p.createdAt.toUtc().toIso8601String(),
                'updated_at': now.toUtc().toIso8601String(),
                'deleted_at': p.deletedAt?.toUtc().toIso8601String(),
              };
              await client.from('products').upsert(row);
              await _isar.writeTxn(() => _isar.products.put(p.copyWith(syncStatus: SyncStatus.synced)));
              synced++;
              items.add(SyncItemResult(p.uuid, SyncItemStatus.synced));
            } catch (e) {
              errors++;
              items.add(SyncItemResult(p.uuid, SyncItemStatus.error, message: e.toString()));
            }
          }
        }

        if (synced > 0) {
          await _recordLastSync(now);
        }
        await _notifications.stopSyncAlert();

        return SyncResult(
          pushed: mutationsPayload.length,
          synced: synced,
          conflicts: conflicts,
          errors: errors,
          items: items,
          serverTime: now,
        );
      }

      final payload = {
        'mutations': mutationsPayload,
        'changes': pendingProducts.map(_productToJson).toList(), // Rétrocompatibilité
      };

      Response<Map<String, dynamic>> response;
      try {
        response = await _api.post<Map<String, dynamic>>('/sync/push', data: payload);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          response = await _api.post<Map<String, dynamic>>('/sync', data: payload);
        } else {
          rethrow;
        }
      }

      final data = response.data;
      final resultsRaw = data?['results'] as List?;
      if (resultsRaw == null) {
        return SyncResult(
          pushed: mutationsPayload.length,
          fatalError: 'Réponse du serveur invalide.',
        );
      }

      final results = resultsRaw.cast<Map<String, dynamic>>();
      int synced = 0, conflicts = 0, errors = 0;
      final items = <SyncItemResult>[];
      final now = DateTime.now();

      await _isar.writeTxn(() async {
        for (final r in results) {
          final uuid = (r['uuid'] ?? r['idempotency_key']) as String;
          final status = r['status'] as String? ?? 'error';
          final idempotencyKey = r['idempotency_key'] as String?;
          SyncMutation? mutation;

          // Mise à jour de la mutation correspondante dans l'Outbox
          if (idempotencyKey != null) {
            mutation = await _isar.syncMutations
                .filter()
                .idempotencyKeyEqualTo(idempotencyKey)
                .findFirst();
            if (mutation != null) {
              if (status == 'synced') {
                await _isar.syncMutations.put(mutation.copyWith(
                  status: MutationStatus.synced,
                  syncedAt: now,
                ));
              } else {
                await _isar.syncMutations.put(mutation.copyWith(
                  status: MutationStatus.failed,
                  lastError: r['message'] as String? ?? r['error'] as String?,
                ));
              }
            }
          }

          final entityType = (r['entity_type'] as String?) ?? mutation?.entityType ?? 'product';

          if (entityType == 'user') {
            final user = await _isar.appUsers.filter().emailEqualTo(uuid).findFirst();
            if (user != null) {
              if (status == 'synced') {
                await _isar.appUsers.put(user.copyWith(
                  syncStatus: SyncStatus.synced,
                  password: null,
                  updatedAt: now,
                ));
              } else {
                await _isar.appUsers.put(user.copyWith(
                  syncStatus: SyncStatus.error,
                  updatedAt: now,
                ));
              }
            }
          } else {
            // Entité Produit locale
            final product = await _isar.products.filter().uuidEqualTo(uuid).findFirst();
            if (product != null) {
              if (status == 'synced') {
                await _isar.products.put(
                  product.copyWith(syncStatus: SyncStatus.synced),
                );
              } else {
                await _isar.products.put(
                  product.copyWith(syncStatus: SyncStatus.error),
                );
              }
            }
          }

          switch (status) {
            case 'synced':
              synced++;
              items.add(SyncItemResult(uuid, SyncItemStatus.synced));
              break;
            case 'conflict':
              conflicts++;
              items.add(
                SyncItemResult(
                  uuid,
                  SyncItemStatus.conflict,
                  message: r['message'] as String?,
                ),
              );
              break;
            default:
              errors++;
              items.add(
                SyncItemResult(
                  uuid,
                  SyncItemStatus.error,
                  message: r['error'] as String?,
                ),
              );
          }
        }
      });

      if (synced == pendingProducts.length + pendingMutations.length || errors == 0) {
        await _notifications.stopSyncAlert();
      }
      if (synced > 0) {
        DateTime? serverTime;
        if (data?['server_time'] != null) {
          serverTime = DateTime.tryParse(data!['server_time'] as String)?.toLocal();
        }
        await _recordLastSync(serverTime);
      }

      return SyncResult(
        pushed: mutationsPayload.length,
        synced: synced,
        conflicts: conflicts,
        errors: errors,
        items: items,
      );
    } on DioException catch (e) {
      return SyncResult(
        pushed: 0,
        fatalError: _dioErrorMessage(e),
      );
    } catch (e) {
      return SyncResult(pushed: 0, fatalError: e.toString());
    }
  }

  /// Récupération delta incrémentale depuis le serveur (modifications distantes depuis le dernier sync).
  Future<SyncResult> pullDelta({bool forceOnline = false}) async {
    return pullAll(forceOnline: forceOnline);
  }

  /// Restauration / synchronisation descendante depuis le serveur.
  Future<SyncResult> pullAll({bool forceOnline = false}) async {
    if (offlineMode && !forceOnline) {
      return SyncResult(
        fatalError:
            'Mode Hors-ligne : La restauration depuis le serveur est temporairement désactivée. Vos données locales sont actives.',
      );
    }

    try {
      await reconcileSuperAdmin();

      final client = _supabaseClient;
      if (client != null) {
        final List<dynamic> rows = await client
            .from('products')
            .select()
            .order('updated_at', ascending: true);

        int applied = 0;
        int maxPulledNumber = 0;
        final now = DateTime.now();

        await _isar.writeTxn(() async {
          for (final raw in rows) {
            final json = raw as Map<String, dynamic>;
            final uuid = (json['uuid'] ?? json['id']) as String;
            final internalCode = (json['internal_code'] as String?) ?? '';
            final name = (json['name'] as String?) ?? '';
            final format = (json['format'] ?? json['category'] ?? '') as String;
            final containment = (json['containment'] ?? '') as String;
            final price = (json['price'] as num?)?.toDouble() ?? 0.0;
            final quantity = (json['quantity'] ?? json['stock'] as num?)?.toInt() ?? 0;
            final imageBase64 = json['image_base64'] as String?;
            final createdAt = json['created_at'] != null ? DateTime.parse(json['created_at'] as String).toLocal() : now;
            final updatedAt = json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String).toLocal() : now;
            final deletedAt = json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String).toLocal() : null;

            if (internalCode.startsWith('CAP-')) {
              final numPart = int.tryParse(internalCode.substring(4));
              if (numPart != null && numPart > maxPulledNumber) {
                maxPulledNumber = numPart;
              }
            }

            final existing = await _isar.products.filter().uuidEqualTo(uuid).findFirst();
            if (existing == null || existing.syncStatus != SyncStatus.pending) {
              final p = Product.create(
                uuid: uuid,
                internalCode: internalCode,
                name: name,
                format: format,
                containment: containment,
                price: price,
                quantity: quantity,
                imageBase64: imageBase64,
                createdAt: createdAt,
                updatedAt: updatedAt,
                syncStatus: SyncStatus.synced,
                deletedAt: deletedAt,
              );
              await _isar.products.put(p);
              applied++;
            }
          }

          if (maxPulledNumber > 0) {
            var seq = await _isar.appSequences.get(0);
            seq ??= AppSequence()..id = 0..lastProductNumber = 0..updatedAt = DateTime.now();
            if (maxPulledNumber > seq.lastProductNumber) {
              seq.lastProductNumber = maxPulledNumber;
              seq.updatedAt = DateTime.now();
              await _isar.appSequences.put(seq);
            }
          }
        });

        try {
          final List<dynamic> profileRows = await client.from('profiles').select();
          await _isar.writeTxn(() async {
            for (final pRaw in profileRows) {
              final pJson = pRaw as Map<String, dynamic>;
              final email = pJson['email'] as String?;
              if (email == null) continue;
              final existingUser = await _isar.appUsers.filter().emailEqualTo(email).findFirst();
              final role = (pJson['role'] as String?) ?? 'operator';
              final name = (pJson['full_name'] as String?) ?? email;
              final isActive = (pJson['is_active'] as bool?) ?? true;
              final disabledAt = pJson['disabled_at'] != null ? DateTime.tryParse(pJson['disabled_at']) : null;
              final createdBy = pJson['created_by'] as String?;

              if (existingUser != null) {
                if (existingUser.syncStatus != SyncStatus.pending) {
                  await _isar.appUsers.put(existingUser.copyWith(
                    name: name,
                    role: role,
                    isActive: isActive,
                    disabledAt: disabledAt,
                    createdBy: createdBy ?? existingUser.createdBy,
                    syncStatus: SyncStatus.synced,
                    updatedAt: now,
                  ));
                }
              } else {
                await _isar.appUsers.put(AppUser.create(
                  uuid: (pJson['id'] as String?) ?? _uuid.v4(),
                  email: email,
                  name: name,
                  role: role,
                  syncStatus: SyncStatus.synced,
                  createdBy: createdBy,
                  isActive: isActive,
                  disabledAt: disabledAt,
                  createdAt: now,
                  updatedAt: now,
                ));
              }
            }
          });
        } catch (_) {}

        await _recordLastSync(now);
        return SyncResult(pushed: 0, synced: applied, serverTime: now);
      }

      final lastSync = await getLastSyncAt();
      final Map<String, dynamic> queryParams = {'include_deleted': 1};
      if (lastSync != null) {
        queryParams['since'] = lastSync.toUtc().toIso8601String();
      }

      Response<Map<String, dynamic>> response;
      try {
        response = await _api.get<Map<String, dynamic>>(
          '/sync/pull',
          queryParameters: queryParams,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          response = await _api.get<Map<String, dynamic>>(
            '/products',
            queryParameters: {'include_deleted': 1},
          );
        } else {
          rethrow;
        }
      }

      final data = response.data;
      final productsRaw = data?['products'] as List?;
      final usersRaw = data?['users'] as List?;

      if (productsRaw == null && data?['status'] != 'success') {
        return SyncResult(fatalError: 'Réponse du serveur invalide.');
      }

      int applied = 0;
      final productsJson = (productsRaw ?? []).cast<Map<String, dynamic>>();

      final tombstonesRaw = data?['tombstones'] as Map<String, dynamic>?;

      await _isar.writeTxn(() async {
        // 1. Traitement des Tombstones (produits supprimés définitivement & logiquement, utilisateurs supprimés)
        if (tombstonesRaw != null) {
          final forceDeletedUuids = (tombstonesRaw['force_deleted_products'] as List?)?.cast<String>() ?? [];
          for (final uuid in forceDeletedUuids) {
            final p = await _isar.products.filter().uuidEqualTo(uuid).findFirst();
            if (p != null && p.syncStatus != SyncStatus.pending) {
              await _isar.products.delete(p.isarId);
            }
          }

          final trashedUuids = (tombstonesRaw['products'] as List?)?.cast<String>() ?? [];
          for (final uuid in trashedUuids) {
            final p = await _isar.products.filter().uuidEqualTo(uuid).findFirst();
            if (p != null && p.syncStatus != SyncStatus.pending && p.deletedAt == null) {
              await _isar.products.put(p.copyWith(
                deletedAt: DateTime.now(),
                syncStatus: SyncStatus.synced,
              ));
            }
          }

          final deletedUsers = (tombstonesRaw['users'] as List?)?.cast<String>() ?? [];
          for (final email in deletedUsers) {
            final u = await _isar.appUsers.filter().emailEqualTo(email).findFirst();
            if (u != null && u.role != 'super_admin' && u.syncStatus != SyncStatus.pending) {
              await _isar.appUsers.delete(u.isarId);
            }
          }
        }

        // 2. Traitement des Produits distants
        int maxPulledNumber = 0;
        for (final json in productsJson) {
          final product = _jsonToProduct(json);

          // Extraction du numéro pour aligner la séquence
          if (product.internalCode.startsWith('CAP-')) {
            final numPart = int.tryParse(product.internalCode.substring(4));
            if (numPart != null && numPart > maxPulledNumber) {
              maxPulledNumber = numPart;
            }
          }

          final existing = await _isar.products
              .filter()
              .uuidEqualTo(product.uuid)
              .findFirst();

          // Conflit : si un produit local en attente possède déjà ce même code sous un autre UUID
          final collision = await _isar.products
              .filter()
              .internalCodeEqualTo(product.internalCode)
              .findFirst();
          if (collision != null && collision.uuid != product.uuid && collision.syncStatus == SyncStatus.pending) {
            var seq = await _isar.appSequences.get(0);
            seq ??= AppSequence()..id = 0..lastProductNumber = 0..updatedAt = DateTime.now();
            seq.lastProductNumber += 1;
            seq.updatedAt = DateTime.now();
            await _isar.appSequences.put(seq);
            final newCode = 'CAP-${seq.lastProductNumber.toString().padLeft(4, '0')}';
            final remapped = collision.copyWith(internalCode: newCode);
            await _isar.products.put(remapped);

            final mut = await _isar.syncMutations.filter().entityIdEqualTo(collision.uuid).findFirst();
            if (mut != null) {
              try {
                final mData = jsonDecode(mut.payloadJson) as Map<String, dynamic>;
                mData['internal_code'] = newCode;
                await _isar.syncMutations.put(mut.copyWith(payloadJson: jsonEncode(mData)));
              } catch (_) {}
            }
          }

          final hasLocalPendingEdit = existing != null && existing.syncStatus == SyncStatus.pending;
          final serverTime = product.deletedAt != null && product.deletedAt!.isAfter(product.updatedAt)
              ? product.deletedAt!
              : product.updatedAt;
          final localTime = existing == null
              ? null
              : (existing.deletedAt != null && existing.deletedAt!.isAfter(existing.updatedAt)
                  ? existing.deletedAt!
                  : existing.updatedAt);
          final serverIsNewer = localTime == null || serverTime.isAfter(localTime) || serverTime.isAtSameMomentAs(localTime);

          if (!hasLocalPendingEdit && serverIsNewer) {
            await _isar.products.put(product);
            applied++;
          }
        }

        // 3. Mise à jour préventive de la séquence locale pour éviter toute future collision
        if (maxPulledNumber > 0) {
          var seq = await _isar.appSequences.get(0);
          seq ??= AppSequence()..id = 0..lastProductNumber = 0..updatedAt = DateTime.now();
          if (maxPulledNumber > seq.lastProductNumber) {
            seq.lastProductNumber = maxPulledNumber;
            seq.updatedAt = DateTime.now();
            await _isar.appSequences.put(seq);
          }
        }

        // 4. Fusion des utilisateurs
        if (usersRaw != null) {
          for (final uJson in usersRaw.cast<Map<String, dynamic>>()) {
            final email = uJson['email'] as String?;
            if (email == null) continue;
            final existing = await _isar.appUsers.filter().emailEqualTo(email).findFirst();

            if (existing != null) {
              if (existing.syncStatus != SyncStatus.pending) {
                final updated = existing.copyWith(
                  name: uJson['name'] as String?,
                  role: uJson['role'] as String?,
                  isActive: uJson['is_active'] as bool?,
                  disabledAt: uJson['disabled_at'] != null ? DateTime.tryParse(uJson['disabled_at']) : null,
                  createdBy: uJson['created_by'] as String?,
                  syncStatus: SyncStatus.synced,
                );
                await _isar.appUsers.put(updated);
              }
            } else {
              final newUser = AppUser.create(
                uuid: _uuid.v4(),
                email: email,
                name: uJson['name'] as String? ?? 'Utilisateur',
                role: uJson['role'] as String? ?? 'manager',
                syncStatus: SyncStatus.synced,
                createdBy: uJson['created_by'] as String?,
                isActive: uJson['is_active'] as bool? ?? true,
                disabledAt: uJson['disabled_at'] != null ? DateTime.tryParse(uJson['disabled_at']) : null,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              await _isar.appUsers.put(newUser);
            }
          }
        }
      });

      DateTime? serverTime;
      if (data?['server_time'] != null) {
        serverTime = DateTime.tryParse(data!['server_time'] as String)?.toLocal();
      }
      await _recordLastSync(serverTime);

      return SyncResult(pushed: 0, synced: applied, serverTime: serverTime);
    } on DioException catch (e) {
      return SyncResult(fatalError: _dioErrorMessage(e));
    } catch (e) {
      return SyncResult(fatalError: e.toString());
    }
  }

  /// Cycle complet de synchronisation bidirectionnelle :
  /// 1. Push des mutations locales ordonnées (Outbox)
  /// 2. Pull des deltas distants depuis le dernier sync
  /// 3. Enregistrement sécurisé du nouveau timestamp
  Future<SyncResult> synchronize({bool forceOnline = false}) async {
    final pushResult = await pushPending(forceOnline: forceOnline);
    if (pushResult.fatalError != null && !pushResult.fatalError!.contains('Mode Hors-ligne')) {
      return pushResult;
    }

    final pullResult = await pullDelta(forceOnline: forceOnline);

    return SyncResult(
      pushed: pushResult.pushed,
      synced: pushResult.synced + pullResult.synced,
      conflicts: pushResult.conflicts + pullResult.conflicts,
      errors: pushResult.errors + pullResult.errors,
      items: [...pushResult.items, ...pullResult.items],
      fatalError: pullResult.fatalError ?? pushResult.fatalError,
      serverTime: pullResult.serverTime ?? pushResult.serverTime,
    );
  }

  Map<String, dynamic> _productToJson(Product p) {
    return {
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
  }

  Product _jsonToProduct(Map<String, dynamic> json) {
    final deletedAtRaw = json['deleted_at'] as String?;
    return Product.create(
      uuid: json['uuid'] as String,
      internalCode: json['internal_code'] as String,
      name: json['name'] as String,
      format: (json['format'] as String?) ?? '',
      containment: (json['containment'] as String?) ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      imageBase64: json['image_base64'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      syncStatus: SyncStatus.synced,
      deletedAt: deletedAtRaw != null ? DateTime.parse(deletedAtRaw).toLocal() : null,
    );
  }

  String _mutationActionToString(MutationAction action) {
    switch (action) {
      case MutationAction.create:
        return 'create';
      case MutationAction.update:
        return 'update';
      case MutationAction.delete:
        return 'delete';
      case MutationAction.permanentDelete:
        return 'permanent_delete';
    }
  }

  String _dioErrorMessage(DioException e) {
    if (e.response?.statusCode == 422) {
      final data = e.response?.data;
      if (data is Map && data['errors'] is Map) {
        final errors = data['errors'] as Map;
        final details = errors.entries
            .map((entry) {
              final value = entry.value;
              final message = value is List && value.isNotEmpty
                  ? value.first.toString()
                  : value.toString();
              return '${entry.key}: $message';
            })
            .join(' ; ');
        if (details.isNotEmpty) {
          return 'Validation serveur : $details';
        }
      }
      return 'Données refusées par le serveur (validation).';
    }
    final code = e.response?.statusCode;
    if (code == 401) return 'Session expirée ou non autorisée. Reconnectez-vous.';
    if (code == 403) return 'Accès refusé par le serveur central.';
    if (code == 422) return 'Données refusées par le serveur (validation).';
    if (code == 500) return 'Erreur interne du serveur.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Délai dépassé. Vérifiez votre connexion.';
    }
    if (e.type == DioExceptionType.connectionError) {
      final uri = Uri.tryParse(ApiConfig.baseUrl);
      final host = uri != null ? '${uri.host}:${uri.port}' : ApiConfig.baseUrl;
      return 'Serveur distant injoignable ($host). Mode hors-ligne maintenu.';
    }
    return 'Erreur réseau : ${e.message}';
  }
}
