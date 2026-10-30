import 'dart:convert';
import 'dart:typed_data';

import 'package:codebar_manager_app/core/services/barcode_service_svg.dart';
import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/collections/product.dart';
import '../../../core/services/export_file_service.dart';
import '../../../core/services/zip_export_service.dart';

enum ExportPhase { idle, busy, done, error }

class ExportState {
  final ExportPhase phase;
  final String? message;
  final String? savedPath;

  const ExportState({
    this.phase = ExportPhase.idle,
    this.message,
    this.savedPath,
  });

  ExportState busy() => const ExportState(phase: ExportPhase.busy);

  ExportState done(String path) => ExportState(
        phase: ExportPhase.done,
        savedPath: path,
        message: 'Export réussi',
      );

  ExportState error(String message) =>
      ExportState(phase: ExportPhase.error, message: message);
}

class ExportController extends StateNotifier<ExportState> {
  final Ref _ref;
  final BarcodeSvgService _svg;
  final ExportFileService _saver;
  final ZipExportService? _zipExporter;

  ExportController(
    this._ref, {
    BarcodeSvgService? svg,
    ExportFileService? saver,
    ZipExportService? zipExporter,
  })  : _svg = svg ?? BarcodeSvgService(),
        _saver = saver ?? ExportFileService(),
        _zipExporter = zipExporter,
        super(const ExportState());

  void reset() {
    state = const ExportState();
  }

  Future<void> exportAllAsZip({
    BarcodeExportType type = BarcodeExportType.qrCode,
  }) async {
    if (state.phase == ExportPhase.busy) return;
    state = state.busy();
    try {
      final exporter =
          _zipExporter ?? ZipExportService(_ref.read(productRepositoryProvider));
      final result = await exporter.exportAll(type: type);
      final label =
          type == BarcodeExportType.barcode128 ? 'Codes-barres 1D' : 'QR Codes';
      final path = await _saver.saveZip(
        name: result.fileName,
        bytes: result.bytes,
        dialogTitle: 'Enregistrer les $label (ZIP)',
      );
      if (path == null) {
        // L'utilisateur a annulé la sélection d'emplacement
        state = const ExportState();
        return;
      }
      state = ExportState(
        phase: ExportPhase.done,
        savedPath: path,
        message:
            'ZIP exporté ($label, ${result.productCount} produit(s), '
            '${(result.bytes.lengthInBytes / 1024).toStringAsFixed(1)} Ko)',
      );
    } catch (e) {
      state = state.error('Export impossible : $e');
    }
  }

  /// Exporte un seul produit sous forme de fichier SVG (QR Code ou Code-barres).
  Future<void> exportSingle(
    Product product, {
    BarcodeExportType type = BarcodeExportType.qrCode,
  }) async {
    if (state.phase == ExportPhase.busy) return;
    state = state.busy();
    try {
      final svg = _svg.generateSvg(
        product.internalCode,
        uuid: product.uuid,
        name: product.name,
        format: product.format,
        containment: product.containment,
        price: product.price,
        quantity: product.quantity,
        type: type,
      );
      final bytes = Uint8List.fromList(utf8.encode(svg));
      final suffix = type == BarcodeExportType.barcode128 ? 'barcode' : 'qr';
      final fileName = '${product.internalCode}-$suffix';
      final label =
          type == BarcodeExportType.barcode128 ? 'Code-barres 1D' : 'QR Code 2D';
      final path = await _saver.saveSvg(
        name: fileName,
        bytes: bytes,
        dialogTitle: 'Enregistrer le $label ($fileName.svg)',
      );
      if (path == null) {
        // L'utilisateur a annulé la sélection d'emplacement
        state = const ExportState();
        return;
      }
      state = ExportState(
        phase: ExportPhase.done,
        savedPath: path,
        message: '$label ($fileName.svg) exporté avec succès',
      );
    } catch (e) {
      state = state.error('Export impossible : $e');
    }
  }
}

final exportFileServiceProvider = Provider<ExportFileService>((ref) {
  return ExportFileService();
});

final zipExportServiceProvider = Provider<ZipExportService?>((ref) => null);

final exportControllerProvider =
    StateNotifierProvider<ExportController, ExportState>((ref) {
  return ExportController(
    ref,
    saver: ref.watch(exportFileServiceProvider),
    zipExporter: ref.watch(zipExportServiceProvider),
  );
});
