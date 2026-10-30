import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

/// Service gérant la sauvegarde de fichiers exportés avec sélection de dossier par l'utilisateur.
class ExportFileService {
  final FilePicker? _filePicker;
  final FileSaver? _fileSaver;

  ExportFileService({
    FilePicker? filePicker,
    FileSaver? fileSaver,
  })  : _filePicker = filePicker,
        _fileSaver = fileSaver;

  FilePicker get _picker => _filePicker ?? FilePicker.platform;
  FileSaver get _saver => _fileSaver ?? FileSaver.instance;

  /// Sauvegarde un fichier SVG en demandant à l'utilisateur où le stocker.
  Future<String?> saveSvg({
    required String name,
    required Uint8List bytes,
    String? dialogTitle,
  }) {
    return saveFile(
      name: name,
      bytes: bytes,
      ext: 'svg',
      dialogTitle: dialogTitle ?? 'Enregistrer le code (SVG)',
    );
  }

  /// Sauvegarde une archive ZIP en demandant à l'utilisateur où la stocker.
  Future<String?> saveZip({
    required String name,
    required Uint8List bytes,
    String? dialogTitle,
  }) {
    return saveFile(
      name: name,
      bytes: bytes,
      ext: 'zip',
      dialogTitle: dialogTitle ?? "Enregistrer l'archive (ZIP)",
    );
  }

  /// Ouvre un dialogue natif permettant à l'utilisateur de choisir où enregistrer le fichier.
  /// Retourne le chemin du fichier enregistré, ou null si l'utilisateur a annulé.
  Future<String?> saveFile({
    required String name,
    required Uint8List bytes,
    required String ext,
    String? dialogTitle,
  }) async {
    final cleanExt = ext.replaceAll('.', '').toLowerCase();
    final formattedName = sanitizeFileName(name, cleanExt);

    String? selectedPath;
    try {
      selectedPath = await _picker.saveFile(
        dialogTitle: dialogTitle,
        fileName: formattedName,
        type: FileType.custom,
        allowedExtensions: [cleanExt],
        bytes: bytes,
      );
    } catch (e) {
      // Si le sélecteur natif rencontre une erreur d'implémentation, repli sur FileSaver
      try {
        final baseName = formattedName.substring(
          0,
          formattedName.length - cleanExt.length - 1,
        );
        return await _saver.saveFile(
          name: baseName,
          bytes: bytes,
          ext: cleanExt,
        );
      } catch (_) {
        rethrow;
      }
    }

    if (selectedPath == null) {
      return null;
    }

    var finalPath = selectedPath;
    if (!finalPath.toLowerCase().endsWith('.$cleanExt')) {
      finalPath = '$finalPath.$cleanExt';
    }

    // Sur plateformes de bureau (Windows, macOS, Linux), FilePicker.saveFile
    // ne fait qu'ouvrir le dialogue et renvoie le chemin sans écrire les données.
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final file = File(finalPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
    }

    return finalPath;
  }

  /// Nettoie le nom de fichier des caractères interdits par les systèmes de fichiers et garantit l'extension.
  static String sanitizeFileName(String name, String ext) {
    final cleanExt = ext.replaceAll('.', '').toLowerCase();
    var sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();

    String matchedExt = cleanExt;
    if (sanitized.toLowerCase().endsWith('.$cleanExt')) {
      matchedExt = sanitized.substring(sanitized.length - cleanExt.length);
      sanitized = sanitized.substring(0, sanitized.length - cleanExt.length - 1);
    }

    sanitized = sanitized.replaceAll(RegExp(r'[\s.]+$'), '').trim();
    if (sanitized.isEmpty) {
      sanitized = 'export';
    }
    return '$sanitized.$matchedExt';
  }
}
