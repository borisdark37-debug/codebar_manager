import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'collections/app_sequence.dart';
import 'collections/app_user.dart';
import 'collections/product.dart';
import 'collections/sync_mutation.dart';

/// Provider global d'accès à Isar. Doit être surchargé au démarrage
/// de l'application (voir main.dart).
final isarProvider = Provider<Isar>(
  (ref) => throw UnimplementedError(
    'isarProvider doit être overridé dans ProviderScope',
  ),
);

/// Ouvre la base Isar avec les collections déclarées.
Future<Isar> openIsar() async {
  final dir = await getApplicationDocumentsDirectory();
  return Isar.open(
    [ProductSchema, AppSequenceSchema, AppUserSchema, SyncMutationSchema],
    directory: dir.path,
    inspector: true,
  );
}
