import 'package:isar/isar.dart';

part 'app_sequence.g.dart';

/// Compteur persistant + métadonnées globales de l'application.
/// Un seul enregistrement, identifié par l'id 0.
@collection
class AppSequence {
  Id id = 0;
  late int lastProductNumber;

  /// Date de la dernière synchronisation réussie (push ou pull).
  DateTime? lastSyncAt;

  late DateTime updatedAt;
}
