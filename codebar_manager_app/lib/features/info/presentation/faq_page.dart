import 'package:flutter/material.dart';

/// Page FAQ (Foire Aux Questions) de CodeBar Manager.
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  static const _faqs = [
    _Faq(
      question: 'Comment me connecter à l\'application ?',
      answer:
          'Selon votre rôle :\n'
          '• Super Admin : utilisez vos identifiants locaux configurés lors de '
          'la première installation sur cet appareil.\n'
          '• Admin / Gérant : connectez-vous avec les identifiants fournis par '
          'votre Super Admin. Une connexion internet est requise lors de cette '
          'première connexion.',
    ),
    _Faq(
      question: 'L\'application fonctionne-t-elle sans internet ?',
      answer:
          'Oui ! CodeBar Manager est conçue pour fonctionner en mode hors-ligne. '
          'Vous pouvez créer, modifier et consulter vos produits sans connexion. '
          'La synchronisation avec le serveur se fera automatiquement dès que '
          'vous serez de nouveau connecté.',
    ),
    _Faq(
      question: 'Comment synchroniser mes données avec le serveur ?',
      answer:
          'Rendez-vous dans la page "Synchronisation" depuis le menu principal '
          'ou la liste des produits. Assurez-vous d\'être connecté à internet, '
          'puis appuyez sur "Envoyer les données en attente". Vous pouvez aussi '
          'recevoir les données du serveur avec "Récupérer depuis le serveur".',
    ),
    _Faq(
      question: 'Comment scanner un code-barres ?',
      answer:
          'Depuis l\'accueil, appuyez sur "Scanner un code". Autorisez l\'accès '
          'à la caméra si demandé. Pointez la caméra vers le code-barres ou '
          'QR code. L\'application détectera automatiquement le code et affichera '
          'les informations du produit correspondant.',
    ),
    _Faq(
      question: 'J\'ai supprimé un produit par erreur, comment le récupérer ?',
      answer:
          'Ne vous inquiétez pas ! Les produits supprimés sont placés dans la '
          '"Corbeille" et ne sont pas définitivement effacés. Accédez à la '
          'corbeille depuis le menu de la liste des produits, puis appuyez sur '
          '"Restaurer" à côté du produit souhaité. Vous pouvez aussi tout '
          'restaurer en une seule fois.',
    ),
    _Faq(
      question: 'Comment réinitialiser mon mot de passe ?',
      answer:
          'Sur la page de connexion, appuyez sur "Mot de passe oublié". '
          'Le Super Admin peut réinitialiser le mot de passe de n\'importe quel '
          'utilisateur (y compris le sien) vers "0000" depuis la page de '
          'gestion des utilisateurs. Il est recommandé de changer ce mot '
          'de passe par défaut immédiatement après.',
    ),
    _Faq(
      question: 'Comment créer un nouvel utilisateur ?',
      answer:
          'Seul le Super Admin peut créer des utilisateurs. Depuis l\'accueil, '
          'accédez à "Gérer les utilisateurs". Remplissez le formulaire avec '
          'le nom, l\'email, le mot de passe et le rôle (Admin ou Gérant). '
          'Synchronisez ensuite les données pour que le compte soit disponible '
          'sur le serveur.',
    ),
    _Faq(
      question: 'Comment exporter les codes-barres ?',
      answer:
          'Depuis la liste des produits, appuyez sur le menu "⋮" et choisissez '
          '"Exporter tout (ZIP)". Vous pouvez aussi accéder à la galerie de '
          'codes-barres et exporter individuellement chaque code en format SVG.',
    ),
    _Faq(
      question: 'Que contient un QR code généré ?',
      answer:
          'Chaque QR code contient le code interne (CAP-XXXX), l\'UUID, le nom '
          'du produit, son format, sa contenance, son prix et sa quantité. '
          'L\'image du produit n\'est pas encodée dans le QR code mais reste '
          'visible dans l\'application lors du scan.',
    ),
    _Faq(
      question: 'L\'application est lente ou plante, que faire ?',
      answer:
          'Essayez de redémarrer l\'application. Si le problème persiste, '
          'vérifiez que vous disposez d\'assez d\'espace de stockage sur votre '
          'appareil. En cas de problème persistant, contactez votre '
          'administrateur système.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Questions fréquentes (FAQ)')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _faqs.length,
        itemBuilder: (_, i) => _FaqCard(faq: _faqs[i]),
      ),
    );
  }
}

class _Faq {
  final String question;
  final String answer;
  const _Faq({required this.question, required this.answer});
}

class _FaqCard extends StatefulWidget {
  final _Faq faq;
  const _FaqCard({required this.faq});

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        leading: Icon(
          _expanded ? Icons.help : Icons.help_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          widget.faq.question,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              widget.faq.answer,
              style: const TextStyle(height: 1.6, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
