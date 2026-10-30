import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/home_page.dart';
import '../../sync/providers/sync_poviders.dart';
import 'login_page.dart';
import 'setup_super_admin_page.dart';

/// Point d'entrée sous MaterialApp qui détermine quelle vue afficher :
/// - SetupSuperAdminPage si l'appareil n'a pas encore de compte local super_admin
/// - LoginPage si l'utilisateur n'est pas encore connecté
/// - HomePage si l'utilisateur est authentifié (en local ou via serveur)
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateState = ref.watch(authGateProvider);

    return gateState.when(
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, stack) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Erreur d\'initialisation : $e',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(authGateProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (state) {
        switch (state) {
          case AuthGateState.needsSetup:
            return const SetupSuperAdminPage();
          case AuthGateState.needsLogin:
            return const LoginPage();
          case AuthGateState.authenticated:
            return const HomePage();
        }
      },
    );
  }
}
