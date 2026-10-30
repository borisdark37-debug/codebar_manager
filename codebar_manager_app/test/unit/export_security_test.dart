import 'package:codebar_manager_app/core/services/export_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Export File Security and Path Traversal Tests', () {
    test('sanitizeFileName defangs directory traversal patterns (Unix & Windows)', () {
      // Unix style traversal
      final unixTraversal = ExportFileService.sanitizeFileName(
        '../../../../etc/passwd',
        'svg',
      );
      expect(unixTraversal.contains('/'), isFalse, reason: 'Slash must be removed/replaced');
      expect(unixTraversal.contains('\\'), isFalse, reason: 'Backslash must be removed/replaced');
      expect(unixTraversal, '.._.._.._.._etc_passwd.svg');
      expect(unixTraversal.endsWith('.svg'), isTrue);

      // Windows style traversal
      final winTraversal = ExportFileService.sanitizeFileName(
        '..\\..\\..\\Windows\\System32\\cmd.exe',
        'zip',
      );
      expect(winTraversal.contains('/'), isFalse);
      expect(winTraversal.contains('\\'), isFalse);
      expect(winTraversal, '.._.._.._Windows_System32_cmd.exe.zip');
      expect(winTraversal.endsWith('.zip'), isTrue);
    });

    test('sanitizeFileName neutralizes control characters, colons, pipes and null bytes', () {
      final malicious = ExportFileService.sanitizeFileName(
        'test:export|file*with<weird>chars?\x00\x1F',
        'svg',
      );

      final forbiddenChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
      expect(forbiddenChars.hasMatch(malicious), isFalse);
      expect(malicious.endsWith('.svg'), isTrue);
    });

    test('sanitizeFileName handles empty, whitespace-only or dots-only inputs safely', () {
      final dotsOnly = ExportFileService.sanitizeFileName('.....', 'svg');
      expect(dotsOnly, 'export.svg');

      final whitespaceOnly = ExportFileService.sanitizeFileName('   ', 'svg');
      expect(whitespaceOnly, 'export.svg');

      final empty = ExportFileService.sanitizeFileName('', 'zip');
      expect(empty, 'export.zip');
    });

    test('sanitizeFileName prevents double-extension and preserves clean extension', () {
      final doubleExt = ExportFileService.sanitizeFileName('my_export.svg', 'svg');
      expect(doubleExt, 'my_export.svg');

      final doubleExtCase = ExportFileService.sanitizeFileName('my_export.SVG', 'svg');
      expect(doubleExtCase, 'my_export.SVG');
    });
  });
}
