import 'package:isar/isar.dart';
import '../../utils/fast_hash.dart';

part 'product.g.dart';

/// Statut de synchronisation d'un produit vis-à-vis de PostgreSQL.
enum SyncStatus {
  pending, // Créé/modifié localement, non encore synchronisé
  synced, // Synchronisé avec succès
  error, // Erreur lors de la dernière tentative de sync
}

@collection
class Product {
  // Id Isar dérivé de l'UUID (contrainte Isar : Id = int64)
  Id get isarId => fastHash(uuid);

  @Index(unique: true, replace: true)
  late String uuid;

  /// Code interne, ex: "CAP-0001". Généré côté client.
  @Index(unique: true, replace: true)
  late String internalCode;

  late String name;
  late String format;
  late String containment;
  late double price;
  late int quantity;
  String? imageBase64;

  late DateTime createdAt;
  late DateTime updatedAt;

  @enumerated
  late SyncStatus syncStatus;

  DateTime? deletedAt; // Suppression logique

  Product();

  Product.create({
    required this.uuid,
    required this.internalCode,
    required this.name,
    required this.format,
    required this.containment,
    this.price = 0,
    this.quantity = 0,
    this.imageBase64,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  Product copyWith({
    String? internalCode,
    String? name,
    String? format,
    String? containment,
    double? price,
    int? quantity,
    String? imageBase64,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Product.create(
      uuid: uuid,
      internalCode: internalCode ?? this.internalCode,
      name: name ?? this.name,
      format: format ?? this.format,
      containment: containment ?? this.containment,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      imageBase64: imageBase64 ?? this.imageBase64,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  bool get isDeleted => deletedAt != null;
}
