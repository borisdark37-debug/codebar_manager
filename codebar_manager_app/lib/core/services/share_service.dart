import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  static Future<File> getOrCreateSvgFile({
    required String fileName,
    required String svgContent,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = _safeFileName(fileName);
    final file = File('${dir.path}/$safeName.svg');
    await file.writeAsString(svgContent, flush: true);
    return file;
  }

  static Future<void> shareSvgFile({
    required File file,
    String? subject,
  }) async {
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'image/svg+xml'),
    ], subject: subject ?? file.uri.pathSegments.last);
  }

  static Future<void> shareSvgContent({
    required String fileName,
    required String svgContent,
    String? subject,
  }) async {
    final file = await getOrCreateSvgFile(
      fileName: fileName,
      svgContent: svgContent,
    );
    await shareSvgFile(file: file, subject: subject ?? fileName);
  }

  static Future<void> shareZipContent({
    required String fileName,
    required Uint8List bytes,
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName.zip');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/zip'),
    ], subject: subject ?? fileName);
  }

  static String _safeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'code-barres' : sanitized;
  }
}
