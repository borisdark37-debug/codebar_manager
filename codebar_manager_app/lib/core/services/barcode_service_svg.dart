import 'dart:convert';
import 'package:barcode/barcode.dart';

enum BarcodeExportType {
  qrCode,
  barcode128,
}

/// Génère le contenu SVG d'un QR Code ou d'un Code-barres standard (Code 128) pour un produit.
class BarcodeSvgService {
  static final Barcode _qr = Barcode.qrCode();
  static final Barcode _code128 = Barcode.code128();

  /// Génère un SVG selon le type choisi (QR Code ou Code-barres).
  String generateSvg(
    String internalCode, {
    required String uuid,
    required String name,
    String format = '',
    String containment = '',
    double price = 0,
    int quantity = 0,
    BarcodeExportType type = BarcodeExportType.qrCode,
  }) {
    if (type == BarcodeExportType.barcode128) {
      return generateBarcode128Svg(internalCode);
    } else {
      return generateQrSvg(
        internalCode,
        uuid: uuid,
        name: name,
        format: format,
        containment: containment,
        price: price,
        quantity: quantity,
      );
    }
  }

  /// Génère un QR Code SVG contenant l'ensemble des données encodées en JSON,
  /// et seul le code interne (CAP-XXXX) visible textuellement sous le QR Code.
  String generateQrSvg(
    String internalCode, {
    required String uuid,
    required String name,
    String format = '',
    String containment = '',
    double price = 0,
    int quantity = 0,
  }) {
    if (internalCode.isEmpty) {
      throw ArgumentError('Le code interne ne peut pas être vide.');
    }

    final payload = jsonEncode({
      'code': internalCode,
      'uuid': uuid,
      'name': name,
      'format': format,
      'containment': containment,
      'price': price,
      'qty': quantity,
    });

    const double qrSize = 220;
    const double totalHeight = 255;

    var svg = _qr.toSvg(
      payload,
      width: qrSize,
      height: qrSize,
      drawText: false,
    );

    svg = svg.replaceAll(
      RegExp(r'height="[0-9.]+"'),
      'height="${totalHeight.toInt()}"',
    );
    svg = svg.replaceAll(
      RegExp(r'viewBox="[0-9.\s]+"'),
      'viewBox="0 0 ${qrSize.toInt()} ${totalHeight.toInt()}"',
    );

    final labelSvg =
        '<text x="${(qrSize / 2).toInt()}" y="244" font-family="Arial, Helvetica, sans-serif" font-size="15" font-weight="bold" text-anchor="middle" fill="#000000">'
        '${_xml(internalCode)}'
        '</text>';

    return svg.replaceFirst('</svg>', '$labelSvg</svg>');
  }

  /// Génère un Code-barres standard 1D (Code 128) au format SVG
  /// avec les barres et le libellé texte lisible sous les barres.
  String generateBarcode128Svg(String internalCode) {
    if (internalCode.isEmpty) {
      throw ArgumentError('Le code interne ne peut pas être vide.');
    }

    return _code128.toSvg(
      internalCode,
      width: 280,
      height: 95,
      drawText: true,
      fontHeight: 14,
    );
  }

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
