/// Hachage FNV-1a 64 bits, recommandé par l'auteur d'Isar
/// pour transformer un UUID (String) en Id (int64).
///
/// Retourne toujours une valeur non nulle.
int fastHash(String string) {
  var hash = 0xcbf29ce484222325;
  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }
  // Isar réserve 0 pour "non défini" : on évite ce cas.
  return hash == 0 ? 1 : hash;
}
