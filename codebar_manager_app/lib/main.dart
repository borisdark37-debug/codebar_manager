import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/database/isar_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (e) {
    debugPrint('Supabase initialisation warning: $e');
  }

  final isar = await openIsar();
  runApp(
    ProviderScope(
      overrides: [isarProvider.overrideWithValue(isar)],
      child: const CodeBarApp(),
    ),
  );
}
