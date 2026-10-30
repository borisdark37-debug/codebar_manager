import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:codebar_manager_app/core/services/barcode_service_svg.dart';

import '../database/collections/product.dart';
import 'product_repository.dart';

/// Résultat d'un export : les octets du ZIP et des métadonnées utiles à l'UI.
class ExportResult {
  final Uint8List bytes;
  final int productCount;
  final String fileName;
  final BarcodeExportType exportType;

  ExportResult({
    required this.bytes,
    required this.productCount,
    required this.fileName,
    this.exportType = BarcodeExportType.qrCode,
  });
}

/// Construit un ZIP contenant un SVG (QR code ou Code-barres) par produit + un fichier index.csv.
class ZipExportService {
  final ProductRepository _repo;
  final BarcodeSvgService _svg;

  ZipExportService(this._repo, {BarcodeSvgService? svg})
      : _svg = svg ?? BarcodeSvgService();

  Future<ExportResult> exportAll({
    BarcodeExportType type = BarcodeExportType.qrCode,
  }) async {
    final products = await _repo.listAll();
    if (products.isEmpty) {
      throw StateError('Aucun produit à exporter.');
    }

    final archive = Archive();
    final suffix = type == BarcodeExportType.barcode128 ? 'barcode' : 'qr';

    // 1) Un SVG par produit, nommé d'après le code interne et le format.
    for (final p in products) {
      final svg = _svg.generateSvg(
        p.internalCode,
        uuid: p.uuid,
        name: p.name,
        format: p.format,
        containment: p.containment,
        price: p.price,
        quantity: p.quantity,
        type: type,
      );
      final bytes = utf8.encode(svg);
      archive.addFile(
        ArchiveFile('${p.internalCode}-$suffix.svg', bytes.length, bytes),
      );
    }

    // 2) Index CSV pour retrouver les correspondances facilement.
    final csvBytes = utf8.encode(_buildCsv(products));
    archive.addFile(ArchiveFile('index.csv', csvBytes.length, csvBytes));

    // 3) Encodage ZIP.
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) {
      throw StateError('Échec de la compression ZIP.');
    }

    final typePrefix = type == BarcodeExportType.barcode128 ? 'codebarres' : 'qrcodes';

    return ExportResult(
      bytes: Uint8List.fromList(zipped),
      productCount: products.length,
      fileName: _buildFileName(typePrefix),
      exportType: type,
    );
  }

  String _buildCsv(List<Product> products) {
    final sb = StringBuffer();
    sb.writeln('internal_code,name,format,containment,price,quantity,uuid');
    for (final p in products) {
      sb.writeln(
        [
          p.internalCode,
          _csvEscape(p.name),
          _csvEscape(p.format),
          _csvEscape(p.containment),
          p.price.toStringAsFixed(2),
          p.quantity.toString(),
          p.uuid,
        ].join(','),
      );
    }
    return sb.toString();
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _buildFileName(String prefix) {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '$prefix-'
        '${now.year}${pad(now.month)}${pad(now.day)}-'
        '${pad(now.hour)}${pad(now.minute)}';
  }
}
