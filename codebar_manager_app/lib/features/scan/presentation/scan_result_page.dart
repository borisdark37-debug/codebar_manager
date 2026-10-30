
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/collections/product.dart';
import '../../../core/services/image_compression_service.dart';

/// Page affichant les résultats d'un scan de code-barres.
/// Affiche toutes les infos encodées dans le code + récupère l'image depuis la BD locale.
class ScanResultPage extends StatelessWidget {
  final Map<String, dynamic> scannedData;
  final Product? product;

  const ScanResultPage({
    super.key,
    required this.scannedData,
    this.product,
  });

  @override
  Widget build(BuildContext context) {
    final hasProduct = product != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultat du scan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statut
            _StatusBanner(found: hasProduct),
            const SizedBox(height: 20),

            // Image (uniquement depuis la BD locale)
            if (hasProduct && product!.imageBase64 != null)
              _ProductImage(base64: product!.imageBase64!),

            const SizedBox(height: 16),

            // Informations du code scanné
            _SectionTitle('Informations du code scanné'),
            _InfoCard(data: _buildCodeInfo()),

            if (hasProduct) ...[
              const SizedBox(height: 16),
              _SectionTitle('Informations complémentaires (BD locale)'),
              _InfoCard(data: _buildLocalInfo()),
            ],

            const SizedBox(height: 24),

            // Bouton scanner un autre
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner un autre code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, String> _buildCodeInfo() {
    final result = <String, String>{};

    // Depuis le QR code scanné
    if (scannedData['code'] != null) {
      result['Code'] = scannedData['code'].toString();
    }
    if (scannedData['name'] != null) {
      result['Nom'] = scannedData['name'].toString();
    }
    if (scannedData['format'] != null) {
      result['Format'] = scannedData['format'].toString();
    }
    if (scannedData['containment'] != null) {
      result['Contenance'] = scannedData['containment'].toString();
    }
    if (scannedData['price'] != null) {
      final price = double.tryParse(scannedData['price'].toString()) ?? 0;
      result['Prix'] = '${price.toStringAsFixed(2)} €';
    }
    if (scannedData['qty'] != null) {
      result['Quantité'] = scannedData['qty'].toString();
    }

    if (result.isEmpty) {
      result['Données brutes'] = scannedData.toString();
    }
    return result;
  }

  Map<String, String> _buildLocalInfo() {
    if (product == null) return {};
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return {
      'Code interne': product!.internalCode,
      'UUID': product!.uuid,
      'Créé le': fmt.format(product!.createdAt),
      'Modifié le': fmt.format(product!.updatedAt),
      'Synchronisation': product!.syncStatus.name,
    };
  }
}

class _StatusBanner extends StatelessWidget {
  final bool found;
  const _StatusBanner({required this.found});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: found ? Colors.teal.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: found ? Colors.teal.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            found ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: found ? Colors.teal : Colors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              found
                  ? 'Produit trouvé dans la base de données locale.'
                  : 'Ce code n\'est pas encore référencé dans l\'application.\n'
                      'Les données affichées proviennent uniquement du code scanné.',
              style: TextStyle(
                color: found ? Colors.teal.shade800 : Colors.orange.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String base64;
  const _ProductImage({required this.base64});

  @override
  Widget build(BuildContext context) {
    final bytes = ImageCompressionService.decodeBase64(base64);
    if (bytes == null) return const SizedBox.shrink();

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          height: 200,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Map<String, String> data;
  const _InfoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: data.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${entry.key} :',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
