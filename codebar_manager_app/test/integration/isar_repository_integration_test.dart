import 'dart:io';
import 'package:codebar_manager_app/core/database/collections/app_sequence.dart';
import 'package:codebar_manager_app/core/database/collections/app_user.dart';
import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:codebar_manager_app/core/database/collections/sync_mutation.dart';
import 'package:codebar_manager_app/core/services/api_client.dart';
import 'package:codebar_manager_app/core/services/product_repository.dart';
import 'package:codebar_manager_app/core/services/secure_stokage_service.dart';
import 'package:codebar_manager_app/core/services/user_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

class MockSecureStorage extends Fake implements SecureStorageService {
  final Map<String, String> _storage = {};
  @override
  Future<void> saveToken(String token) async => _storage['token'] = token;
  @override
  Future<String?> getToken() async => _storage['token'];
  @override
  Future<bool> hasToken() async => _storage.containsKey('token');
  @override
  Future<String?> getUserEmail() async => _storage['user_email'];
  @override
  Future<String?> getUserName() async => _storage['user_name'];
  @override
  Future<void> saveUser({required String role, required String name, String? email}) async {
    _storage['role'] = role;
    _storage['user_name'] = name;
    if (email != null) _storage['user_email'] = email;
  }
}

class MockApiClient extends Fake implements ApiClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'read') return 'mock_password';
    if (methodCall.method == 'write') return true;
    return null;
  });

  late Directory tempDir;
  late Isar isar;
  late ProductRepository productRepo;
  late UserRepository userRepo;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: false);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_repo_test_');
    isar = await Isar.open(
      [ProductSchema, AppSequenceSchema, AppUserSchema, SyncMutationSchema],
      directory: tempDir.path,
      name: 'repo_test_db_${DateTime.now().microsecondsSinceEpoch}',
    );
    productRepo = ProductRepository(isar);
    userRepo = UserRepository(isar, MockApiClient(), MockSecureStorage());
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Isar Repository Integration Tests', () {
    test('ProductRepository.create persists product, increments sequence and logs Outbox mutation', () async {
      // 1. Premier produit créé
      final p1 = await productRepo.create(
        name: 'Huile Essentielle Lavande',
        format: '30ml',
        containment: 'Flacon verre ambré',
        price: 18.50,
        quantity: 25,
      );

      expect(p1.internalCode, 'CAP-0001');
      expect(p1.syncStatus, SyncStatus.pending);

      // Vérification Isar
      final retrievedP1 = await isar.products.filter().uuidEqualTo(p1.uuid).findFirst();
      expect(retrievedP1, isNotNull);
      expect(retrievedP1?.name, 'Huile Essentielle Lavande');

      // Vérification Outbox
      final mutations = await isar.syncMutations.filter().entityIdEqualTo(p1.uuid).findAll();
      expect(mutations.length, 1);
      expect(mutations.first.action, MutationAction.create);
      expect(mutations.first.status, MutationStatus.pending);

      // 2. Deuxième produit créé -> doit impérativement incrémenter à CAP-0002
      final p2 = await productRepo.create(
        name: 'Eau Florale Rose',
        format: '200ml',
        containment: 'Spray',
        price: 12.00,
        quantity: 10,
      );

      expect(p2.internalCode, 'CAP-0002');

      final seq = await isar.appSequences.get(0);
      expect(seq?.lastProductNumber, 2);
    });

    test('ProductRepository update, softDelete, restore and deletePermanently update Outbox and store', () async {
      final p = await productRepo.create(
        name: 'Crème Mains',
        format: '75ml',
        containment: 'Tube',
        price: 9.00,
        quantity: 30,
      );

      // Update
      final updated = await productRepo.update(
        p,
        name: 'Crème Mains Karité',
        format: '75ml',
        containment: 'Tube',
        price: 10.50,
        quantity: 28,
      );
      expect(updated.name, 'Crème Mains Karité');
      expect(updated.price, 10.50);

      var updateMuts = await isar.syncMutations
          .filter()
          .entityIdEqualTo(p.uuid)
          .and()
          .actionEqualTo(MutationAction.update)
          .findAll();
      expect(updateMuts.length, 1);

      // Soft Delete
      await productRepo.softDelete(updated);
      final softDeleted = await isar.products.filter().uuidEqualTo(p.uuid).findFirst();
      expect(softDeleted?.deletedAt, isNotNull);

      var delMuts = await isar.syncMutations
          .filter()
          .entityIdEqualTo(p.uuid)
          .and()
          .actionEqualTo(MutationAction.delete)
          .findAll();
      expect(delMuts.length, 1);

      // Restore
      await productRepo.restore(softDeleted!);
      final restored = await isar.products.filter().uuidEqualTo(p.uuid).findFirst();
      expect(restored?.deletedAt, isNull);

      // Permanent Delete
      await productRepo.deletePermanently(restored!);
      final permanentlyDeleted = await isar.products.filter().uuidEqualTo(p.uuid).findFirst();
      expect(permanentlyDeleted, isNull);

      var permMuts = await isar.syncMutations
          .filter()
          .entityIdEqualTo(p.uuid)
          .and()
          .actionEqualTo(MutationAction.permanentDelete)
          .findAll();
      expect(permMuts.length, 1);
    });

    test('UserRepository.ensureSuperAdminExists creates Super Admin in Isar collection', () async {
      final superAdmin = await userRepo.ensureSuperAdminExists();
      expect(superAdmin, isNotNull);
      expect(superAdmin?.role, 'super_admin');
      expect(superAdmin?.isActive, isTrue);

      final inDb = await isar.appUsers.filter().roleEqualTo('super_admin').findFirst();
      expect(inDb, isNotNull);
      expect(inDb?.email, isNotEmpty);
    });
  });
}
