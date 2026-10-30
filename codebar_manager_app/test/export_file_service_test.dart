import 'dart:io';
import 'dart:typed_data';

import 'package:codebar_manager_app/core/services/export_file_service.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFilePicker extends FilePicker {
  String? saveFilePathToReturn;
  String? lastDialogTitle;
  String? lastFileName;
  FileType? lastType;
  List<String>? lastAllowedExtensions;
  Uint8List? lastBytes;
  bool shouldThrow = false;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (shouldThrow) {
      throw Exception('Fake picker error');
    }
    lastDialogTitle = dialogTitle;
    lastFileName = fileName;
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    lastBytes = bytes;
    return saveFilePathToReturn;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return null;
  }

  @override
  Future<bool?> clearTemporaryFiles() async => true;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => null;
}

class FakeFileSaver extends FileSaver {
  String? saveFileResult;
  String? lastName;
  String? lastExt;
  Uint8List? lastBytes;
  bool shouldThrow = false;

  @override
  Future<String> saveFile({
    required String name,
    Uint8List? bytes,
    File? file,
    String? filePath,
    LinkDetails? link,
    String ext = '',
    MimeType mimeType = MimeType.other,
    String? customMimeType,
    Dio? dioClient,
    Uint8List Function(dynamic data)? transformDioResponse,
  }) async {
    if (shouldThrow) {
      throw Exception('Fake saver error');
    }
    lastName = name;
    lastExt = ext;
    lastBytes = bytes;
    return saveFileResult ?? 'fallback/path/$name.$ext';
  }
}

void main() {
  group('ExportFileService.sanitizeFileName', () {
    test('removes forbidden characters and ensures extension', () {
      expect(
        ExportFileService.sanitizeFileName('code:123/test*', 'svg'),
        'code_123_test_.svg',
      );
      expect(
        ExportFileService.sanitizeFileName('my_export.svg', 'svg'),
        'my_export.svg',
      );
      expect(
        ExportFileService.sanitizeFileName('archive.ZIP', 'zip'),
        'archive.ZIP',
      );
      expect(
        ExportFileService.sanitizeFileName('', 'svg'),
        'export.svg',
      );
    });

    test('handles edge cases: whitespace, trailing dots, control chars, and standalone extension', () {
      expect(
        ExportFileService.sanitizeFileName('   ', 'svg'),
        'export.svg',
      );
      expect(
        ExportFileService.sanitizeFileName('.svg', 'svg'),
        'export.svg',
      );
      expect(
        ExportFileService.sanitizeFileName('foo.. ', 'svg'),
        'foo.svg',
      );
      expect(
        ExportFileService.sanitizeFileName('foo\x00bar\n', 'svg'),
        'foo_bar_.svg',
      );
    });
  });

  group('ExportFileService file saving', () {
    late FakeFilePicker fakePicker;
    late FakeFileSaver fakeSaver;
    late ExportFileService service;
    late Directory tempDir;

    setUp(() async {
      fakePicker = FakeFilePicker();
      fakeSaver = FakeFileSaver();
      service = ExportFileService(filePicker: fakePicker, fileSaver: fakeSaver);
      tempDir = await Directory.systemTemp.createTemp('export_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveSvg passes correct params to FilePicker and writes file', () async {
      final targetFile = '${tempDir.path}/code_test.svg';
      fakePicker.saveFilePathToReturn = targetFile;
      final bytes = Uint8List.fromList([60, 115, 118, 103, 62]); // <svg>

      final result = await service.saveSvg(name: 'code_test', bytes: bytes);

      expect(result, targetFile);
      expect(fakePicker.lastFileName, 'code_test.svg');
      expect(fakePicker.lastAllowedExtensions, ['svg']);
      expect(fakePicker.lastType, FileType.custom);
      expect(fakePicker.lastBytes, bytes);

      final savedFile = File(targetFile);
      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.readAsBytes(), bytes);
    });

    test('saveZip passes correct params to FilePicker and writes file', () async {
      final targetFile = '${tempDir.path}/archive_test.zip';
      fakePicker.saveFilePathToReturn = targetFile;
      final bytes = Uint8List.fromList([80, 75, 3, 4]); // PK header

      final result = await service.saveZip(name: 'archive_test', bytes: bytes);

      expect(result, targetFile);
      expect(fakePicker.lastFileName, 'archive_test.zip');
      expect(fakePicker.lastAllowedExtensions, ['zip']);
      expect(fakePicker.lastType, FileType.custom);
      expect(fakePicker.lastBytes, bytes);

      final savedFile = File(targetFile);
      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.readAsBytes(), bytes);
    });

    test('returns null gracefully when user cancels save dialog', () async {
      fakePicker.saveFilePathToReturn = null;
      final bytes = Uint8List.fromList([1, 2, 3]);

      final result = await service.saveSvg(name: 'cancelled', bytes: bytes);

      expect(result, isNull);
    });

    test('appends extension if user selection on desktop omitted it', () async {
      final targetWithoutExt = '${tempDir.path}/my_saved_code';
      fakePicker.saveFilePathToReturn = targetWithoutExt;
      final bytes = Uint8List.fromList([60, 115, 118, 103, 62]);

      final result = await service.saveSvg(name: 'my_saved_code', bytes: bytes);

      expect(result, '$targetWithoutExt.svg');
      expect(await File('$targetWithoutExt.svg').exists(), isTrue);
    });

    test('falls back to FileSaver when FilePicker encounters platform error', () async {
      fakePicker.shouldThrow = true;
      fakeSaver.saveFileResult = 'fallback/path/code.svg';
      final bytes = Uint8List.fromList([1, 2, 3]);

      final result = await service.saveSvg(name: 'code:test', bytes: bytes);

      expect(result, 'fallback/path/code.svg');
      expect(fakeSaver.lastName, 'code_test');
      expect(fakeSaver.lastExt, 'svg');
      expect(fakeSaver.lastBytes, bytes);
    });

    test('rethrows error when FileSaver fallback also fails', () async {
      fakePicker.shouldThrow = true;
      fakeSaver.shouldThrow = true;
      final bytes = Uint8List.fromList([1, 2, 3]);

      expect(
        () => service.saveSvg(name: 'failing_file', bytes: bytes),
        throwsA(isA<Exception>()),
      );
    });
  });
}
