import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product Model Unit Tests', () {
    test('Product.create initializes all fields accurately', () {
      final now = DateTime.now();
      final product = Product.create(
        uuid: 'prod-uuid-1234',
        internalCode: 'CAP-0001',
        name: 'Huile d\'Argan Pure',
        format: '100ml',
        containment: 'Flacon verre',
        price: 29.90,
        quantity: 15,
        imageBase64: 'fake-base64',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      );

      expect(product.uuid, 'prod-uuid-1234');
      expect(product.internalCode, 'CAP-0001');
      expect(product.name, 'Huile d\'Argan Pure');
      expect(product.format, '100ml');
      expect(product.containment, 'Flacon verre');
      expect(product.price, 29.90);
      expect(product.quantity, 15);
      expect(product.imageBase64, 'fake-base64');
      expect(product.createdAt, now);
      expect(product.updatedAt, now);
      expect(product.syncStatus, SyncStatus.pending);
      expect(product.deletedAt, isNull);
    });

    test('Product.copyWith modifies specified fields and leaves others unchanged', () {
      final now = DateTime.now();
      final initial = Product.create(
        uuid: 'prod-uuid-1234',
        internalCode: 'CAP-0001',
        name: 'Savon Artisanal',
        format: '200g',
        containment: 'Pain',
        price: 5.50,
        quantity: 20,
        createdAt: now,
        updatedAt: now,
      );

      final modified = initial.copyWith(
        name: 'Savon Bio Amande',
        price: 6.50,
        quantity: 18,
        syncStatus: SyncStatus.synced,
      );

      expect(modified.uuid, 'prod-uuid-1234');
      expect(modified.internalCode, 'CAP-0001');
      expect(modified.name, 'Savon Bio Amande');
      expect(modified.format, '200g');
      expect(modified.price, 6.50);
      expect(modified.quantity, 18);
      expect(modified.syncStatus, SyncStatus.synced);
      expect(modified.deletedAt, isNull);
    });

    test('Product soft delete and clearDeletedAt behavior', () {
      final now = DateTime.now();
      final active = Product.create(
        uuid: 'prod-uuid-9999',
        internalCode: 'CAP-9999',
        name: 'Produit Test',
        format: '50ml',
        containment: 'Pot',
        createdAt: now,
        updatedAt: now,
      );

      final deleted = active.copyWith(deletedAt: now);
      expect(deleted.deletedAt, isNotNull);

      final restored = deleted.copyWith(clearDeletedAt: true);
      expect(restored.deletedAt, isNull);
    });
  });
}
