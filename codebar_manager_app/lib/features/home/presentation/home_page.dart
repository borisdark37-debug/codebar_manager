import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_provider.dart';
import '../../admin/presentation/activity_logs_page.dart';
import '../../admin/presentation/user_list_page.dart';
import '../../info/presentation/about_page.dart';
import '../../info/presentation/faq_page.dart';
import '../../info/presentation/terms_page.dart';
import '../../products/presentation/product_list_page.dart';
import '../../products/presentation/trash_page.dart';
import '../../products/providers/product_provider.dart';
import '../../profile/presentation/profile_page.dart';
import '../../scan/presentation/scan_page.dart';
import '../../sync/presentation/sync_page.dart';
import '../../sync/providers/sync_poviders.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoSyncProvider);
    final products = ref.watch(productsStreamProvider);
    final trashed = ref.watch(trashedProductsStreamProvider);
    final role = ref.watch(authRoleProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    String roleDisplay = 'Invité';
    if (role.valueOrNull == 'super_admin') {
      roleDisplay = 'Super Admin';
    } else if (role.valueOrNull == 'admin') {
      roleDisplay = 'Admin';
    } else if (role.valueOrNull == 'manager') {
      roleDisplay = 'Gérant';
    }

    final trashedCount = trashed.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeBar Manager'),
        actions: [
          // Bouton bascule Mode Sombre / Mode Clair
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? Colors.amber : null,
            ),
            tooltip: isDark ? 'Passer au mode clair' : 'Passer au mode sombre',
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggleTheme();
            },
          ),
          // Bouton Profil
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Mon Profil',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Menu',
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()));
                  break;
                case 'about':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutPage()));
                  break;
                case 'terms':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TermsPage()));
                  break;
                case 'faq':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FaqPage()));
                  break;
                case 'logout':
                  _logout(context, ref);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Mon Profil'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('À propos'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'faq',
                child: ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('FAQ'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'terms',
                child: ListTile(
                  leading: Icon(Icons.article_outlined),
                  title: Text('Conditions d\'utilisation'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Déconnexion',
                      style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(productsStreamProvider),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 42,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        Chip(
                          label: Text(
                            roleDisplay,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bienvenue',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Gérez vos produits et utilisateurs en toute autonomie en mode hors-ligne.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    icon: Icons.inventory_2_outlined,
                    label: 'Produits',
                    value: products.when(
                      data: (items) => items.length.toString(),
                      loading: () => '0',
                      error: (_, _) => '0',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    icon: Icons.sync,
                    label: 'Synchro',
                    value: 'Active',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoCard(
                    icon: Icons.delete_outline,
                    label: 'Corbeille',
                    value: trashedCount.toString(),
                    iconColor: trashedCount > 0 ? Colors.orange : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _ActionTile(
              icon: Icons.inventory_2_outlined,
              title: 'Gérer les produits',
              subtitle: 'Créer, rechercher et modifier vos produits',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProductListPage()),
              ),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.qr_code_scanner,
              title: 'Scanner un code',
              subtitle:
                  'Scanner un code-barres ou QR code pour voir les infos produit',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanPage()),
              ),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.sync,
              title: 'Synchronisation',
              subtitle: 'Push Outbox, Pull Delta & statut serveur',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SyncPage()),
              ),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.delete_sweep_outlined,
              title: 'Corbeille',
              subtitle: 'Voir, restaurer ou supprimer définitivement les produits',
              badge: trashedCount > 0 ? trashedCount.toString() : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrashPage()),
              ),
            ),
            if (role.valueOrNull == 'super_admin' ||
                role.valueOrNull == 'admin') ...[
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.group_outlined,
                title: 'Liste des utilisateurs',
                subtitle:
                    'Consulter et gérer les utilisateurs en mode local',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserListPage()),
                ),
              ),
            ],
            if (role.valueOrNull == 'super_admin') ...[
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.receipt_long_outlined,
                title: 'Journal d\'activité',
                subtitle:
                    'Consulter les connexions et opérations effectuées',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ActivityLogsPage()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ref.read(syncServiceProvider).stopAutoSync();
      await ref.read(secureStorageProvider).deleteToken();
      ref.invalidate(authGateProvider);
      ref.invalidate(authStateProvider);
      ref.invalidate(authRoleProvider);
    }
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon,
                  color: iconColor ?? Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(icon),
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        ),
      );
}
