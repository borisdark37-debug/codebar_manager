import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sync/providers/sync_poviders.dart';
import 'activity_log_detail_page.dart';

class ActivityLogsPage extends ConsumerStatefulWidget {
  const ActivityLogsPage({super.key});

  @override
  ConsumerState<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends ConsumerState<ActivityLogsPage> {
  final List<Map<String, dynamic>> _logs = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _currentPage = 1;
  int _lastPage = 1;
  String _selectedCategory = 'all'; // 'all', 'auth', 'product', 'user'
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLogs(page: 1);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs({int page = 1, bool isRefresh = false}) async {
    if (page == 1 && !isRefresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (page > 1) {
      setState(() => _loadingMore = true);
    }

    try {
      final syncService = ref.read(syncServiceProvider);
      // Réconciliation du token Sanctum du Super Admin si nécessaire
      await syncService.reconcileSuperAdmin();

      final client = ref.read(apiClientProvider);
      final response = await client.get<Map<String, dynamic>>(
        '/activity-logs',
        queryParameters: {
          'page': page,
          'per_page': 25,
        },
      );

      final data = response.data;
      final rawList = (data?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final lastPage = (data?['last_page'] as num?)?.toInt() ?? 1;

      if (mounted) {
        setState(() {
          if (page == 1) {
            _logs.clear();
          }
          _logs.addAll(rawList);
          _currentPage = page;
          _lastPage = lastPage;
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        String msg;
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          msg = 'Délai d\'attente dépassé (30s). Le serveur met trop de temps à répondre.';
        } else if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          msg = 'Accès restreint : Seul le Super Administrateur peut consulter le journal d\'activité centralisé.';
        } else {
          msg = 'Impossible de se connecter au serveur : ${e.message ?? e.toString()}';
        }
        setState(() {
          _error = msg;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger le journal d\'activité : $e';
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    return _logs.where((log) {
      final action = log['action']?.toString() ?? '';
      final user = log['user'] as Map<String, dynamic>?;
      final userName = user?['name']?.toString().toLowerCase() ?? '';
      final userEmail = user?['email']?.toString().toLowerCase() ?? '';
      final metadataStr = log['metadata']?.toString().toLowerCase() ?? '';

      // Filtre de catégorie
      if (_selectedCategory == 'auth' && !action.startsWith('auth.')) {
        return false;
      }
      if (_selectedCategory == 'product' && !action.startsWith('product.')) {
        return false;
      }
      if (_selectedCategory == 'user' && !action.startsWith('user.')) {
        return false;
      }

      // Filtre de recherche
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesAction = action.toLowerCase().contains(q);
        final matchesUser = userName.contains(q) || userEmail.contains(q);
        final matchesMeta = metadataStr.contains(q);
        return matchesAction || matchesUser || matchesMeta;
      }

      return true;
    }).toList();
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

  String _formatActionTitle(String? action) {
    switch (action) {
      case 'auth.login':
        return 'Connexion';
      case 'product.created':
        return 'Produit créé';
      case 'product.updated':
        return 'Produit modifié';
      case 'product.deleted':
        return 'Produit supprimé';
      case 'user.created':
        return 'Utilisateur créé';
      default:
        return action ?? 'Activité';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d’activité'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () => _loadLogs(page: 1, isRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher par action, utilisateur, code...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),

          // Chips de filtres par catégorie
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('all', 'Tous'),
                const SizedBox(width: 8),
                _buildFilterChip('auth', 'Connexions'),
                const SizedBox(width: 8),
                _buildFilterChip('product', 'Produits'),
                const SizedBox(width: 8),
                _buildFilterChip('user', 'Utilisateurs'),
              ],
            ),
          ),

          const Divider(height: 1),

          // Liste des logs
          Expanded(
            child: Builder(
              builder: (context) {
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_error != null) {
                  final isOffline = _error!.contains('Hors-ligne');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isOffline ? Icons.cloud_off_rounded : Icons.error_outline,
                            size: 56,
                            color: isOffline ? Theme.of(context).colorScheme.primary : Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.tonalIcon(
                            onPressed: () => _loadLogs(page: 1),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Actualiser'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucune activité trouvée',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Les opérations effectuées sur l\'application apparaîtront ici.',
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => _loadLogs(page: 1, isRefresh: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length + (_currentPage < _lastPage ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton.icon(
                                    onPressed: () =>
                                        _loadLogs(page: _currentPage + 1),
                                    icon: const Icon(Icons.expand_more),
                                    label: const Text('Charger plus de logs'),
                                  ),
                          ),
                        );
                      }

                      final log = filtered[index];
                      final action = log['action']?.toString();
                      final user = log['user'] as Map<String, dynamic>?;
                      final userName = user?['name'] ?? 'Système';
                      final createdAt = log['created_at']?.toString() ?? '';
                      final color = _actionColor(action);

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(_actionIcon(action), color: color, size: 22),
                          ),
                          title: Text(
                            _formatActionTitle(action),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Par : $userName'),
                              Text(
                                createdAt,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Colors.grey,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ActivityLogDetailPage(log: log),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String category, String label) {
    final isSelected = _selectedCategory == category;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (_) {
        setState(() => _selectedCategory = category);
      },
    );
  }
}
