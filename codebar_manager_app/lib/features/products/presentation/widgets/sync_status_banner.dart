import 'package:codebar_manager_app/core/services/sync_service.dart';
import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:codebar_manager_app/features/sync/providers/sync_poviders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingCountStreamProvider);
    final pendingMutationsAsync = ref.watch(pendingMutationsCountStreamProvider);
    final syncState = ref.watch(syncControllerProvider);

    final pendingMutations = pendingMutationsAsync.valueOrNull ?? 0;
    final pendingProducts = pendingAsync.valueOrNull ?? 0;
    final pending = pendingMutations > 0 ? pendingMutations : pendingProducts;
    final isSyncing = syncState.phase == SyncPhase.syncing;
    final isError = syncState.phase == SyncPhase.error;

    Color color;
    IconData icon;
    String title;
    String subtitle;
    Widget actionWidget;

    if (isSyncing) {
      color = Colors.blue;
      icon = Icons.sync;
      title = 'Synchronisation en cours…';
      subtitle = 'Envoi des mutations Outbox et récupération des deltas';
      actionWidget = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
      );
    } else if (isError) {
      color = Colors.red.shade700;
      icon = Icons.sync_problem_outlined;
      title = 'Erreur de synchronisation';
      subtitle = syncState.fatalMessage ?? 'Vérifiez la connexion au serveur central.';
      actionWidget = TextButton(
        onPressed: () {
          ref.read(syncControllerProvider.notifier).synchronize(forceOnline: true);
        },
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: const Text('Réessayer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    } else if (pending > 0) {
      color = Colors.orange.shade800;
      icon = Icons.cloud_upload_outlined;
      title = 'Synchronisation en attente';
      subtitle = '$pending modification(s) locale(s) prêtes à être envoyées';
      actionWidget = FilledButton.tonal(
        onPressed: () async {
          final res = await ref.read(syncControllerProvider.notifier).synchronize(forceOnline: true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res.isFullSuccess
                      ? 'Synchronisation réussie (${res.synced} élément(s)).'
                      : (res.fatalError ?? 'Synchronisation terminée avec erreurs.'),
                ),
                backgroundColor: res.isFullSuccess ? Colors.teal : Colors.orange.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('Synchroniser', style: TextStyle(fontSize: 12)),
      );
    } else {
      color = Colors.teal;
      icon = Icons.cloud_done_outlined;
      title = SyncService.offlineMode ? 'Mode Hors-ligne (À jour)' : 'En ligne • Synchronisé';
      subtitle = 'Base locale Isar et serveur central parfaitement synchronisés';
      actionWidget = TextButton.icon(
        onPressed: () async {
          final res = await ref.read(syncControllerProvider.notifier).synchronize(forceOnline: true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res.isFullSuccess
                      ? 'Synchronisation terminée : Données à jour.'
                      : (res.fatalError ?? 'Synchronisation terminée.'),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        icon: const Icon(Icons.sync, size: 14),
        label: const Text('Actualiser', style: TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
      );
    }

    return Container(
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          actionWidget,
        ],
      ),
    );
  }
}
