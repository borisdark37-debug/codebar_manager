import 'package:isar/isar.dart';
import '../../utils/fast_hash.dart';
import 'product.dart'; // pour réutiliser SyncStatus

part 'app_user.g.dart';

@collection
class AppUser {
  Id get isarId => fastHash(uuid);

  @Index(unique: true, replace: true)
  late String uuid;

  @Index(unique: true, replace: true)
  late String email;

  late String name;
  late String role; // 'super_admin' | 'admin' | 'manager'

  /// Mot de passe (en clair pour transmission lors de la synchronisation serveur)
  String? password;

  @enumerated
  late SyncStatus syncStatus;

  /// Nom ou email de l'administrateur ayant créé l'utilisateur (null pour super_admin)
  String? createdBy;

  late bool isActive;
  DateTime? disabledAt;

  late DateTime createdAt;
  late DateTime updatedAt;

  AppUser();

  AppUser.create({
    required this.uuid,
    required this.email,
    required this.name,
    required this.role,
    this.password,
    this.syncStatus = SyncStatus.pending,
    this.createdBy,
    this.isActive = true,
    this.disabledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  AppUser copyWith({
    String? name,
    String? role,
    String? password,
    bool clearPassword = false,
    SyncStatus? syncStatus,
    String? createdBy,
    bool? isActive,
    DateTime? disabledAt,
    bool clearDisabledAt = false,
    DateTime? updatedAt,
  }) {
    return AppUser.create(
      uuid: uuid,
      email: email,
      name: name ?? this.name,
      role: role ?? this.role,
      password: clearPassword ? null : (password ?? this.password),
      syncStatus: syncStatus ?? this.syncStatus,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
      disabledAt: clearDisabledAt ? null : (disabledAt ?? this.disabledAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Indique si l'utilisateur est désactivé depuis au moins 30 jours
  bool get isPurgeEligible {
    if (isActive || disabledAt == null) return false;
    final days = DateTime.now().difference(disabledAt!).inDays;
    return days >= 30;
  }

  /// Jours restants avant l'éligibilité à la purge complète (30 jours)
  int get daysUntilPurge {
    if (isActive || disabledAt == null) return 30;
    final days = DateTime.now().difference(disabledAt!).inDays;
    return (30 - days).clamp(0, 30);
  }
}
