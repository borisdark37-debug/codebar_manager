import 'dart:convert';
import 'package:flutter/material.dart';

class ActivityLogDetailPage extends StatelessWidget {
  final Map<String, dynamic> log;

  const ActivityLogDetailPage({super.key, required this.log});

  String _formatAction(String? action) {
    switch (action) {
      case 'auth.login':
        return 'Connexion utilisateur';
      case 'product.created':
        return 'Création de produit';
      case 'product.updated':
        return 'Modification de produit';
      case 'product.deleted':
        return 'Suppression de produit';
      case 'user.created':
        return 'Création d\'un compte utilisateur';
      default:
        return action ?? 'Action inconnue';
    }
  }

  Color _actionColor(String? action) {
    if (action == null) return Colors.blueGrey;
    if (action.startsWith('auth.')) return Colors.blue;
    if (action == 'product.created') return Colors.green;
    if (action == 'product.updated') return Colors.orange;
    if (action == 'product.deleted') return Colors.red;
    if (action.startsWith('user.')) return Colors.purple;
    return Colors.teal;
  }

  IconData _actionIcon(String? action) {
    switch (action) {
      case 'auth.login':
        return Icons.login;
      case 'product.created':
        return Icons.add_circle_outline;
      case 'product.updated':
        return Icons.edit_note_outlined;
      case 'product.deleted':
        return Icons.delete_outline;
      case 'user.created':
        return Icons.person_add_outlined;
      default:
        return Icons.history;
    }
  }

  String _metaLabel(String key) {
    switch (key) {
      case 'internal_code':
        return 'Code interne';
      case 'name':
        return 'Nom du produit';
      case 'price':
        return 'Prix';
      case 'quantity':
        return 'Quantité';
      case 'format':
        return 'Format';
      case 'containment':
        return 'Contenance';
      case 'role':
        return 'Rôle attribué';
      case 'email':
        return 'Email';
      case 'device':
        return 'Appareil client';
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = log['action']?.toString();
    final user = log['user'] as Map<String, dynamic>?;
    final ipAddress = log['ip_address']?.toString() ?? 'Non renseignée';
    final createdAt = log['created_at']?.toString() ?? 'Date inconnue';
    final entityType = log['entity_type']?.toString();
    final entityId = log['entity_id']?.toString();
    final metadata = log['metadata'];

    final color = _actionColor(action);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de l\'activité'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // En-tête de l'action
          Card(
            color: color.withValues(alpha: 0.08),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: color,
                    child: Icon(_actionIcon(action), color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatAction(action),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Action système : $action',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Informations contextuelles
          Text(
            'Informations générales',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Utilisateur auteur'),
                  subtitle: Text(user?['name'] != null
                      ? '${user!['name']} (${user['email'] ?? 'Sans email'})'
                      : 'Système / Anonyme'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text('Date et heure'),
                  subtitle: Text(createdAt),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('Adresse IP cliente'),
                  subtitle: Text(ipAddress),
                ),
                if (entityType != null) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Entité cible'),
                    subtitle: Text('$entityType ${entityId != null ? "($entityId)" : ""}'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Métadonnées associées
          Text(
            'Données et métadonnées associées',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  if (metadata == null) {
                    return const Text('Aucune métadonnée supplémentaire.');
                  }

                  if (metadata is Map) {
                    final entries = metadata.entries.toList();
                    if (entries.isEmpty) {
                      return const Text('Aucune métadonnée enregistrée.');
                    }

                    return Column(
                      children: entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 140,
                                child: Text(
                                  _metaLabel(entry.key.toString()),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.value?.toString() ?? '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  }

                  // Si c'est du JSON string
                  return Text(
                    jsonEncode(metadata),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
