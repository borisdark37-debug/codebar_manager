import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/collections/app_user.dart';
import '../../../core/database/isar_provider.dart';
import '../../../core/services/user_repository.dart';
import '../../sync/providers/sync_poviders.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(
    ref.watch(isarProvider),
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
  );
});

final usersStreamProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(userRepositoryProvider).watchAll();
});

final pendingUsersCountStreamProvider = StreamProvider<int>((ref) {
  return ref.watch(userRepositoryProvider).watchPendingCount();
});
