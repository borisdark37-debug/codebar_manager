import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../core/database/collections/app_user.dart';
import '../../../core/database/collections/sync_mutation.dart';
import '../../../core/database/isar_provider.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/local_auth_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/secure_stokage_service.dart';
import '../../../core/services/sync_service.dart';
import '../../admin/providers/user_providers.dart';

// --- Infrastructure ---

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final localAuthServiceProvider = Provider<LocalAuthService>(
  (ref) => LocalAuthService(),
);

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(isarProvider),
    ref.watch(apiClientProvider),
    NotificationService(), // Exactement 3 paramètres positionnels
  );
});

// --- Auth state ---

enum AuthGateState {
  needsSetup,
  needsLogin,
  authenticated,
}

final authGateProvider = FutureProvider<AuthGateState>((ref) async {
  final storage = ref.watch(secureStorageProvider);

  // 1. Initialiser préventivement les Super Admins par défaut en base Isar locale
  final userRepo = ref.watch(userRepositoryProvider);
  await userRepo.ensureSuperAdminExists();

  // 2. Vérifier si un utilisateur est déjà connecté
  final role = await storage.getRole();
  final hasToken = await storage.hasToken();

  if (role != null && role.isNotEmpty) {
    // Si l'utilisateur a été désactivé par un administrateur en base locale
    if (role != 'super_admin') {
      final email = await storage.getUserEmail();
      if (email != null && email.isNotEmpty) {
        final isar = ref.watch(isarProvider);
        final user = await isar.appUsers
            .filter()
            .emailEqualTo(email, caseSensitive: false)
            .findFirst();
        if (user != null && !user.isActive) {
          await storage.deleteToken();
          return AuthGateState.needsLogin;
        }
      }
    }
    return AuthGateState.authenticated;
  }

  // 3. Vérifier si l'utilisateur est connecté en mode serveur avec token Sanctum
  if (hasToken) {
    return AuthGateState.authenticated;
  }

  return AuthGateState.needsLogin;
});

final authStateProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final role = await storage.getRole();
  if (role != null && role.isNotEmpty) {
    return true;
  }
  return ref.watch(authServiceProvider).isAuthenticated();
});

final authRoleProvider = FutureProvider<String?>((ref) async {
  return ref.watch(secureStorageProvider).getRole();
});

// --- État de synchronisation & Santé Serveur ---

final serverHealthProvider = FutureProvider<bool>((ref) async {
  return ref.watch(syncServiceProvider).checkServerHealth();
});

enum SyncPhase { idle, syncing, done, error }

class SyncState {
  final SyncPhase phase;
  final SyncResult? lastResult;
  final String? fatalMessage;

  const SyncState({
    this.phase = SyncPhase.idle,
    this.lastResult,
    this.fatalMessage,
  });

  SyncState copyWith({
    SyncPhase? phase,
    SyncResult? lastResult,
    String? fatalMessage,
    bool clearMessage = false,
  }) {
    return SyncState(
      phase: phase ?? this.phase,
      lastResult: lastResult ?? this.lastResult,
      fatalMessage: clearMessage ? null : (fatalMessage ?? this.fatalMessage),
    );
  }
}

class SyncController extends StateNotifier<SyncState> {
  final SyncService _service;
  final Ref _ref;

  SyncController(this._service, this._ref) : super(const SyncState());

  /// Pousse les mutations locales vers le serveur
  Future<void> pushPending({bool forceOnline = false}) async {
    if (SyncService.offlineMode && !forceOnline) {
      state = const SyncState(
        phase: SyncPhase.idle,
        fatalMessage:
            'Mode Hors-ligne : La synchronisation serveur est temporairement désactivée. Vos modifications sont conservées en toute sécurité dans la base locale.',
      );
      return;
    }

    state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
    final result = await _service.pushPending(forceOnline: true);

    if (result.fatalError != null) {
      state = state.copyWith(
        phase: SyncPhase.error,
        fatalMessage: result.fatalError,
        lastResult: result,
      );
    } else {
      state = state.copyWith(
        phase: SyncPhase.done,
        lastResult: result,
      );
      _ref.invalidate(lastSyncProvider);
    }
  }

  /// Restaure ou récupère les deltas depuis le serveur
  Future<void> pullAll({bool forceOnline = false}) async {
    if (SyncService.offlineMode && !forceOnline) {
      state = const SyncState(
        phase: SyncPhase.idle,
        fatalMessage:
            'Mode Hors-ligne : La restauration depuis le serveur est temporairement désactivée. Vos données locales sont actives.',
      );
      return;
    }

    state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
    final result = await _service.pullAll(forceOnline: true);

    if (result.fatalError != null) {
      state = state.copyWith(
        phase: SyncPhase.error,
        fatalMessage: result.fatalError,
        lastResult: result,
      );
    } else {
      state = state.copyWith(
        phase: SyncPhase.done,
        lastResult: result,
      );
      _ref.invalidate(lastSyncProvider);
    }
  }

  /// Synchronisation bidirectionnelle unifiée (Push Outbox puis Pull Delta)
  Future<SyncResult> synchronize({bool forceOnline = true}) async {
    state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
    final result = await _service.synchronize(forceOnline: forceOnline);

    if (result.fatalError != null && !result.fatalError!.contains('Mode Hors-ligne')) {
      state = state.copyWith(
        phase: SyncPhase.error,
        fatalMessage: result.fatalError,
        lastResult: result,
      );
    } else {
      state = state.copyWith(
        phase: SyncPhase.done,
        lastResult: result,
      );
      _ref.invalidate(lastSyncProvider);
    }
    return result;
  }
}

final syncControllerProvider = StateNotifierProvider<SyncController, SyncState>(
  (ref) {
    return SyncController(ref.watch(syncServiceProvider), ref);
  },
);

// --- Métadonnées de synchronisation ---

final lastSyncProvider = FutureProvider<DateTime?>((ref) async {
  return ref.watch(syncServiceProvider).getLastSyncAt();
});

/// Stream du nombre de mutations locales en attente dans l'Outbox
final pendingMutationsCountStreamProvider = StreamProvider<int>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.syncMutations
      .filter()
      .statusEqualTo(MutationStatus.pending)
      .watch(fireImmediately: true)
      .map((list) => list.length);
});

/// Provider autoDispose activant la synchronisation périodique continue (toutes les 8s).
final autoSyncProvider = Provider.autoDispose<void>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  syncService.startAutoSync();
  ref.onDispose(() {
    syncService.stopAutoSync();
  });
});
