import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/collections/product.dart';
import '../../../core/services/barcode_service_svg.dart';
import '../../../core/services/image_compression_service.dart';
import '../../../core/services/share_service.dart';
import '../providers/export_providers.dart';
import 'widgets/export_format_dialog.dart';

class ProductFormPage extends ConsumerStatefulWidget {
  final Product? product;

  const ProductFormPage({super.key, this.product});

  bool get isEdit => product != null;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _formatController;
  late final TextEditingController _containmentController;
  late final TextEditingController _priceController;
  late final TextEditingController _quantityController;
  String? _imageBase64;
  String? _imageCompressionNote;
  bool _saving = false;
  bool _isCompressingImage = false;
  BarcodeExportType _previewType = BarcodeExportType.qrCode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _formatController = TextEditingController(
      text: widget.product?.format ?? '',
    );
    _containmentController = TextEditingController(
      text: widget.product?.containment ?? '',
    );
    _priceController = TextEditingController(
      text: widget.product?.price.toStringAsFixed(2) ?? '0.00',
    );
    _quantityController = TextEditingController(
      text: widget.product?.quantity.toString() ?? '0',
    );
    _imageBase64 = widget.product?.imageBase64;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _formatController.dispose();
    _containmentController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // L'image est maintenant obligatoire
    if (_imageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Une image est obligatoire pour enregistrer le produit.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
      final quantity = int.tryParse(_quantityController.text);
      if (price == null || price < 0 || quantity == null || quantity < 0) {
        throw const FormatException('Prix ou quantité invalide.');
      }
      if (widget.isEdit) {
        await repo.update(
          widget.product!,
          name: _nameController.text.trim(),
          format: _formatController.text.trim(),
          containment: _containmentController.text.trim(),
          price: price,
          quantity: quantity,
          imageBase64: _imageBase64,
        );
      } else {
        await repo.create(
          name: _nameController.text.trim(),
          format: _formatController.text.trim(),
          containment: _containmentController.text.trim(),
          price: price,
          quantity: quantity,
          imageBase64: _imageBase64,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              subtitle: const Text('Appareil photo avec compression automatique'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie / fichiers'),
              subtitle: const Text('Sélectionner une image existante'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    setState(() => _isCompressingImage = true);
    try {
      final result = await ImageCompressionService.pickAndCompress(
        source: source,
        maxDimension: 1024,
        quality: 75,
      );
      if (result == null) return;

      setState(() {
        _imageBase64 = result.base64;
        _imageCompressionNote = result.savingsPercentage > 5
            ? 'Optimisée : ${result.formattedCompressedSize} (-${result.savingsPercentage.toStringAsFixed(0)}%)'
            : 'Optimisée : ${result.formattedCompressedSize}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Image compressée avec succès (${result.formattedOriginalSize} → ${result.formattedCompressedSize})',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du traitement de l’image : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompressingImage = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce produit ?'),
        content: Text(
          '"${widget.product!.name}" sera déplacé dans la corbeille.\n'
          'Vous pourrez le restaurer ou le supprimer définitivement depuis l\'écran Corbeille.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(productRepositoryProvider).softDelete(widget.product!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              ], subject: 'Code ${widget.product?.internalCode ?? ""}'),
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
        title: Text(widget.isEdit ? 'Modifier le produit' : 'Nouveau produit'),
        actions: [
          if (widget.isEdit) ...[
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
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Exporter le code (SVG)',
              onPressed: isExporting
                  ? null
                  : () async {
                      final format = await showExportFormatDialog(
                        context,
                        title: 'Exporter ${widget.product!.internalCode}',
                        initialType: _previewType,
                      );
                      if (format != null) {
                        ref.read(exportControllerProvider.notifier).exportSingle(
                          widget.product!,
                          type: format,
                        );
                      }
                    },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: 'Supprimer',
              onPressed: _saving ? null : _delete,
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.isEdit) ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.teal.shade200),
                ),
                color: Colors.teal.shade50.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Code : ${widget.product!.internalCode}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                'Génération et export (1D ou 2D)',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          Chip(
                            label: Text(
                              _previewType == BarcodeExportType.barcode128
                                  ? 'Code 128'
                                  : 'QR Code',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: Colors.teal.shade100,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<BarcodeExportType>(
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
                        selected: {_previewType},
                        onSelectionChanged: (set) {
                          setState(() => _previewType = set.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: _previewType == BarcodeExportType.barcode128 ? 110 : 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: SvgPicture.string(
                          BarcodeSvgService().generateSvg(
                            widget.product!.internalCode,
                            uuid: widget.product!.uuid,
                            name: widget.product!.name,
                            format: widget.product!.format,
                            containment: widget.product!.containment,
                            price: widget.product!.price,
                            quantity: widget.product!.quantity,
                            type: _previewType,
                          ),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: isExporting
                                  ? null
                                  : () {
                                      ref
                                          .read(exportControllerProvider.notifier)
                                          .exportSingle(widget.product!, type: _previewType);
                                    },
                              icon: const Icon(Icons.file_download_outlined, size: 18),
                              label: Text(
                                _previewType == BarcodeExportType.barcode128
                                    ? 'Télécharger 1D'
                                    : 'Télécharger QR',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final svg = BarcodeSvgService().generateSvg(
                                  widget.product!.internalCode,
                                  uuid: widget.product!.uuid,
                                  name: widget.product!.name,
                                  format: widget.product!.format,
                                  containment: widget.product!.containment,
                                  price: widget.product!.price,
                                  quantity: widget.product!.quantity,
                                  type: _previewType,
                                );
                                final suffix = _previewType == BarcodeExportType.barcode128
                                    ? 'barcode'
                                    : 'qr';
                                final fileName = '${widget.product!.internalCode}-$suffix';
                                final file = await ShareService.getOrCreateSvgFile(
                                  fileName: fileName,
                                  svgContent: svg,
                                );
                                await ShareService.shareSvgFile(
                                  file: file,
                                  subject: '${widget.product!.internalCode} — ${widget.product!.name}',
                                );
                              },
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('Partager', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nom du produit *',
                hintText: 'Ex : Sérum visage éclat',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Prix (€) *',
                      prefixIcon: Icon(Icons.euro_outlined),
                    ),
                    validator: (v) =>
                        double.tryParse((v ?? '').replaceAll(',', '.')) == null
                            ? 'Prix invalide'
                            : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantité *',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    validator: (v) => int.tryParse(v ?? '') == null
                        ? 'Quantité invalide'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: (_saving || _isCompressingImage) ? null : _pickImage,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _imageBase64 == null
                      ? Colors.orange.shade700
                      : Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
              icon: _isCompressingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _imageBase64 == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.check_circle,
                      color: _imageBase64 == null
                          ? Colors.orange.shade700
                          : Theme.of(context).colorScheme.primary,
                    ),
              label: Text(
                _isCompressingImage
                    ? 'Compression de l’image...'
                    : _imageBase64 == null
                        ? 'Ajouter une image * (Obligatoire)'
                        : 'Image sélectionnée (Modifier)',
                style: TextStyle(
                  color: _imageBase64 == null
                      ? Colors.orange.shade800
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_imageBase64 != null) ...[
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    SizedBox(
                      height: 190,
                      width: double.infinity,
                      child: Builder(
                        builder: (_) {
                          final bytes = ImageCompressionService.decodeBase64(_imageBase64);
                          if (bytes == null) {
                            return const Center(
                              child: Text('Image impossible à afficher'),
                            );
                          }
                          return Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Text('Image impossible à afficher'),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filled(
                        tooltip: 'Retirer l’image',
                        onPressed: (_saving || _isCompressingImage)
                            ? null
                            : () => setState(() {
                                  _imageBase64 = null;
                                  _imageCompressionNote = null;
                                }),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
              if (_imageCompressionNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.speed, size: 16, color: Colors.teal),
                      const SizedBox(width: 4),
                      Text(
                        _imageCompressionNote!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.teal.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _formatController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Format *',
                hintText: 'Ex : 30 ml',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Format requis' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _containmentController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Contenance *',
                hintText: 'Ex : Flacon verre ambré',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Contenance requise' : null,
              onFieldSubmitted: (_) => _saving ? null : _save(),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                widget.isEdit
                    ? 'Enregistrer les modifications'
                    : 'Créer le produit',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Le code interne sera généré automatiquement à la création, '
                'au format CAP-XXXX.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
