import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/collections/product.dart';
import '../providers/product_provider.dart';

/// Page affichant tous les produits supprimés (soft-delete = corbeille).
/// Tous les rôles peuvent accéder à cette page et restaurer des produits.
/// Les produits peuvent également être supprimés définitivement.
class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashedAsync = ref.watch(trashedProductsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corbeille'),
        actions: [
          trashedAsync.whenOrNull(
            data: (items) => items.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () => _confirmRestoreAll(context, ref),
                        icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
                        label: const Text('Tout restaurer'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        tooltip: 'Vider la corbeille',
                        onPressed: () => _confirmClearAll(context, ref),
                      ),
                    ],
                  )
                : null,
          ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: trashedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Erreur : $e', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_sweep_outlined,
                    size: 72,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'La corbeille est vide',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Les produits supprimés apparaîtront ici.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.amber.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${products.length} produit(s) en corbeille. Les codes et identifiants des produits supprimés définitivement ne seront jamais réattribués.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) => _TrashTile(product: products[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRestoreAll(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tout restaurer'),
        content: const Text(
          'Voulez-vous restaurer tous les produits supprimés ? '
          'Ils seront remis dans la liste active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurer tout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(productRepositoryProvider).restoreAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tous les produits ont été restaurés.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider la corbeille'),
        content: const Text(
          'Voulez-vous supprimer définitivement tous les produits de la corbeille ?\n\n'
          '⚠️ Attention : cette action est irréversible. Aucun de leurs numéros ou codes ne sera réattribué.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vider définitivement'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(productRepositoryProvider).clearTrash();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La corbeille a été vidée définitivement.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _TrashTile extends ConsumerWidget {
  final Product product;
  const _TrashTile({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deletedDate = product.deletedAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(product.deletedAt!)
        : '–';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.red.shade50,
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      title: Text(
        product.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${product.internalCode} • Supprimé le $deletedDate',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => _restore(context, ref),
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Restaurer'),
            style: TextButton.styleFrom(foregroundColor: Colors.teal),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
            tooltip: 'Supprimer définitivement',
            onPressed: () => _confirmDeletePermanently(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    await ref.read(productRepositoryProvider).restore(product);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} restauré.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeletePermanently(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement'),
        content: Text(
          'Voulez-vous supprimer définitivement "${product.name}" (${product.internalCode}) ?\n\n'
          '⚠️ Cette action est irréversible. Ce numéro et cet identifiant ne seront jamais réutilisés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(productRepositoryProvider).deletePermanently(product);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.internalCode} supprimé définitivement.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
