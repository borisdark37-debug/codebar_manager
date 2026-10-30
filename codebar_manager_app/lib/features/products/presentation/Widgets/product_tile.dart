import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/collections/product.dart';
import '../../providers/export_providers.dart';
import 'export_format_dialog.dart';

class ProductTile extends ConsumerWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductTile({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isPending = product.syncStatus == SyncStatus.pending;
    final isExporting =
        ref.watch(exportControllerProvider).phase == ExportPhase.busy;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: isPending
            ? Colors.orange.shade100
            : Colors.teal.shade100,
        child: Icon(
          Icons.qr_code_2,
          color: isPending ? Colors.orange.shade800 : Colors.teal.shade800,
        ),
      ),
      title: Text(
        '${product.internalCode} — ${product.name}',
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text('${product.format} · ${product.containment}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: 'Exporter le code (SVG)',
            onPressed: isExporting
                ? null
                : () async {
                    final format = await showExportFormatDialog(
                      context,
                      title: 'Exporter ${product.internalCode}',
                    );
                    if (format != null) {
                      ref
                          .read(exportControllerProvider.notifier)
                          .exportSingle(product, type: format);
                    }
                  },
          ),
          Chip(
            label: Text(
              isPending ? 'en attente' : 'synchronisé',
              style: const TextStyle(fontSize: 11),
            ),
            backgroundColor: isPending
                ? Colors.orange.shade50
                : Colors.green.shade50,
            side: BorderSide(
              color: isPending ? Colors.orange.shade200 : Colors.green.shade200,
            ),
          ),
        ],
      ),
    );
  }
}
