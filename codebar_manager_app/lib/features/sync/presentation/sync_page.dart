import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/sync_service.dart';
import '../../products/providers/product_provider.dart';
import '../providers/sync_poviders.dart';
import 'widgets/login_form.dart';
import 'widgets/sync_result_view.dart';

class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final syncState = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: auth.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erreur : $e',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (isAuthenticated) {
          if (!isAuthenticated) {
            return const LoginForm();
          }
          return _AuthenticatedView(syncState: syncState);
        },
      ),
    );
  }
}

class _AuthenticatedView extends ConsumerStatefulWidget {
  final SyncState syncState;

  const _AuthenticatedView({required this.syncState});

  @override
  ConsumerState<_AuthenticatedView> createState() => _AuthenticatedViewState();
}

class _AuthenticatedViewState extends ConsumerState<_AuthenticatedView> {
  bool _offlineSwitch = SyncService.offlineMode;

  @override
  Widget build(BuildContext context) {
    final syncState = widget.syncState;
    final isSyncing = syncState.phase == SyncPhase.syncing;
    final lastSyncAsync = ref.watch(lastSyncProvider);
    final pendingProductsAsync = ref.watch(pendingCountStreamProvider);
    final pendingMutationsAsync = ref.watch(pendingMutationsCountStreamProvider);
    final healthAsync = ref.watch(serverHealthProvider);

    final pendingMutations = pendingMutationsAsync.valueOrNull ?? 0;
    final pendingProducts = pendingProductsAsync.valueOrNull ?? 0;
    final pendingTotal = pendingMutations > 0 ? pendingMutations : pendingProducts;

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final lastSyncDate = lastSyncAsync.valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Carte État de la synchronisation & Connectivité
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _offlineSwitch
                                ? Icons.cloud_off
                                : (healthAsync.valueOrNull == true
                                    ? Icons.cloud_done
                                    : Icons.cloud_queue),
                            color: _offlineSwitch
                                ? Colors.orange.shade800
                                : (healthAsync.valueOrNull == true
                                    ? Colors.teal
                                    : Colors.blueGrey),
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _offlineSwitch ? 'Mode Hors-ligne' : 'Mode En ligne (Synchronisé)',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _offlineSwitch ? Colors.orange.shade900 : Colors.teal.shade900,
                                ),
                          ),
                        ],
                      ),
                      Switch(
                        value: !_offlineSwitch,
                        activeThumbColor: Colors.teal,
                        onChanged: (online) {
                          setState(() {
                            _offlineSwitch = !online;
                            SyncService.setOfflineMode(!online);
                          });
                          ref.invalidate(serverHealthProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                online
                                    ? 'Mode En ligne activé : synchronisation automatique disponible.'
                                    : 'Mode Hors-ligne forcé : données sécurisées en base Isar.',
                              ),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Dernière synchro : ',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                      Text(
                        lastSyncDate != null ? dateFormat.format(lastSyncDate) : 'Jamais effectuée',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.outbox, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Modifications en attente (Outbox) : ',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                      Text(
                        '$pendingTotal élément(s)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: pendingTotal > 0 ? Colors.orange.shade800 : Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.dns_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Serveur central : ',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                      Text(
                        healthAsync.when(
                          data: (ok) => ok ? 'Connecté (OK)' : 'Inaccessible / Hors-ligne',
                          loading: () => 'Vérification…',
                          error: (_, _) => 'Injoignable',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: healthAsync.valueOrNull == true ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Bouton Synchronisation Complète
          FilledButton.icon(
            onPressed: isSyncing
                ? null
                : () async {
                    final res = await ref
                        .read(syncControllerProvider.notifier)
                        .synchronize(forceOnline: true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            res.isFullSuccess
                                ? 'Synchronisation réussie (${res.synced} éléments traités).'
                                : (res.fatalError ?? 'Synchronisation terminée avec erreurs.'),
                          ),
                          backgroundColor: res.isFullSuccess ? Colors.teal : Colors.orange.shade900,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
            icon: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
            label: Text(
              isSyncing ? 'Synchronisation en cours…' : 'Synchroniser maintenant (Push & Pull)',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF087F8C),
            ),
          ),

          const SizedBox(height: 12),

          // Bouton Push uniquement
          ElevatedButton.icon(
            onPressed: isSyncing
                ? null
                : () async {
                    await ref.read(syncControllerProvider.notifier).pushPending(forceOnline: true);
                    final state = ref.read(syncControllerProvider);
                    if (context.mounted) {
                      final msg = state.lastResult != null
                          ? 'Envoi terminé (${state.lastResult!.synced} synchronisés, ${state.lastResult!.errors} erreurs).'
                          : (state.fatalMessage ?? 'Envoi terminé.');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                      );
                    }
                  },
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Envoyer au serveur (Push Outbox)'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),

          const SizedBox(height: 12),

          // Bouton Pull uniquement
          OutlinedButton.icon(
            onPressed: isSyncing
                ? null
                : () async {
                    await ref.read(syncControllerProvider.notifier).pullAll(forceOnline: true);
                    final state = ref.read(syncControllerProvider);
                    if (context.mounted) {
                      final msg = state.lastResult != null
                          ? 'Restauration terminée (${state.lastResult!.synced} éléments mis à jour).'
                          : (state.fatalMessage ?? 'Restauration terminée.');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                      );
                    }
                  },
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Restaurer depuis le serveur (Pull Delta)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),

          const SizedBox(height: 24),

          // Affichage du résultat
          if (syncState.lastResult != null)
            SyncResultView(result: syncState.lastResult!),

          if (syncState.fatalMessage != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueGrey.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncState.fatalMessage!,
                        style: TextStyle(color: Colors.blueGrey.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Déconnexion
          TextButton.icon(
            onPressed: () async {
              ref.read(syncServiceProvider).stopAutoSync();
              await ref.read(secureStorageProvider).deleteToken();
              ref.invalidate(authStateProvider);
              ref.invalidate(authGateProvider);
              ref.invalidate(authRoleProvider);
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text(
              'Se déconnecter',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
