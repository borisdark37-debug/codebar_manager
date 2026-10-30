import 'package:flutter/material.dart';

import '../../../../core/services/sync_service.dart';

class SyncResultView extends StatelessWidget {
  final SyncResult result;

  const SyncResultView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.pushed == 0 && result.synced == 0 && result.fatalError == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aucune modification à synchroniser.'),
        ),
      );
    }

    final isFull = result.isFullSuccess;
    final bgColor = isFull
        ? Colors.green.shade50
        : (result.hasErrors ? Colors.orange.shade50 : Colors.blue.shade50);
    final icon = isFull
        ? Icons.check_circle
        : (result.hasErrors ? Icons.warning_amber : Icons.info_outline);

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: isFull ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(
                  isFull
                      ? 'Synchronisation réussie'
                      : 'Synchronisation partielle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result.pushed > 0) _Line('Envoyés', '${result.pushed}'),
            if (result.synced > 0) _Line('Réussis', '${result.synced}'),
            if (result.conflicts > 0) _Line('Conflits', '${result.conflicts}'),
            if (result.errors > 0) _Line('Erreurs', '${result.errors}'),

            // Détail des erreurs
            if (result.items.any((i) => i.status != SyncItemStatus.synced)) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Détails des échecs',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...result.items
                  .where((i) => i.status != SyncItemStatus.synced)
                  .map(
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            i.status == SyncItemStatus.conflict
                                ? Icons.merge_type
                                : Icons.error_outline,
                            size: 16,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${i.uuid.substring(0, 8)}… — '
                              '${i.message ?? i.status.name}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;

  const _Line(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value),
        ],
      ),
    );
  }
}
