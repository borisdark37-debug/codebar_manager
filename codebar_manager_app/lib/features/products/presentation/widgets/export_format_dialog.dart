import 'package:flutter/material.dart';
import '../../../../core/services/barcode_service_svg.dart';

/// Dialogue invitant l'utilisateur à choisir entre un Code-barres (1D) ou un QR Code (2D).
Future<BarcodeExportType?> showExportFormatDialog(
  BuildContext context, {
  String? title,
  BarcodeExportType? initialType,
}) async {
  return showDialog<BarcodeExportType>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? 'Format d\'exportation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choisissez le type de code à générer et exporter :',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          ListTile(
            selected: initialType == BarcodeExportType.qrCode,
            selectedTileColor: const Color(0xFF087F8C).withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: initialType == BarcodeExportType.qrCode
                    ? const Color(0xFF087F8C)
                    : Colors.grey.shade300,
                width: initialType == BarcodeExportType.qrCode ? 2 : 1,
              ),
            ),
            leading: const Icon(Icons.qr_code_2, size: 36, color: Color(0xFF087F8C)),
            title: const Text('QR Code (2D)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
              'Encode l\'ensemble des informations du produit (nom, prix, quantité, etc.)',
              style: TextStyle(fontSize: 12),
            ),
            trailing: initialType == BarcodeExportType.qrCode
                ? const Icon(Icons.check_circle, color: Color(0xFF087F8C))
                : null,
            onTap: () => Navigator.pop(ctx, BarcodeExportType.qrCode),
          ),
          const SizedBox(height: 12),
          ListTile(
            selected: initialType == BarcodeExportType.barcode128,
            selectedTileColor: const Color(0xFF087F8C).withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: initialType == BarcodeExportType.barcode128
                    ? const Color(0xFF087F8C)
                    : Colors.grey.shade300,
                width: initialType == BarcodeExportType.barcode128 ? 2 : 1,
              ),
            ),
            leading: const Icon(Icons.line_weight, size: 36, color: Color(0xFF087F8C)),
            title: const Text('Code-barres (1D)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
              'Format linéaire standard Code 128 avec le code interne lisible.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: initialType == BarcodeExportType.barcode128
                ? const Icon(Icons.check_circle, color: Color(0xFF087F8C))
                : null,
            onTap: () => Navigator.pop(ctx, BarcodeExportType.barcode128),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}
