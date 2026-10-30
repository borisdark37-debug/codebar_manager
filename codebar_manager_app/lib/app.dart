import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/notification_service.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/auth_gate.dart';

class CodeBarApp extends ConsumerStatefulWidget {
  const CodeBarApp({super.key});

  @override
  ConsumerState<CodeBarApp> createState() => _CodeBarAppState();
}

class _CodeBarAppState extends ConsumerState<CodeBarApp> {
  final NotificationService _notifications = NotificationService();

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final ok = await _notifications.init();
    if (!ok) {
      if (kDebugMode) {
        debugPrint('Notifications indisponibles.');
      }
      return;
    }

    // En Mode Hors-ligne : aucune alerte sonore de synchronisation serveur distante.
    // Arrêt de toute alerte persistante qui aurait pu être planifiée antérieurement.
    await _notifications.stopSyncAlert();
  }

  @override
  Widget build(BuildContext context) {
    final currentThemeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'CodeBar Manager',
      debugShowCheckedModeBanner: false,
      themeMode: currentThemeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F8C),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F9),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFF087F8C), width: 2),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F8C),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E252B),
        ),
        scaffoldBackgroundColor: const Color(0xFF12161A),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFF1E252B),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E252B),
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF263038),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFF087F8C), width: 2),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
