import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../database/collections/app_sequence.dart';

class CodeGeneratorService {
  final Isar _isar;
  static const _uuid = Uuid();

  CodeGeneratorService(this._isar);

  /// Génère un UUID v4 unique côté client.
  String generateUuid() => _uuid.v4();

  /// Réserve le prochain code interne au format CAP-XXXX.
  /// L'opération est atomique (transaction Isar), ce qui garantit
  /// qu'aucun doublon ne peut être créé sur le même appareil.
  Future<String> reserveNextInternalCode() async {
    return _isar.writeTxn(() async {
      var sequence = await _isar.appSequences.get(0);
      sequence ??= AppSequence()
        ..id = 0
        ..lastProductNumber = 0
        ..updatedAt = DateTime.now();
      sequence.lastProductNumber += 1;
      sequence.updatedAt = DateTime.now();
      await _isar.appSequences.put(sequence);
      return 'CAP-${sequence.lastProductNumber.toString().padLeft(4, '0')}';
    });
  }

  /// Lecture (non bloquante) du dernier numéro utilisé — utile pour l'affichage.
  Future<int> peekLastNumber() async {
    final seq = await _isar.appSequences.get(0);
    return seq?.lastProductNumber ?? 0;
  }
}
