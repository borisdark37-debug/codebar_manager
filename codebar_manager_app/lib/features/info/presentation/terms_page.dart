import 'package:flutter/material.dart';

/// Page Conditions d'utilisation de CodeBar Manager.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conditions d\'utilisation')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conditions Générales d\'Utilisation',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Dernière mise à jour : Octobre 2024',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 24),
            _Article(
              number: '1',
              title: 'Acceptation des conditions',
              content:
                  'En utilisant l\'application CodeBar Manager, vous acceptez '
                  'les présentes conditions générales d\'utilisation. Si vous '
                  'n\'acceptez pas ces conditions, veuillez ne pas utiliser '
                  'l\'application.',
            ),
            _Article(
              number: '2',
              title: 'Utilisation autorisée',
              content:
                  'L\'application est destinée à un usage professionnel de '
                  'gestion de stock et de codes-barres. Vous vous engagez à '
                  'utiliser l\'application conformément à sa destination et aux '
                  'lois en vigueur dans votre pays.',
            ),
            _Article(
              number: '3',
              title: 'Comptes et accès',
              content:
                  'Vous êtes responsable de la confidentialité de vos identifiants '
                  'de connexion. Vous ne devez pas partager votre compte avec des '
                  'tiers non autorisés. Signalez immédiatement toute utilisation '
                  'non autorisée de votre compte à l\'administrateur.',
            ),
            _Article(
              number: '4',
              title: 'Données et confidentialité',
              content:
                  'Les données saisies dans l\'application (produits, codes, '
                  'images) sont stockées localement sur votre appareil et peuvent '
                  'être synchronisées vers un serveur central. Vous êtes responsable '
                  'des données que vous saisissez et de leur conformité aux '
                  'réglementations applicables.',
            ),
            _Article(
              number: '5',
              title: 'Limitations de responsabilité',
              content:
                  'L\'application est fournie « en l\'état ». Nous ne garantissons '
                  'pas une disponibilité continue du service de synchronisation. '
                  'En cas de perte de données due à une défaillance matérielle '
                  'ou logicielle, notre responsabilité ne saurait être engagée '
                  'au-delà de la valeur du service souscrit.',
            ),
            _Article(
              number: '6',
              title: 'Propriété intellectuelle',
              content:
                  'L\'application CodeBar Manager et l\'ensemble de ses composants '
                  '(code source, interface, logos) sont protégés par les droits '
                  'de propriété intellectuelle. Toute reproduction, modification '
                  'ou distribution non autorisée est strictement interdite.',
            ),
            _Article(
              number: '7',
              title: 'Modification des conditions',
              content:
                  'Nous nous réservons le droit de modifier ces conditions à tout '
                  'moment. Les utilisateurs seront informés des changements '
                  'importants via une notification dans l\'application.',
            ),
            _Article(
              number: '8',
              title: 'Contact',
              content:
                  'Pour toute question relative à ces conditions d\'utilisation, '
                  'veuillez contacter votre administrateur système ou le support '
                  'technique de votre organisation.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Article extends StatelessWidget {
  final String number;
  final String title;
  final String content;
  const _Article({required this.number, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(content, style: const TextStyle(height: 1.6, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
