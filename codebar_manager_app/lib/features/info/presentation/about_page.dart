import 'package:flutter/material.dart';

/// Page À Propos de l'application CodeBar Manager.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 48,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'CodeBar Manager',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            _Section(
              title: 'Description',
              content:
                  'CodeBar Manager est une application de gestion de stock '
                  'intégrant la création et le scan de codes-barres et QR codes. '
                  'Elle fonctionne en mode hors-ligne et synchronise vos données '
                  'avec un serveur central lorsque vous êtes connecté.',
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'Fonctionnalités principales',
              content:
                  '• Gestion des produits (création, modification, suppression)\n'
                  '• Génération de QR codes avec données encodées\n'
                  '• Scanner intégré pour lire les codes produits\n'
                  '• Mode hors-ligne avec synchronisation différée\n'
                  '• Gestion multi-utilisateurs par rôles\n'
                  '• Journal d\'activité complet\n'
                  '• Export des codes en SVG et ZIP',
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'Rôles utilisateurs',
              content:
                  '• Super Admin : gestion complète, création d\'utilisateurs\n'
                  '• Admin : gestion des produits et synchronisation\n'
                  '• Gérant : consultation et gestion du stock',
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'Technologies',
              content:
                  '• Application mobile : Flutter\n'
                  '• Base de données locale : Isar\n'
                  '• Backend : Laravel / PostgreSQL\n'
                  '• Authentification : Laravel Sanctum',
            ),
            const SizedBox(height: 32),
            Text(
              '© 2024 CodeBar Manager. Tous droits réservés.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String content;
  const _Section({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(content, style: const TextStyle(height: 1.6)),
          ],
        ),
      ),
    );
  }
}
