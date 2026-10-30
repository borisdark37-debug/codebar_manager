import 'dart:io';
import 'package:codebar_manager_app/core/database/collections/app_sequence.dart';
import 'package:codebar_manager_app/core/services/code_generator_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late Isar isar;
  late CodeGeneratorService codeGen;

  setUpAll(() async {
    try {
      await Isar.initializeIsarCore(download: true);
    } catch (_) {}
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('code_gen_test_');
    isar = await Isar.open(
      [AppSequenceSchema],
      directory: tempDir.path,
      name: 'code_gen_db_${DateTime.now().microsecondsSinceEpoch}',
    );
    codeGen = CodeGeneratorService(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('CodeGeneratorService Unit Tests', () {
    test('generateUuid produces valid UUID v4 format', () {
      final uuid = codeGen.generateUuid();
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(uuidRegex.hasMatch(uuid), isTrue);
    });

    test('reserveNextInternalCode generates sequential zero-padded codes', () async {
      final code1 = await codeGen.reserveNextInternalCode();
      expect(code1, 'CAP-0001');

      final code2 = await codeGen.reserveNextInternalCode();
      expect(code2, 'CAP-0002');

      final code3 = await codeGen.reserveNextInternalCode();
      expect(code3, 'CAP-0003');

      final last = await codeGen.peekLastNumber();
      expect(last, 3);
    });
  });
}
