import 'package:codebar_manager_app/core/services/barcode_service_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BarcodeSvgService', () {
    final service = BarcodeSvgService();

    test('generates valid QR Code SVG with payload and text', () {
      final svg = service.generateSvg(
        'CAP-0042',
        uuid: 'test-uuid-1',
        name: 'Produit Test',
        format: '50ml',
        containment: 'Flacon',
        price: 19.99,
        quantity: 5,
        type: BarcodeExportType.qrCode,
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('CAP-0042'));
    });

    test('generates valid 1D Barcode (Code 128) SVG', () {
      final svg = service.generateSvg(
        'CAP-0042',
        uuid: 'test-uuid-1',
        name: 'Produit Test',
        type: BarcodeExportType.barcode128,
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, contains('CAP-0042'));
      // Code 128 SVG contains path bars and text
      expect(svg, contains('<path'));
      expect(svg, contains('<text'));
    });

    test('throws ArgumentError on empty internal code', () {
      expect(
        () => service.generateSvg(
          '',
          uuid: 'test-uuid-2',
          name: 'Empty Code',
          type: BarcodeExportType.barcode128,
        ),
        throwsArgumentError,
      );

      expect(
        () => service.generateSvg(
          '',
          uuid: 'test-uuid-2',
          name: 'Empty Code',
          type: BarcodeExportType.qrCode,
        ),
        throwsArgumentError,
      );
    });

    test('1D and 2D SVGs are structurally different for the same product', () {
      final qr = service.generateSvg(
        'CAP-0042',
        uuid: 'test-uuid-1',
        name: 'Produit Test',
        type: BarcodeExportType.qrCode,
      );
      final barcode1d = service.generateSvg(
        'CAP-0042',
        uuid: 'test-uuid-1',
        name: 'Produit Test',
        type: BarcodeExportType.barcode128,
      );

      expect(qr != barcode1d, isTrue);
      // Code 128 has a distinct viewBox width of 280 and height of 95
      expect(barcode1d, contains('viewBox="0.00000 0.00000 280.00000 95.00000"'));
      // QR has viewBox width 220 and height 255
      expect(qr, contains('viewBox="0 0 220 255"'));
    });

    test('escapes XML special characters in QR Code text label to maintain valid SVG structure', () {
      final svg = service.generateSvg(
        'CAP-&<>"',
        uuid: 'test-uuid-special',
        name: 'Produit & Ingrédients <Bio>',
        type: BarcodeExportType.qrCode,
      );

      // Le texte visible dans le SVG doit avoir ses caractères spéciaux XML échappés
      expect(svg, contains('CAP-&amp;&lt;&gt;&quot;'));
      expect(svg, isNot(contains('<text>CAP-&<>"</text>')));
      expect(svg, endsWith('</svg>'));
    });
  });
}
