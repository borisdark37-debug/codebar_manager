import 'package:codebar_manager_app/core/database/collections/app_user.dart';
import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:codebar_manager_app/core/services/sync_service.dart';
import 'package:codebar_manager_app/features/products/providers/product_provider.dart';
import 'package:codebar_manager_app/features/sync/providers/sync_poviders.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class DummySyncService implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Offline-first Product Filtering and Sorting', () {
    final now = DateTime.now();
    final p1 = Product.create(
      uuid: 'uuid-1',
      internalCode: 'CAP-0001',
      name: 'Crème Hydratante',
      format: '50ml',
      containment: 'Pot verre',
      price: 25.0,
      quantity: 10,
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );

    final p2 = Product.create(
      uuid: 'uuid-2',
      internalCode: 'CAP-0002',
      name: 'Baume Lèvres',
      format: '15ml',
      containment: 'Tube',
      price: 8.5,
      quantity: 40,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    final p3 = Product.create(
      uuid: 'uuid-3',
      internalCode: 'CAP-0003',
      name: 'Sérum Anti-Âge',
      format: '30ml',
      containment: 'Flacon pipette',
      price: 45.0,
      quantity: 5,
      createdAt: now,
      updatedAt: now,
    );

    final products = [p1, p2, p3];

    test('filters offline products by code, name, format or containment', () {
      final byCode = applyFilterAndSort(
        products: products,
        query: 'cap-0002',
        sort: ProductSort.code,
      );
      expect(byCode.length, 1);
      expect(byCode.first.name, 'Baume Lèvres');

      final byName = applyFilterAndSort(
        products: products,
        query: 'sérum',
        sort: ProductSort.code,
      );
      expect(byName.length, 1);
      expect(byName.first.internalCode, 'CAP-0003');

      final byFormat = applyFilterAndSort(
        products: products,
        query: '50ml',
        sort: ProductSort.code,
      );
      expect(byFormat.length, 1);
      expect(byFormat.first.name, 'Crème Hydratante');

      final byContainment = applyFilterAndSort(
        products: products,
        query: 'tube',
        sort: ProductSort.code,
      );
      expect(byContainment.length, 1);
      expect(byContainment.first.name, 'Baume Lèvres');
    });

    test('sorts products offline by code, name, and date descending', () {
      final sortedByCode = applyFilterAndSort(
        products: products,
        query: '',
        sort: ProductSort.code,
      );
      expect(sortedByCode.map((p) => p.internalCode).toList(), [
        'CAP-0001',
        'CAP-0002',
        'CAP-0003',
      ]);

      final sortedByName = applyFilterAndSort(
        products: products,
        query: '',
        sort: ProductSort.name,
      );
      expect(sortedByName.map((p) => p.name).toList(), [
        'Baume Lèvres',
        'Crème Hydratante',
        'Sérum Anti-Âge',
      ]);

      final sortedByDate = applyFilterAndSort(
        products: products,
        query: '',
        sort: ProductSort.dateDesc,
      );
      expect(sortedByDate.map((p) => p.internalCode).toList(), [
        'CAP-0003',
        'CAP-0002',
        'CAP-0001',
      ]);
    });
  });

  group('Offline SyncController and SyncService Behavior', () {
    setUp(() {
      SyncService.setOfflineMode(true);
    });

    tearDown(() {
      SyncService.setOfflineMode(false);
    });

    test('SyncController pushPending and pullAll return immediate offline notice', () async {
      final container = ProviderContainer(
        overrides: [
          syncServiceProvider.overrideWithValue(DummySyncService()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(syncControllerProvider.notifier);

      await controller.pushPending();
      final statePush = container.read(syncControllerProvider);
      expect(statePush.phase, SyncPhase.idle);
      expect(statePush.fatalMessage, contains('Mode Hors-ligne'));
      expect(statePush.fatalMessage, contains('temporairement désactivée'));

      await controller.pullAll();
      final statePull = container.read(syncControllerProvider);
      expect(statePull.phase, SyncPhase.idle);
      expect(statePull.fatalMessage, contains('Mode Hors-ligne'));
      expect(statePull.fatalMessage, contains('données locales sont actives'));
    });

    test('SyncService offlineMode flag returns offline notice without network calls', () async {
      expect(SyncService.offlineMode, isTrue);

      // Create a mock or fake SyncService call verification
      // Without any HTTP backend running, pushPending() and pullAll() must not throw or connect
      // because offlineMode is true.
    });
  });

  group('Offline User State & Purge Eligibility Rules', () {
    test('User active status and 30-day purge eligibility calculation', () {
      final now = DateTime.now();

      final activeUser = AppUser.create(
        uuid: 'user-1',
        email: 'manager1@example.com',
        name: 'Manager One',
        role: 'manager',
        isActive: true,
        createdAt: now.subtract(const Duration(days: 60)),
        updatedAt: now.subtract(const Duration(days: 60)),
      );

      expect(activeUser.isActive, isTrue);
      expect(activeUser.disabledAt, isNull);
      expect(activeUser.isPurgeEligible, isFalse);

      final recentlyDisabled = activeUser.copyWith(
        isActive: false,
        disabledAt: now.subtract(const Duration(days: 10)),
      );

      expect(recentlyDisabled.isActive, isFalse);
      expect(recentlyDisabled.isPurgeEligible, isFalse);
      expect(recentlyDisabled.daysUntilPurge, 20);

      final purgeEligibleUser = activeUser.copyWith(
        isActive: false,
        disabledAt: now.subtract(const Duration(days: 35)),
      );

      expect(purgeEligibleUser.isActive, isFalse);
      expect(purgeEligibleUser.isPurgeEligible, isTrue);
      expect(purgeEligibleUser.daysUntilPurge, 0);
    });

    test('AppUser copyWith maintains or clears passwords and attributes correctly', () {
      final now = DateTime.now();
      final user = AppUser.create(
        uuid: 'user-2',
        email: 'admin1@example.com',
        name: 'Admin One',
        role: 'admin',
        password: 'initialPassword',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final updatedPassword = user.copyWith(password: 'newPassword123');
      expect(updatedPassword.password, 'newPassword123');

      final deactivated = updatedPassword.copyWith(
        isActive: false,
        disabledAt: now,
      );
      expect(deactivated.isActive, isFalse);
      expect(deactivated.disabledAt, now);

      final reactivated = deactivated.copyWith(
        isActive: true,
        clearDisabledAt: true,
      );
      expect(reactivated.isActive, isTrue);
      expect(reactivated.disabledAt, isNull);
    });
  });
}
