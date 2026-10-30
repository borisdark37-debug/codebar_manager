import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/collections/app_user.dart';
import '../../../core/database/collections/product.dart';
import '../../../core/utils/error_handler.dart';
import '../providers/user_providers.dart';
import 'user_detail_page.dart';
import 'user_management_page.dart';

class UserListPage extends ConsumerStatefulWidget {
  const UserListPage({super.key});

  @override
  ConsumerState<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends ConsumerState<UserListPage> {
  String _search = '';
  bool _isSyncingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(userRepositoryProvider).ensureSuperAdminExists();
    });
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncingAll = true);
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final count = await userRepo.syncAllPending();
      await userRepo.fetchAndMergeServerUsers();
      ref.invalidate(usersStreamProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? '$count utilisateur(s) synchronisé(s) vers le serveur.'
                  : 'Tous les utilisateurs sont synchronisés avec le serveur.',
            ),
            backgroundColor: Colors.teal,
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
      if (mounted) setState(() => _isSyncingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilisateurs'),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _isSyncingAll ? null : _syncAll,
            icon: _isSyncingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(
              _isSyncingAll ? 'Synchronisation…' : 'Tout synchroniser',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un utilisateur (nom, email, rôle)…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erreur : $e', style: const TextStyle(color: Colors.red)),
                ),
              ),
              data: (users) {
                final filtered = users.where((u) {
                  if (_search.isEmpty) return true;
                  return u.name.toLowerCase().contains(_search) ||
                      u.email.toLowerCase().contains(_search) ||
                      u.role.toLowerCase().contains(_search);
                }).toList();

                filtered.sort((a, b) {
                  int rank(String role) {
                    if (role == 'super_admin') return 0;
                    if (role == 'admin') return 1;
                    return 2;
                  }
                  final ra = rank(a.role);
                  final rb = rank(b.role);
                  if (ra != rb) return ra.compareTo(rb);
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          _search.isEmpty
                              ? 'Aucun utilisateur enregistré'
                              : 'Aucun utilisateur correspondant',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(userRepositoryProvider).fetchAndMergeServerUsers();
                    ref.invalidate(usersStreamProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) => _UserTile(user: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserManagementPage()),
        ),
        icon: const Icon(Icons.person_add),
        label: const Text('Nouvel utilisateur'),
      ),
    );
  }
}

class _UserTile extends ConsumerStatefulWidget {
  final AppUser user;
  const _UserTile({required this.user});

  @override
  ConsumerState<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends ConsumerState<_UserTile> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final ok = await ref.read(userRepositoryProvider).syncUser(widget.user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? '${widget.user.name} a été synchronisé avec le serveur.'
                  : 'Échec de la synchronisation.',
            ),
            backgroundColor: ok ? Colors.teal : Colors.orange.shade800,
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

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final isSuperAdmin = u.role == 'super_admin';

    Color roleColor = Colors.blue;
    String roleLabel = 'Gérant';
    if (u.role == 'super_admin') {
      roleColor = Colors.purple;
      roleLabel = 'Super Admin';
    } else if (u.role == 'admin') {
      roleColor = Colors.teal;
      roleLabel = 'Admin';
    }

    final isSynced = u.syncStatus == SyncStatus.synced;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Text(
              u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
              style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSynced
                    ? Colors.green
                    : (u.syncStatus == SyncStatus.error ? Colors.red : Colors.orange),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              u.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: u.isActive ? null : TextDecoration.lineThrough,
                color: u.isActive ? null : Colors.grey,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              roleLabel,
              style: TextStyle(fontSize: 10, color: roleColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u.email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                isSynced ? '✓ Synchronisé' : '⏳ En attente de synchronisation',
                style: TextStyle(
                  fontSize: 11,
                  color: isSynced ? Colors.green : Colors.orange.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!isSuperAdmin && u.createdBy != null) ...[
                const Text(' • ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  'Ajouté par ${u.createdBy}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSynced)
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 20, color: Colors.teal),
              tooltip: 'Synchroniser cet utilisateur vers le serveur',
              onPressed: _syncing ? null : _sync,
            ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UserDetailPage(user: u)),
        );
      },
    );
  }
}
