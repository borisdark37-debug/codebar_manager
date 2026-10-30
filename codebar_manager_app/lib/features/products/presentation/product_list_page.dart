import 'package:codebar_manager_app/features/products/presentation/Widgets/empty_product_view.dart';
import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/collections/product.dart';
import '../../sync/presentation/sync_page.dart';
import '../providers/export_providers.dart';
import 'barcode_gallery_page.dart';
import 'product_form_page.dart';
import 'widgets/export_format_dialog.dart';
import 'widgets/pending_alert_badge.dart';
import 'widgets/product_tile.dart';
import 'widgets/sync_status_banner.dart';

class ProductListPage extends ConsumerWidget {
  const ProductListPage({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Product? product,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormPage(product: product)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final currentSort = ref.watch(productSortProvider);
    final exportState = ref.watch(exportControllerProvider);

    ref.listen<ExportState>(exportControllerProvider, (_, next) {
      if (next.phase == ExportPhase.done && next.savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message ?? 'Export réussi'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Partager',
              onPressed: () => Share.shareXFiles([
                XFile(next.savedPath!),
              ], subject: 'Codes-barres CodeBar Manager'),
            ),
          ),
        );
        Future.microtask(
          () => ref.read(exportControllerProvider.notifier).reset(),
        );
      } else if (next.phase == ExportPhase.error && next.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message!),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
        Future.microtask(
          () => ref.read(exportControllerProvider.notifier).reset(),
        );
      }
    });

    final hasProducts =
        (productsAsync.valueOrNull ?? const <Product>[]).isNotEmpty;
    final isExporting = exportState.phase == ExportPhase.busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits'),
        actions: [
          if (isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.grid_view_outlined),
            tooltip: 'Galerie des codes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BarcodeGalleryPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Synchronisation',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SyncPage()),
            ),
          ),
          const PendingAlertBadge(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onSelected: (value) async {
              switch (value) {
                case 'sort_code':
                  ref.read(productSortProvider.notifier).state =
                      ProductSort.code;
                  break;
                case 'sort_name':
                  ref.read(productSortProvider.notifier).state =
                      ProductSort.name;
                  break;
                case 'sort_date':
                  ref.read(productSortProvider.notifier).state =
                      ProductSort.dateDesc;
                  break;
                case 'export_all':
                  final format = await showExportFormatDialog(
                    context,
                    title: 'Exporter tout le catalogue',
                  );
                  if (format != null) {
                    ref.read(exportControllerProvider.notifier).exportAllAsZip(type: format);
                  }
                  break;
                case 'gallery':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BarcodeGalleryPage(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (_) => [
              _sortItem(
                'sort_code',
                'Trier par code',
                currentSort,
                ProductSort.code,
              ),
              _sortItem(
                'sort_name',
                'Trier par nom',
                currentSort,
                ProductSort.name,
              ),
              _sortItem(
                'sort_date',
                'Plus récents',
                currentSort,
                ProductSort.dateDesc,
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'gallery',
                child: Row(
                  children: [
                    Icon(Icons.grid_view_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Galerie des codes'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export_all',
                enabled: hasProducts && !isExporting,
                child: const Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Exporter tout (ZIP)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher (nom, code, format…)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(productSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Erreur : $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return EmptyProductsView(
                    onCreate: () => _openForm(context, ref),
                  );
                }
                return ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) {
                    final p = products[i];
                    return ProductTile(
                      product: p,
                      onTap: () => _openForm(context, ref, product: p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Produit'),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(
    String value,
    String label,
    ProductSort current,
    ProductSort target,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            target == current ? Icons.check : Icons.circle_outlined,
            size: 16,
            color: target == current ? Colors.teal : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
