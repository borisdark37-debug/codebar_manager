import 'dart:io';
import 'package:codebar_manager_app/core/database/collections/app_sequence.dart';
import 'package:codebar_manager_app/core/database/collections/app_user.dart';
import 'package:codebar_manager_app/core/database/collections/product.dart';
import 'package:codebar_manager_app/core/database/collections/sync_mutation.dart';
import 'package:codebar_manager_app/core/services/api_client.dart';
import 'package:codebar_manager_app/core/services/barcode_service_svg.dart';
import 'package:codebar_manager_app/core/services/code_generator_service.dart';
import 'package:codebar_manager_app/core/services/notification_service.dart';
import 'package:codebar_manager_app/core/services/sync_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

class RegressionApiClient extends ApiClient {
  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Options? options}) async {
    if (path.contains('/migrate-super-admin')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'token': 'sanctum-token-reconciled',
          'user': {'email': 'superadmin@example.com', 'role': 'super_admin'},
        } as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{} as T,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> secureStorage = {};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'read') {
      final key = methodCall.arguments['key'];
      return secureStorage[key];
    }
    if (methodCall.method == 'write') {
      final key = methodCall.arguments['key'];
      final val = methodCall.arguments['value'];
      secureStorage[key] = val;
      return true;
    }
    if (methodCall.method == 'containsKey') {
      final key = methodCall.arguments['key'];
      return secureStorage.containsKey(key);
    }
    return null;
  });

  late Directory tempDir;
  late Isar isar;
  late CodeGeneratorService codeGen;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: false);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('regression_test_');
    isar = await Isar.open(
      [ProductSchema, AppSequenceSchema, AppUserSchema, SyncMutationSchema],
      directory: tempDir.path,
      name: 'regression_db_${DateTime.now().microsecondsSinceEpoch}',
    );
    codeGen = CodeGeneratorService(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Application Non-Regression Test Suite', () {
    test('Regression: 1D Barcode (Code128) vs 2D QR Code output distinct valid SVG structures', () {
      final barcodeService = BarcodeSvgService();
      final product = Product.create(
        uuid: 'reg-prod-1',
        internalCode: 'CAP-REG-100',
        name: 'Produit Barcode Regression',
        format: '50ml',
        containment: 'Pot',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final qrSvg = barcodeService.generateSvg(
        product.internalCode,
        uuid: product.uuid,
        name: product.name,
        type: BarcodeExportType.qrCode,
      );
      final bar1dSvg = barcodeService.generateSvg(
        product.internalCode,
        uuid: product.uuid,
        name: product.name,
        type: BarcodeExportType.barcode128,
      );

      expect(qrSvg, startsWith('<svg'));
      expect(qrSvg, endsWith('</svg>'));
      expect(bar1dSvg, startsWith('<svg'));
      expect(bar1dSvg, endsWith('</svg>'));

      // Les structures internes doivent différer
      expect(qrSvg, isNot(equals(bar1dSvg)));
      expect(qrSvg, contains('CAP-REG-100'));
      expect(bar1dSvg, contains('CAP-REG-100'));
    });

    test('Regression: sequence numbers CAP-XXXX are monotonically increasing and never reused', () async {
      final Set<String> generatedCodes = {};
      const totalToGenerate = 25;

      for (int i = 0; i < totalToGenerate; i++) {
        final code = await codeGen.reserveNextInternalCode();
        expect(generatedCodes.contains(code), isFalse, reason: 'Sequence code $code was duplicate!');
        generatedCodes.add(code);
      }

      expect(generatedCodes.length, totalToGenerate);
      expect(generatedCodes.first, 'CAP-0001');
      expect(generatedCodes.last, 'CAP-0025');

      final lastNum = await codeGen.peekLastNumber();
      expect(lastNum, 25);
    });

    test('Regression: Super Admin reconciliation migrates local admin and persists Sanctum token', () async {
      // 1. Création locale du Super Admin dans Isar
      final now = DateTime.now();
      final localAdmin = AppUser.create(
        uuid: 'super-admin-local-reg',
        email: 'superadmin.reconcile@example.com',
        name: 'Super Admin Reconcile',
        role: 'super_admin',
        password: 'adminPassword123',
        syncStatus: SyncStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      await isar.writeTxn(() => isar.appUsers.put(localAdmin));

      final syncService = SyncService(isar, RegressionApiClient(), NotificationService());

      // 2. Réconciliation
      final reconciled = await syncService.reconcileSuperAdmin();
      expect(reconciled, isTrue);

      // Vérification que le token a bien été enregistré dans SecureStorage
      expect(secureStorage['auth_token'], 'sanctum-token-reconciled');

      // Vérification que le mot de passe en clair local est effacé après synchronisation réussie
      final updatedAdmin = await isar.appUsers.filter().emailEqualTo('superadmin.reconcile@example.com').findFirst();
      expect(updatedAdmin?.syncStatus, SyncStatus.synced);
      expect(updatedAdmin?.password, isNull);
    });
  });
}
