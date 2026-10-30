import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingAlertBadge extends ConsumerWidget {
  const PendingAlertBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(pendingCountStreamProvider);
    final count = countAsync.valueOrNull ?? 0;

    return IconButton(
      tooltip: 'Mode Hors-ligne (Base locale)',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: Colors.teal,
        child: const Icon(
          Icons.offline_pin_outlined,
          color: Colors.teal,
        ),
      ),
      onPressed: () => _showStatusDialog(context, count),
    );
  }

  void _showStatusDialog(BuildContext context, int count) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.offline_pin_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('Mode Hors-ligne actif'),
          ],
        ),
        content: Text(
          '$count produit(s) enregistré(s) dans la base locale (Isar).\n\n'
          'Toutes vos modifications sont conservées sur cet appareil sans nécessiter de connexion réseau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
