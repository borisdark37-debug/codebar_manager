import 'package:codebar_manager_app/core/database/collections/app_user.dart';
import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUser Model Unit Tests', () {
    test('AppUser.create sets all properties properly', () {
      final now = DateTime.now();
      final user = AppUser.create(
        uuid: 'user-uuid-1',
        email: 'agent@example.com',
        name: 'Agent de Stock',
        role: 'manager',
        password: 'plain_password',
        createdBy: 'super_admin',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(user.uuid, 'user-uuid-1');
      expect(user.email, 'agent@example.com');
      expect(user.name, 'Agent de Stock');
      expect(user.role, 'manager');
      expect(user.password, 'plain_password');
      expect(user.createdBy, 'super_admin');
      expect(user.isActive, isTrue);
      expect(user.syncStatus, SyncStatus.pending);
      expect(user.disabledAt, isNull);
      expect(user.isPurgeEligible, isFalse);
      expect(user.daysUntilPurge, 30);
    });

    test('AppUser purge calculations for disabled users', () {
      final now = DateTime.now();
      // Désactivé il y a 35 jours -> éligible à la purge
      final oldDisabled = AppUser.create(
        uuid: 'old-disabled',
        email: 'old@example.com',
        name: 'Ancien Salarié',
        role: 'manager',
        isActive: false,
        disabledAt: now.subtract(const Duration(days: 35)),
        createdAt: now.subtract(const Duration(days: 100)),
        updatedAt: now.subtract(const Duration(days: 35)),
      );

      expect(oldDisabled.isPurgeEligible, isTrue);
      expect(oldDisabled.daysUntilPurge, 0);

      // Désactivé il y a 10 jours -> encore 20 jours avant la purge
      final recentDisabled = AppUser.create(
        uuid: 'recent-disabled',
        email: 'recent@example.com',
        name: 'Salarié Récent',
        role: 'manager',
        isActive: false,
        disabledAt: now.subtract(const Duration(days: 10)),
        createdAt: now.subtract(const Duration(days: 50)),
        updatedAt: now.subtract(const Duration(days: 10)),
      );

      expect(recentDisabled.isPurgeEligible, isFalse);
      expect(recentDisabled.daysUntilPurge, 20);
    });

    test('AppUser.copyWith modifies role, active state and resets disabledAt', () {
      final now = DateTime.now();
      final user = AppUser.create(
        uuid: 'user-uuid-2',
        email: 'admin@example.com',
        name: 'Admin Test',
        role: 'manager',
        isActive: false,
        disabledAt: now,
        createdAt: now,
        updatedAt: now,
      );

      final reActivated = user.copyWith(
        role: 'admin',
        isActive: true,
        clearDisabledAt: true,
      );

      expect(reActivated.role, 'admin');
      expect(reActivated.isActive, isTrue);
      expect(reActivated.disabledAt, isNull);
    });
  });
}
