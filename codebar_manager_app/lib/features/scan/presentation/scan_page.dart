import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../products/providers/product_provider.dart';
import 'scan_result_page.dart';

/// Page de scan de codes-barres / QR codes.
/// Ouvre la caméra et détecte automatiquement le code scanné.
/// Redirige vers la page de détail du produit correspondant.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _isProcessing = true);
    await _controller.stop();

    final rawValue = barcode.rawValue!;
    final repo = ref.read(productRepositoryProvider);

    try {
      // Essai 1 : JSON encodé dans un QR code
      Map<String, dynamic>? data;
      try {
        data = json.decode(rawValue) as Map<String, dynamic>;
      } catch (_) {
        data = null;
      }

      if (data != null && data.containsKey('code')) {
        // QR code CodeBar Manager : chercher par internalCode
        final code = data['code'] as String?;
        if (code != null) {
          final product = await repo.findByInternalCode(code);
          if (mounted) {
            await Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ScanResultPage(
                  scannedData: data!,
                  product: product,
                ),
              ),
            );
            return;
          }
        }
      }

      // Essai 2 : code brut = internalCode direct (ex: CAP-0001)
      final product = await repo.findByInternalCode(rawValue.trim());
      if (mounted) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ScanResultPage(
              scannedData: {'code': rawValue},
              product: product,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la lecture du code : $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isProcessing = false);
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner un code'),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Lampe torche',
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_outlined),
            tooltip: 'Retourner la caméra',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Viseur central
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.teal,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Instruction
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_isProcessing)
                  const CircularProgressIndicator(color: Colors.teal)
                else
                  const Text(
                    'Placez le code-barres ou QR code dans le cadre',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
