import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../core/database/collections/app_user.dart';
import '../../../core/database/isar_provider.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/error_handler.dart';
import '../../admin/providers/user_providers.dart';
import '../../sync/providers/sync_poviders.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  String? _userName;
  String? _userRole;
  String? _email;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final storage = ref.read(secureStorageProvider);
    final localAuth = ref.read(localAuthServiceProvider);
    final isar = ref.read(isarProvider);
    final userRepo = ref.read(userRepositoryProvider);

    await userRepo.ensureSuperAdminExists();

    final name = await storage.getUserName();
    final role = await storage.getRole();
    final email = await storage.getUserEmail() ?? (role == 'super_admin' ? await localAuth.getEmail() : null);

    AppUser? appUser;
    if (email != null && email.isNotEmpty) {
      appUser = await isar.appUsers
          .filter()
          .emailEqualTo(email, caseSensitive: false)
          .findFirst();
    }

    if (mounted) {
      setState(() {
        _userName = name ?? appUser?.name ?? 'Utilisateur';
        _userRole = role ?? appUser?.role ?? 'manager';
        _email = email ?? appUser?.email ?? 'Non renseigné';
        _loading = false;
      });
    }
  }

  Future<void> _syncProfile() async {
    setState(() => _syncing = true);
    try {
      final res = await ref.read(syncControllerProvider.notifier).synchronize(forceOnline: true);
      await ref.read(userRepositoryProvider).syncAllPending();
      await _loadProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.isFullSuccess
                  ? 'Synchronisation réussie (${res.synced} élément(s) traités).'
                  : (res.fatalError ?? 'Synchronisation terminée avec avertissements.'),
            ),
            backgroundColor: res.isFullSuccess ? Colors.teal : Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de synchronisation : ${AppErrorHandler.friendly(e)}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _changePassword() async {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer de mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nouveau mot de passe',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (newPassCtrl.text.isEmpty || newPassCtrl.text != confirmPassCtrl.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Les mots de passe ne correspondent pas.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      if (_userRole == 'super_admin') {
        final localAuth = ref.read(localAuthServiceProvider);
        await localAuth.changePassword(newPassCtrl.text);
      }
      final isar = ref.read(isarProvider);
      final email = _email;
      if (email != null && email.isNotEmpty) {
        final user = await isar.appUsers.filter().emailEqualTo(email).findFirst();
        if (user != null) {
          await ref.read(userRepositoryProvider).updatePassword(user, newPassCtrl.text);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mot de passe mis à jour et programmé pour synchronisation.'),
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
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(secureStorageProvider).deleteToken();
      ref.invalidate(authGateProvider);
      ref.invalidate(authStateProvider);
      ref.invalidate(authRoleProvider);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    String roleDisplay = 'Gérant';
    Color roleColor = Colors.blue;
    if (_userRole == 'super_admin') {
      roleDisplay = 'Super Administrateur';
      roleColor = Colors.purple;
    } else if (_userRole == 'admin') {
      roleDisplay = 'Administrateur';
      roleColor = Colors.teal;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: roleColor.withValues(alpha: 0.15),
                    child: Text(
                      _userName != null && _userName!.isNotEmpty
                          ? _userName![0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: roleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _userName ?? 'Utilisateur',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _email ?? '',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Chip(
                    label: Text(
                      roleDisplay,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: roleColor,
                      ),
                    ),
                    backgroundColor: roleColor.withValues(alpha: 0.12),
                    side: BorderSide(color: roleColor.withValues(alpha: 0.25)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // État et contrôle de synchronisation
          Card(
            color: Colors.teal.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.teal.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        SyncService.offlineMode ? Icons.offline_pin_outlined : Icons.sync_outlined,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          SyncService.offlineMode
                              ? 'Mode Hors-ligne (Base locale Isar)'
                              : 'Synchronisation En ligne active',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vos données sont sécurisées localement. Vous pouvez synchroniser votre compte, produits et utilisateurs avec le serveur central d\'un simple clic.',
                    style: TextStyle(fontSize: 13, color: Colors.teal.shade900),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade800,
                    ),
                    onPressed: _syncing ? null : _syncProfile,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: Text(_syncing ? 'Synchronisation en cours…' : 'Synchroniser mes données'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.security_outlined),
                  title: Text('Mode d\'authentification'),
                  subtitle: Text('Hybride (Local hors-ligne & Serveur Sanctum)'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Modifier mon mot de passe'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    isDark ? Icons.dark_mode : Icons.light_mode,
                    color: isDark ? Colors.amber : Colors.teal,
                  ),
                  title: const Text('Mode Sombre'),
                  subtitle: Text(
                    isDark
                        ? 'Actuellement en thème sombre'
                        : 'Actuellement en thème clair',
                  ),
                  value: isDark,
                  onChanged: (_) {
                    ref.read(themeModeProvider.notifier).toggleTheme();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}
