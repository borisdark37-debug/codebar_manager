import 'package:codebar_manager_app/core/services/barcode_service_svg.dart';
import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/collections/product.dart';
import '../../../core/services/share_service.dart';
import '../../../core/services/zip_export_service.dart';
import '../providers/export_providers.dart';
import 'widgets/export_format_dialog.dart';

class BarcodeGalleryPage extends ConsumerStatefulWidget {
  const BarcodeGalleryPage({super.key});

  @override
  ConsumerState<BarcodeGalleryPage> createState() => _BarcodeGalleryPageState();
}

class _BarcodeGalleryPageState extends ConsumerState<BarcodeGalleryPage> {
  BarcodeExportType _selectedType = BarcodeExportType.qrCode;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final hasProducts = (productsAsync.valueOrNull ?? const <Product>[]).isNotEmpty;
    final exportState = ref.watch(exportControllerProvider);
    final isExporting = exportState.phase == ExportPhase.busy;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galerie des codes'),
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
          if (hasProducts) ...[
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Tout exporter (ZIP)',
              onPressed: isExporting ? null : () => _exportAllZip(context),
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Tout partager (ZIP)',
              onPressed: isExporting ? null : () => _shareAllZip(context),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Sélecteur QR Code (2D) vs Code-barres (1D)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<BarcodeExportType>(
                segments: const [
                  ButtonSegment(
                    value: BarcodeExportType.qrCode,
                    label: Text('QR Code (2D)'),
                    icon: Icon(Icons.qr_code_2),
                  ),
                  ButtonSegment(
                    value: BarcodeExportType.barcode128,
                    label: Text('Code-barres (1D)'),
                    icon: Icon(Icons.line_weight),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (set) {
                  setState(() => _selectedType = set.first);
                },
              ),
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
                  return _buildEmptyState(context);
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = _columnsFor(constraints.maxWidth);
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: _selectedType == BarcodeExportType.barcode128 ? 1.25 : 1.05,
                      ),
                      itemCount: products.length,
                      itemBuilder: (_, i) => _BarcodeCard(
                        product: products[i],
                        activeType: _selectedType,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_2, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Aucun code disponible',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Créez des produits pour générer leurs codes.',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  int _columnsFor(double width) {
    if (width >= 1200) return 4;
    if (width >= 800) return 3;
    return 2;
  }

  Future<void> _exportAllZip(BuildContext context) async {
    final format = await showExportFormatDialog(
      context,
      title: 'Exporter tout le catalogue',
      initialType: _selectedType,
    );
    if (format == null) return;

    ref.read(exportControllerProvider.notifier).exportAllAsZip(type: format);
  }

  Future<void> _shareAllZip(BuildContext context) async {
    final format = await showExportFormatDialog(
      context,
      title: 'Partager tout le catalogue',
      initialType: _selectedType,
    );
    if (format == null) return;

    try {
      final repo = ref.read(productRepositoryProvider);
      final result = await ZipExportService(repo).exportAll(type: format);

      final label = format == BarcodeExportType.barcode128 ? 'Codes-barres 1D' : 'QR Codes';
      await ShareService.shareZipContent(
        fileName: result.fileName,
        bytes: result.bytes,
        subject: '$label CodeBar Manager (${result.productCount} produits)',
      );

      if (context.mounted) {
        _showSnack(context, '${result.productCount} code(s) partagé(s) ($label)');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnack(context, 'Erreur de partage : $e');
      }
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _BarcodeCard extends ConsumerWidget {
  final Product product;
  final BarcodeExportType activeType;

  const _BarcodeCard({
    required this.product,
    required this.activeType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isExporting =
        ref.watch(exportControllerProvider).phase == ExportPhase.busy;
    final svg = BarcodeSvgService().generateSvg(
      product.internalCode,
      uuid: product.uuid,
      name: product.name,
      format: product.format,
      containment: product.containment,
      price: product.price,
      quantity: product.quantity,
      type: activeType,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showChoiceDialog(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: SvgPicture.string(svg, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.internalCode,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          product.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    tooltip: activeType == BarcodeExportType.barcode128
                        ? 'Télécharger le code-barres 1D'
                        : 'Télécharger le QR code (2D)',
                    onPressed: isExporting ? null : () => _exportActive(context, ref),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 18),
                    tooltip: activeType == BarcodeExportType.barcode128
                        ? 'Partager le code-barres 1D'
                        : 'Partager le QR code (2D)',
                    onPressed: () => _shareActive(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportActive(BuildContext context, WidgetRef ref) async {
    ref.read(exportControllerProvider.notifier).exportSingle(product, type: activeType);
  }

  Future<void> _shareActive(BuildContext context) async {
    await _doShare(context, activeType);
  }

  Future<void> _exportWithDialog(BuildContext context, WidgetRef ref) async {
    final format = await showExportFormatDialog(
      context,
      title: 'Exporter ${product.internalCode}',
      initialType: activeType,
    );
    if (format == null) return;

    ref.read(exportControllerProvider.notifier).exportSingle(product, type: format);
  }

  Future<void> _shareWithDialog(BuildContext context) async {
    final format = await showExportFormatDialog(
      context,
      title: 'Partager ${product.internalCode}',
      initialType: activeType,
    );
    if (format == null || !context.mounted) return;
    await _doShare(context, format);
  }

  Future<void> _doShare(BuildContext context, BarcodeExportType format) async {
    final svg = BarcodeSvgService().generateSvg(
      product.internalCode,
      uuid: product.uuid,
      name: product.name,
      format: product.format,
      containment: product.containment,
      price: product.price,
      quantity: product.quantity,
      type: format,
    );
    try {
      final suffix = format == BarcodeExportType.barcode128 ? 'barcode' : 'qr';
      final fileName = '${product.internalCode}-$suffix';
      final file = await ShareService.getOrCreateSvgFile(
        fileName: fileName,
        svgContent: svg,
      );
      await ShareService.shareSvgFile(
        file: file,
        subject: '${product.internalCode} — ${product.name}',
      );
      if (context.mounted) {
        final label = format == BarcodeExportType.barcode128 ? 'Code-barres 1D' : 'QR Code (2D)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label ($fileName.svg) partagé'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de partage : $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showChoiceDialog(BuildContext context, WidgetRef ref) async {
    final activeLabel = activeType == BarcodeExportType.barcode128 ? 'Code-barres 1D' : 'QR Code (2D)';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${product.internalCode} — ${product.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.file_download_outlined, color: Colors.teal),
                title: Text('Télécharger en $activeLabel'),
                subtitle: const Text('Enregistrer immédiatement le code affiché'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportActive(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune, color: Colors.teal),
                title: const Text('Choisir un autre format d\'export'),
                subtitle: const Text('Basculer entre Code-barres 1D et QR Code (2D)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportWithDialog(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blue),
                title: const Text('Partager le code SVG'),
                subtitle: const Text('Choisir le format et partager'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareWithDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
