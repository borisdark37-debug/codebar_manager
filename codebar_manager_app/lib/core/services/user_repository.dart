import 'dart:convert';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../database/collections/app_user.dart';
import '../database/collections/product.dart';
import '../database/collections/sync_mutation.dart';
import 'api_client.dart';
import 'local_auth_service.dart';
import 'secure_stokage_service.dart';

class UserRepository {
  final Isar _isar;
  final ApiClient _api;
  final SecureStorageService _storage;
  static const _uuid = Uuid();

  static bool offlineMode = false;

  UserRepository(this._isar, this._api, this._storage);

  /// S'assure que les 2 comptes Super Administrateur par défaut sont bien présents dans la collection AppUser locale.
  Future<AppUser?> ensureSuperAdminExists() async {
    final now = DateTime.now();
    final localAuth = LocalAuthService();
    final plainPass = await localAuth.getPlainPassword();

    // 1. Super Admin 1 par défaut : Capucine Bolo
    var sa1 = await _isar.appUsers
        .filter()
        .emailEqualTo('capucine@gmail.com', caseSensitive: false)
        .findFirst();
    if (sa1 == null) {
      sa1 = AppUser.create(
        uuid: 'capucine-bolo-default',
        email: 'capucine@gmail.com',
        name: 'Capucine Bolo',
        role: 'super_admin',
        password: 'Password123!',
        syncStatus: SyncStatus.synced,
        createdBy: null,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      await _isar.writeTxn(() => _isar.appUsers.put(sa1!));
    }

    // 2. Super Admin 2 par défaut : Boris Dark
    var sa2 = await _isar.appUsers
        .filter()
        .emailEqualTo('borisdark37@gmail.com', caseSensitive: false)
        .findFirst();
    if (sa2 == null) {
      sa2 = AppUser.create(
        uuid: 'boris-dark-default',
        email: 'borisdark37@gmail.com',
        name: 'Boris Dark',
        role: 'super_admin',
        password: 'Password123!',
        syncStatus: SyncStatus.synced,
        createdBy: null,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      await _isar.writeTxn(() => _isar.appUsers.put(sa2!));
    }

    var superAdmin = await _isar.appUsers
        .filter()
        .roleEqualTo('super_admin')
        .findFirst();

    if (superAdmin == null) {
      final localEmail = await localAuth.getEmail();
      final email = localEmail ?? 'capucine@gmail.com';

      superAdmin = AppUser.create(
        uuid: 'super-admin-local',
        email: email,
        name: 'Capucine Bolo',
        role: 'super_admin',
        password: plainPass ?? 'Password123!',
        syncStatus: SyncStatus.synced,
        createdBy: null,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      await _isar.writeTxn(() async {
        await _isar.appUsers.put(superAdmin!);
      });
    } else if (plainPass != null && superAdmin.password != plainPass) {
      superAdmin = superAdmin.copyWith(password: plainPass);
      await _isar.writeTxn(() async {
        await _isar.appUsers.put(superAdmin!);
      });
    }
    return superAdmin;
  }

  /// Migre le compte Super Administrateur créé en local vers le serveur Laravel.
  Future<bool> migrateSuperAdmin({AppUser? user, String? password}) async {
    var superAdmin = user ?? await _isar.appUsers.filter().roleEqualTo('super_admin').findFirst();
    final localAuth = LocalAuthService();
    final email = superAdmin?.email ?? await localAuth.getEmail() ?? await _storage.getUserEmail();
    if (email == null) {
      throw StateError('Aucun compte Super Administrateur trouvé sur cet appareil.');
    }

    final plainPass = password ?? superAdmin?.password ?? await localAuth.getPlainPassword();
    if (plainPass == null) {
      throw StateError('Mot de passe requis pour migrer le compte Super Administrateur vers le serveur.');
    }

    final name = superAdmin?.name ?? await _storage.getUserName() ?? 'Super Admin';

    final res = await _api.post(
      '/migrate-super-admin',
      data: {
        'name': name,
        'email': email,
        'password': plainPass,
        'device_name': 'CodeBar Manager Mobile/Desktop',
      },
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = res.data as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token != null) {
        await _storage.saveToken(token);
        await _storage.saveAuthMode('server');
        await _storage.saveUser(role: 'super_admin', name: name, email: email);
        await localAuth.savePlainPassword(plainPass);
      }

      if (superAdmin == null) {
        superAdmin = AppUser.create(
          uuid: 'super-admin-local',
          email: email,
          name: name,
          role: 'super_admin',
          syncStatus: SyncStatus.synced,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      } else {
        superAdmin = superAdmin.copyWith(
          syncStatus: SyncStatus.synced,
          password: null,
          updatedAt: DateTime.now(),
        );
      }

      await _isar.writeTxn(() async {
        await _isar.appUsers.put(superAdmin!);
      });

      return true;
    }
    return false;
  }

  /// Crée un utilisateur dans la base locale et journalise la mutation dans l'Outbox.
  Future<AppUser> create({
    required String name,
    required String email,
    required String password,
    required String role,
    String? createdBy,
  }) async {
    final now = DateTime.now();
    final userUuid = _uuid.v4();

    // Déterminer le créateur si non fourni
    String? effectiveCreator = createdBy;
    if (effectiveCreator == null && role != 'super_admin') {
      effectiveCreator = await _storage.getUserName() ?? 'Super Admin';
    }

    final appUser = AppUser.create(
      uuid: userUuid,
      email: email,
      name: name,
      role: role,
      password: password,
      syncStatus: SyncStatus.pending,
      createdBy: role == 'super_admin' ? null : effectiveCreator,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'user',
      entityId: email,
      action: MutationAction.create,
      payloadJson: jsonEncode({
        'name': name,
        'email': email,
        'role': role,
        'password': password,
        'created_by': appUser.createdBy,
        'is_active': true,
      }),
      createdAt: now,
    );

    // Sauvegarde locale immédiate
    await _isar.writeTxn(() async {
      await _isar.appUsers.put(appUser);
      await _isar.syncMutations.put(mutation);
    });

    return appUser;
  }

  /// Synchronise un utilisateur spécifique vers le serveur
  Future<bool> syncUser(AppUser user, {String? password}) async {
    if (user.role == 'super_admin') {
      final hasToken = await _storage.hasToken();
      if (!hasToken) {
        return migrateSuperAdmin(user: user, password: password);
      }
    }

    try {
      final res = await _api.post(
        '/users/sync',
        data: {
          'users': [
            {
              'name': user.name,
              'email': user.email,
              'role': user.role,
              'password': password ?? user.password ?? '0000',
              'created_by': user.createdBy,
              'is_active': user.isActive,
            }
          ]
        },
      );

      if (res.statusCode == 200) {
        final now = DateTime.now();
        final updated = user.copyWith(
          syncStatus: SyncStatus.synced,
          password: null,
          updatedAt: now,
        );
        await _isar.writeTxn(() async {
          await _isar.appUsers.put(updated);
          final userMutations = await _isar.syncMutations
              .filter()
              .entityTypeEqualTo('user')
              .and()
              .entityIdEqualTo(user.email)
              .and()
              .statusEqualTo(MutationStatus.pending)
              .findAll();
          for (final m in userMutations) {
            await _isar.syncMutations.put(m.copyWith(
              status: MutationStatus.synced,
              syncedAt: now,
            ));
          }
        });
        return true;
      }
      return false;
    } catch (e) {
      if (user.role == 'super_admin') {
        try {
          return await migrateSuperAdmin(user: user, password: password);
        } catch (_) {}
      }
      final updated = user.copyWith(
        syncStatus: SyncStatus.error,
        updatedAt: DateTime.now(),
      );
      await _isar.writeTxn(() async {
        await _isar.appUsers.put(updated);
      });
      rethrow;
    }
  }

  /// Synchronise l'ensemble des utilisateurs en attente ou en erreur vers le serveur
  Future<int> syncAllPending({String? superAdminPassword}) async {
    await ensureSuperAdminExists();

    int syncedCount = 0;

    // 1. Migrer le Super Admin d'abord s'il est en attente
    final pendingSuperAdmin = await _isar.appUsers
        .filter()
        .roleEqualTo('super_admin')
        .and()
        .group((q) => q.syncStatusEqualTo(SyncStatus.pending).or().syncStatusEqualTo(SyncStatus.error))
        .findFirst();

    if (pendingSuperAdmin != null) {
      try {
        final ok = await migrateSuperAdmin(user: pendingSuperAdmin, password: superAdminPassword);
        if (ok) syncedCount++;
      } catch (e) {
        if (!await _storage.hasToken()) {
          rethrow;
        }
      }
    }

    final pendingUsers = await _isar.appUsers
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .or()
        .syncStatusEqualTo(SyncStatus.error)
        .findAll();

    final remainingUsers = pendingUsers.where((u) => u.role != 'super_admin').toList();

    if (remainingUsers.isEmpty) return syncedCount;

    final payload = remainingUsers.map((u) {
      return {
        'name': u.name,
        'email': u.email,
        'role': u.role,
        'password': u.password ?? '0000',
        'created_by': u.createdBy,
        'is_active': u.isActive,
      };
    }).toList();

    try {
      final res = await _api.post(
        '/users/sync',
        data: {'users': payload},
      );

      if (res.statusCode == 200) {
        final now = DateTime.now();
        await _isar.writeTxn(() async {
          for (final u in remainingUsers) {
            final updated = u.copyWith(
              syncStatus: SyncStatus.synced,
              clearPassword: true,
              updatedAt: now,
            );
            await _isar.appUsers.put(updated);

            final muts = await _isar.syncMutations
                .filter()
                .entityTypeEqualTo('user')
                .and()
                .entityIdEqualTo(u.email)
                .and()
                .statusEqualTo(MutationStatus.pending)
                .findAll();
            for (final m in muts) {
              await _isar.syncMutations.put(m.copyWith(
                status: MutationStatus.synced,
                syncedAt: now,
              ));
            }
          }
        });
        return syncedCount + remainingUsers.length;
      }
      return syncedCount;
    } catch (e) {
      await _isar.writeTxn(() async {
        for (final u in remainingUsers) {
          final updated = u.copyWith(syncStatus: SyncStatus.error);
          await _isar.appUsers.put(updated);
        }
      });
      rethrow;
    }
  }

  /// Met à jour le mot de passe d'un utilisateur en mode Online-First avec repli Offline résilient.
  Future<AppUser> resetPasswordOnline(AppUser user, String newPassword) async {
    final now = DateTime.now();
    var updated = user.copyWith(
      password: newPassword,
      syncStatus: SyncStatus.pending,
      updatedAt: now,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'user',
      entityId: user.email,
      action: MutationAction.update,
      payloadJson: jsonEncode({
        'name': user.name,
        'email': user.email,
        'role': user.role,
        'password': newPassword,
      }),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.appUsers.put(updated);
      await _isar.syncMutations.put(mutation);
    });

    // Tenter la réinitialisation directe en ligne vers le serveur central
    if (!offlineMode) {
      try {
        final res = await _api.post(
          '/users/reset-password',
          data: {
            'email': user.email,
            'password': newPassword,
          },
        );
        if (res.statusCode == 200) {
          updated = updated.copyWith(
            syncStatus: SyncStatus.synced,
            clearPassword: true,
            updatedAt: DateTime.now(),
          );
          await _isar.writeTxn(() async {
            await _isar.appUsers.put(updated);
            await _isar.syncMutations.put(mutation.copyWith(
              status: MutationStatus.synced,
              syncedAt: DateTime.now(),
            ));
          });
        }
      } catch (_) {
        // En cas d'indisponibilité du serveur ou timeout (30s), la mutation reste 'pending' en local
      }
    }

    return updated;
  }

  /// Met à jour le mot de passe d'un utilisateur et journalise la mutation Outbox
  Future<AppUser> updatePassword(AppUser user, String newPassword) =>
      resetPasswordOnline(user, newPassword);

  /// Active ou désactive un utilisateur et enregistre la mutation Outbox
  Future<AppUser> toggleActive(AppUser user) async {
    final newActive = !user.isActive;
    final now = DateTime.now();

    final updated = user.copyWith(
      isActive: newActive,
      disabledAt: newActive ? null : now,
      clearDisabledAt: newActive,
      syncStatus: SyncStatus.pending,
      updatedAt: now,
    );

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'user',
      entityId: user.email,
      action: MutationAction.update,
      payloadJson: jsonEncode({
        'name': user.name,
        'email': user.email,
        'role': user.role,
        'is_active': newActive,
      }),
      createdAt: now,
    );

    await _isar.writeTxn(() async {
      await _isar.appUsers.put(updated);
      await _isar.syncMutations.put(mutation);
    });

    return updated;
  }

  /// Supprime définitivement un utilisateur du système et enregistre la mutation Outbox
  Future<void> deletePermanently(AppUser user, {bool force = false}) async {
    if (user.role == 'super_admin') {
      throw StateError('Le compte Super Administrateur ne peut pas être supprimé.');
    }

    if (!force && !user.isPurgeEligible) {
      throw StateError(
        'L\'utilisateur doit être désactivé depuis au moins 30 jours (encore ${user.daysUntilPurge} jour(s)).',
      );
    }

    final mutation = SyncMutation.create(
      idempotencyKey: _uuid.v4(),
      entityType: 'user',
      entityId: user.email,
      action: MutationAction.delete,
      payloadJson: jsonEncode({'email': user.email}),
      createdAt: DateTime.now(),
    );

    // Suppression locale et journalisation Outbox
    await _isar.writeTxn(() async {
      await _isar.syncMutations.put(mutation);
      await _isar.appUsers.delete(user.isarId);
    });
  }

  /// Récupère les utilisateurs distants depuis l'API et les fusionne dans Isar
  Future<List<AppUser>> fetchAndMergeServerUsers() async {
    await ensureSuperAdminExists();
    if (offlineMode) {
      return listAll();
    }

    try {
      final res = await _api.get<Map<String, dynamic>>('/users');
      final list = (res.data?['users'] as List?) ?? [];
      final now = DateTime.now();

      await _isar.writeTxn(() async {
        for (final item in list) {
          final email = item['email'] as String;
          final existing = await _isar.appUsers.filter().emailEqualTo(email).findFirst();

          final name = item['name'] as String? ?? 'Utilisateur';
          final role = item['role'] as String? ?? 'manager';
          final isActive = item['is_active'] as bool? ?? true;
          final disabledAtStr = item['disabled_at'] as String?;
          final disabledAt = disabledAtStr != null ? DateTime.tryParse(disabledAtStr) : null;
          final createdBy = item['created_by'] as String?;

          if (existing != null) {
            final updated = existing.copyWith(
              name: name,
              role: role,
              isActive: isActive,
              disabledAt: disabledAt,
              createdBy: createdBy ?? existing.createdBy,
              syncStatus: SyncStatus.synced,
              updatedAt: now,
            );
            await _isar.appUsers.put(updated);
          } else {
            final newUser = AppUser.create(
              uuid: _uuid.v4(),
              email: email,
              name: name,
              role: role,
              syncStatus: SyncStatus.synced,
              createdBy: createdBy,
              isActive: isActive,
              disabledAt: disabledAt,
              createdAt: now,
              updatedAt: now,
            );
            await _isar.appUsers.put(newUser);
          }
        }
      });
    } catch (_) {
      // Si offline, on continue avec les données locales
    }
    await ensureSuperAdminExists();
    return listAll();
  }

  Future<List<AppUser>> listAll() async {
    await ensureSuperAdminExists();
    return _isar.appUsers.where().sortByRole().findAll();
  }

  Stream<List<AppUser>> watchAll() {
    return _isar.appUsers.where().sortByRole().watch(fireImmediately: true);
  }

  Stream<int> watchPendingCount() {
    return _isar.appUsers
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .or()
        .syncStatusEqualTo(SyncStatus.error)
        .watch(fireImmediately: true)
        .map((l) => l.length);
  }
}
