import 'dart:typed_data';

import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:codebar_manager_app/core/services/barcode_service_svg.dart';
import 'package:codebar_manager_app/core/services/export_file_service.dart';
import 'package:codebar_manager_app/core/services/zip_export_service.dart';
import 'package:codebar_manager_app/features/products/providers/export_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockExportFileService extends ExportFileService {
  String? saveSvgResult;
  String? saveZipResult;
  String? lastSvgName;
  String? lastZipName;
  String? lastDialogTitle;
  int svgCallCount = 0;
  int zipCallCount = 0;
  bool shouldThrow = false;

  @override
  Future<String?> saveSvg({
    required String name,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    svgCallCount++;
    if (shouldThrow) throw Exception('Simulated save error');
    lastSvgName = name;
    lastDialogTitle = dialogTitle;
    return saveSvgResult;
  }

  @override
  Future<String?> saveZip({
    required String name,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    zipCallCount++;
    if (shouldThrow) throw Exception('Simulated zip error');
    lastZipName = name;
    lastDialogTitle = dialogTitle;
    return saveZipResult;
  }
}

class FakeZipExportService implements ZipExportService {
  ExportResult? resultToReturn;
  bool shouldThrow = false;
  BarcodeExportType? lastType;

  @override
  Future<ExportResult> exportAll({
    BarcodeExportType type = BarcodeExportType.qrCode,
  }) async {
    lastType = type;
    if (shouldThrow) throw Exception('Simulated zip generation error');
    return resultToReturn ??
        ExportResult(
          bytes: Uint8List.fromList([80, 75, 3, 4, 0, 0, 0, 0]),
          productCount: 3,
          fileName: 'qrcodes-test-archive',
          exportType: type,
        );
  }
}

void main() {
  final testProduct = Product.create(
    uuid: '00000000-0000-0000-0000-000000000001',
    internalCode: 'CAP-0001',
    name: 'Capsule Café',
    format: 'Boîte',
    containment: '10 pcs',
    price: 4.50,
    quantity: 100,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group('ExportController.exportSingle', () {
    late ProviderContainer container;
    late MockExportFileService mockSaver;

    setUp(() {
      mockSaver = MockExportFileService();
      container = ProviderContainer(
        overrides: [
          exportFileServiceProvider.overrideWithValue(mockSaver),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('sets ExportPhase.done when file is successfully saved to user destination', () async {
      mockSaver.saveSvgResult = 'C:/Users/User/Documents/CAP-0001-qr.svg';

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportSingle(testProduct, type: BarcodeExportType.qrCode);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.done);
      expect(state.savedPath, 'C:/Users/User/Documents/CAP-0001-qr.svg');
      expect(state.message, contains('CAP-0001-qr.svg'));
      expect(mockSaver.lastSvgName, 'CAP-0001-qr');
      expect(mockSaver.lastDialogTitle, contains('QR Code 2D'));
    });

    test('gracefully returns to idle with null savedPath when user cancels destination picker', () async {
      mockSaver.saveSvgResult = null; // User cancelled

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportSingle(testProduct, type: BarcodeExportType.qrCode);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.idle);
      expect(state.savedPath, isNull);
      expect(state.message, isNull);
    });

    test('sets ExportPhase.error when saving throws an error', () async {
      mockSaver.shouldThrow = true;

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportSingle(testProduct, type: BarcodeExportType.qrCode);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.error);
      expect(state.message, contains('Export impossible'));
    });
    test('ignores second export attempt when already busy', () async {
      mockSaver.saveSvgResult = 'C:/Users/User/Documents/CAP-0001-qr.svg';

      final controller = container.read(exportControllerProvider.notifier);
      final future1 = controller.exportSingle(testProduct, type: BarcodeExportType.qrCode);
      final future2 = controller.exportSingle(testProduct, type: BarcodeExportType.barcode128);

      await Future.wait([future1, future2]);
      expect(mockSaver.svgCallCount, 1);
    });
  });

  group('ExportController.exportAllAsZip', () {
    late ProviderContainer container;
    late MockExportFileService mockSaver;
    late FakeZipExportService fakeZipExporter;

    setUp(() {
      mockSaver = MockExportFileService();
      fakeZipExporter = FakeZipExportService();
      container = ProviderContainer(
        overrides: [
          exportFileServiceProvider.overrideWithValue(mockSaver),
          zipExportServiceProvider.overrideWithValue(fakeZipExporter),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('sets ExportPhase.done when zip file is successfully saved to user destination', () async {
      mockSaver.saveZipResult = 'C:/Users/User/Documents/qrcodes-test-archive.zip';

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportAllAsZip(type: BarcodeExportType.qrCode);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.done);
      expect(state.savedPath, 'C:/Users/User/Documents/qrcodes-test-archive.zip');
      expect(state.message, contains('ZIP exporté'));
      expect(state.message, contains('3 produit(s)'));
      expect(mockSaver.lastZipName, 'qrcodes-test-archive');
      expect(mockSaver.lastDialogTitle, contains('QR Codes'));
    });

    test('gracefully returns to idle with null savedPath when user cancels zip destination picker', () async {
      mockSaver.saveZipResult = null; // User cancelled

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportAllAsZip(type: BarcodeExportType.barcode128);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.idle);
      expect(state.savedPath, isNull);
      expect(state.message, isNull);
      expect(mockSaver.lastDialogTitle, contains('Codes-barres 1D'));
    });

    test('sets ExportPhase.error when zip exporter throws an error', () async {
      fakeZipExporter.shouldThrow = true;

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportAllAsZip(type: BarcodeExportType.qrCode);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.error);
      expect(state.message, contains('Export impossible'));
    });

    test('sets ExportPhase.error when saver throws an error', () async {
      mockSaver.shouldThrow = true;

      final controller = container.read(exportControllerProvider.notifier);
      await controller.exportAllAsZip(type: BarcodeExportType.qrCode);

      final state = container.read(exportControllerProvider);
      expect(state.phase, ExportPhase.error);
      expect(state.message, contains('Export impossible'));
    });

    test('ignores second exportAllAsZip attempt when already busy', () async {
      mockSaver.saveZipResult = 'C:/Users/User/Documents/qrcodes-test-archive.zip';

      final controller = container.read(exportControllerProvider.notifier);
      final future1 = controller.exportAllAsZip(type: BarcodeExportType.qrCode);
      final future2 = controller.exportAllAsZip(type: BarcodeExportType.barcode128);

      await Future.wait([future1, future2]);
      expect(mockSaver.zipCallCount, 1);
    });
  });
}
