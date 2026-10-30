import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../core/database/collections/app_user.dart';
import '../../../core/database/collections/product.dart';
import '../../../core/database/isar_provider.dart';
import '../../../core/utils/error_handler.dart';
import '../../sync/providers/sync_poviders.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final storage = ref.read(secureStorageProvider);
    final localAuth = ref.read(localAuthServiceProvider);
    final isar = ref.read(isarProvider);
    final authService = ref.read(authServiceProvider);

    // 1. Tenter la connexion en ligne au serveur central d'abord
    bool serverSuccess = false;
    try {
      await authService.login(
        email: email,
        password: password,
        deviceName: 'CodeBar Manager Client',
      );
      serverSuccess = true;

      // Mettre à jour / insérer l'utilisateur dans Isar localement avec syncStatus synced
      final role = await storage.getRole() ?? 'manager';
      final name = await storage.getUserName() ?? 'Utilisateur';
      final savedEmail = await storage.getUserEmail() ?? email;

      final existing = await isar.appUsers
          .filter()
          .emailEqualTo(savedEmail, caseSensitive: false)
          .findFirst();

      if (existing != null) {
        final updated = existing.copyWith(
          name: name,
          role: role,
          password: password,
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime.now(),
        );
        await isar.writeTxn(() => isar.appUsers.put(updated));
      } else {
        final newUser = AppUser.create(
          uuid: 'srv-$savedEmail',
          email: savedEmail,
          name: name,
          role: role,
          password: password,
          syncStatus: SyncStatus.synced,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await isar.writeTxn(() => isar.appUsers.put(newUser));
      }

      if (role == 'super_admin') {
        await localAuth.savePlainPassword(password);
        if (!await localAuth.isSetup()) {
          await localAuth.setup(savedEmail, password);
        }
      }

      ref.invalidate(authGateProvider);
      ref.invalidate(authStateProvider);
      ref.invalidate(authRoleProvider);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        setState(() {
          _error = 'Délai de connexion dépassé (20s max). Le serveur a mis trop de temps à répondre. Veuillez relancer la reconnexion.';
        });
        return;
      }
      // Si refus explicite par le serveur (identifiants invalides ou compte désactivé)
      if (e.response?.statusCode == 422 || e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        final data = e.response?.data;
        if (data is Map && data['errors'] is Map) {
          final errors = data['errors'] as Map;
          if (errors.containsKey('email')) {
            final emailErrors = errors['email'];
            final msg = emailErrors is List && emailErrors.isNotEmpty
                ? emailErrors.first.toString()
                : emailErrors.toString();
            setState(() => _error = msg);
            return;
          }
        }
        final msg = (data is Map && data['message'] != null)
            ? data['message'].toString()
            : 'Identifiants incorrects.';
        setState(() => _error = msg);
        return;
      }
      // Si erreur de connexion (serveur non joignable, hors-ligne), on passe au repli local
    } catch (_) {
      // Repli local
    }

    // 2. Repli local résilient (Offline-first fallback)
    try {
      // Recherche parmi les utilisateurs enregistrés en base locale (Isar)
      final appUser = await isar.appUsers
          .filter()
          .emailEqualTo(email, caseSensitive: false)
          .findFirst();

      if (appUser != null) {
        if (!appUser.isActive) {
          setState(() {
            _error = 'Ce compte utilisateur a été désactivé.';
          });
          return;
        }

        bool isValid = false;
        if (appUser.role == 'super_admin') {
          isValid = (await localAuth.verify(email, password)) ||
              (appUser.password != null && appUser.password == password);
        } else {
          isValid = appUser.password != null && appUser.password == password;
        }

        if (isValid) {
          await storage.saveAuthMode('local');
          await storage.saveUser(
            role: appUser.role,
            name: appUser.name,
            email: appUser.email,
          );
          if (appUser.role == 'super_admin') {
            await localAuth.savePlainPassword(password);
          }
          ref.invalidate(authGateProvider);
          ref.invalidate(authStateProvider);
          ref.invalidate(authRoleProvider);
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          return;
        } else {
          setState(() {
            _error = 'Mot de passe incorrect. Vérifiez votre saisie.';
          });
          return;
        }
      }

      final localAdminEmail = await localAuth.getEmail();
      if (localAdminEmail != null &&
          localAdminEmail.toLowerCase() == email.toLowerCase()) {
        final isValidLocal = await localAuth.verify(email, password);
        if (isValidLocal) {
          await storage.saveAuthMode('local');
          await storage.saveUser(
            role: 'super_admin',
            name: 'Super Admin',
            email: email,
          );
          await localAuth.savePlainPassword(password);
          ref.invalidate(authGateProvider);
          ref.invalidate(authStateProvider);
          ref.invalidate(authRoleProvider);
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          return;
        }
      }

      if (!serverSuccess) {
        setState(() {
          _error = 'Identifiants introuvables sur le serveur et en local. Vérifiez vos identifiants.';
        });
      }
    } catch (e) {
      setState(() {
        _error = AppErrorHandler.friendly(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResetDialog() async {
    final resetEmailCtrl = TextEditingController(text: _emailController.text.trim());

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entrez l\'adresse email du compte à réinitialiser.\n'
              'Le mot de passe sera temporairement réinitialisé à "0000".',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Adresse Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final targetEmail = resetEmailCtrl.text.trim();
              if (targetEmail.isEmpty) return;
              Navigator.pop(ctx);

              final isar = ref.read(isarProvider);
              final user = await isar.appUsers
                  .filter()
                  .emailEqualTo(targetEmail, caseSensitive: false)
                  .findFirst();

              if (user != null) {
                final updated = user.copyWith(
                  password: '0000',
                  updatedAt: DateTime.now(),
                );
                await isar.writeTxn(() => isar.appUsers.put(updated));
                if (user.role == 'super_admin') {
                  final localAuth = ref.read(localAuthServiceProvider);
                  await localAuth.changePassword('0000');
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Mot de passe de $targetEmail réinitialisé à "0000". Connectez-vous avec ce code.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Aucun compte local trouvé pour $targetEmail. Connectez-vous en ligne si disponible.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_person_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CodeBar Manager',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connexion En ligne & Hors-ligne',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Adresse Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email requis';
                      if (!v.contains('@')) return 'Format email invalide';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _busy ? null : _login(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
                  ),
                  // Lien "Mot de passe oublié"
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showResetDialog,
                      child: const Text('Mot de passe oublié ?'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: Colors.orange.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(_busy ? 'Connexion en cours…' : 'Se connecter'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    color: Colors.blueGrey.shade50,
                    elevation: 0,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.sync_alt_outlined,
                              color: Colors.teal, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '💡 En ligne & Hors-ligne : Connexion automatique au serveur central si accessible, avec repli instantané sur la base locale en cas d\'absence de réseau.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.blueGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
