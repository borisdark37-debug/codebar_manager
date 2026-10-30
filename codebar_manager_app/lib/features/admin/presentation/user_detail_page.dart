import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/collections/app_user.dart';
import '../../../core/database/collections/product.dart';
import '../../../core/utils/error_handler.dart';
import '../providers/user_providers.dart';

class UserDetailPage extends ConsumerStatefulWidget {
  final AppUser user;

  const UserDetailPage({super.key, required this.user});

  @override
  ConsumerState<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends ConsumerState<UserDetailPage> {
  late AppUser _user;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  Future<void> _sync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mode Hors-ligne : ${_user.name} est enregistré en local. La synchronisation avec le serveur est temporairement désactivée.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleActive() async {
    final action = _user.isActive ? 'désactiver' : 'activer';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} l\'utilisateur'),
        content: Text(
          _user.isActive
              ? 'Voulez-vous vraiment désactiver ce compte ?\n\n'
                'L\'utilisateur ne pourra plus se connecter. Au bout de 30 jours d\'inactivité, il pourra être supprimé définitivement.'
              : 'Voulez-vous réactiver ce compte utilisateur ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: _user.isActive ? FilledButton.styleFrom(backgroundColor: Colors.orange) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final updated = await ref.read(userRepositoryProvider).toggleActive(_user);
      setState(() => _user = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _user.isActive ? 'Compte utilisateur réactivé.' : 'Compte utilisateur désactivé.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : ${AppErrorHandler.friendly(e)}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePermanently() async {
    final isEligible = _user.isPurgeEligible;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement'),
        content: Text(
          isEligible
              ? 'Ce compte est désactivé depuis plus de 30 jours. Voulez-vous le supprimer définitivement du système ?'
              : 'Attention : Ce compte n\'est désactivé que depuis ${_user.disabledAt != null ? DateTime.now().difference(_user.disabledAt!).inDays : 0} jour(s).\n\n'
                'Voulez-vous quand même forcer sa suppression définitive ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(userRepositoryProvider).deletePermanently(_user, force: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_user.name} a été supprimé définitivement.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : ${AppErrorHandler.friendly(e)}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: Text(
          'Voulez-vous réinitialiser le mot de passe de ${_user.name} ?\n\n'
          'Le mot de passe deviendra "0000".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réinitialiser à 0000'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final updated = await ref.read(userRepositoryProvider).resetPasswordOnline(_user, '0000');
      setState(() => _user = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mot de passe de ${_user.name} réinitialisé à "0000" avec succès.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : ${AppErrorHandler.friendly(e)}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final isSuperAdmin = _user.role == 'super_admin';

    return Scaffold(
      appBar: AppBar(
        title: Text(_user.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.offline_pin_outlined),
            tooltip: 'Mode Hors-ligne',
            onPressed: _sync,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Carte principale d'en-tête
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        _user.name.isNotEmpty ? _user.name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _user.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(_user.email, style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildRoleChip(_user.role),
                        _buildSyncChip(_user.syncStatus),
                        _buildStatusChip(_user.isActive),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Alerte si compte désactivé (calcul des 30 jours)
            if (!_user.isActive && _user.disabledAt != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Compte désactivé le ${fmt.format(_user.disabledAt!)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _user.isPurgeEligible
                                ? '✓ Éligible à la suppression définitive (plus de 30 jours d\'inactivité).'
                                : 'Suppression automatique dans ${_user.daysUntilPurge} jour(s).',
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Détails utilisateur
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informations détaillées',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Rôle',
                      value: _roleLabel(_user.role),
                    ),
                    const Divider(height: 16),
                    _DetailRow(
                      label: 'État de synchronisation',
                      value: _syncLabel(_user.syncStatus),
                    ),
                    const Divider(height: 16),
                    // Affichage de la personne l'ayant ajouté (sauf pour le super admin)
                    if (!isSuperAdmin) ...[
                      _DetailRow(
                        label: 'Ajouté par',
                        value: _user.createdBy != null && _user.createdBy!.isNotEmpty
                            ? _user.createdBy!
                            : 'Super Admin',
                      ),
                      const Divider(height: 16),
                    ],
                    _DetailRow(
                      label: 'Statut du compte',
                      value: _user.isActive ? 'Actif' : 'Désactivé',
                    ),
                    const Divider(height: 16),
                    _DetailRow(
                      label: 'Date de création',
                      value: fmt.format(_user.createdAt),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            FilledButton.tonalIcon(
              onPressed: _sync,
              icon: const Icon(Icons.offline_pin_outlined),
              label: const Text('Mode Hors-ligne (Stocké en local)'),
            ),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _busy ? null : _resetPassword,
              icon: const Icon(Icons.lock_reset),
              label: const Text('Réinitialiser le mot de passe (0000)'),
            ),
            const SizedBox(height: 10),

            // Désactivation / Réactivation (non applicable au Super Admin)
            if (!isSuperAdmin) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _toggleActive,
                icon: Icon(_user.isActive ? Icons.block : Icons.check_circle_outline),
                label: Text(_user.isActive ? 'Désactiver le compte' : 'Activer le compte'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _user.isActive ? Colors.orange.shade800 : Colors.teal,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _deletePermanently,
                icon: const Icon(Icons.delete_forever),
                label: Text(
                  _user.isPurgeEligible
                      ? 'Supprimer définitivement (30j révolus)'
                      : 'Supprimer définitivement',
                ),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(String role) {
    String label = 'Gérant';
    Color color = Colors.blue;
    if (role == 'super_admin') {
      label = 'Super Admin';
      color = Colors.purple;
    } else if (role == 'admin') {
      label = 'Admin';
      color = Colors.teal;
    }
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildSyncChip(SyncStatus status) {
    final color = status == SyncStatus.synced ? Colors.green : Colors.teal;
    final label = status == SyncStatus.synced
        ? 'Synchronisé'
        : 'Mode Local (Hors-ligne)';
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 4),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildStatusChip(bool isActive) {
    return Chip(
      label: Text(
        isActive ? 'Actif' : 'Désactivé',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.teal : Colors.red,
        ),
      ),
      backgroundColor: (isActive ? Colors.teal : Colors.red).withValues(alpha: 0.1),
      side: BorderSide(color: (isActive ? Colors.teal : Colors.red).withValues(alpha: 0.3)),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return 'Super Administrateur';
      case 'admin':
        return 'Administrateur';
      case 'manager':
        return 'Gérant';
      default:
        return role;
    }
  }

  String _syncLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return 'Synchronisé avec le serveur';
      case SyncStatus.pending:
      case SyncStatus.error:
        return 'Mode Local (Enregistré sur l\'appareil)';
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
