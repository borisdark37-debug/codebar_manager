import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Résultat d'une compression d'image avec statistiques d'optimisation.
class ImageCompressionResult {
  final Uint8List bytes;
  final String base64;
  final int originalSize;
  final int compressedSize;

  const ImageCompressionResult({
    required this.bytes,
    required this.base64,
    required this.originalSize,
    required this.compressedSize,
  });

  /// Ratio d'économie en pourcentage (ex: 78.5%)
  double get savingsPercentage {
    if (originalSize <= 0) return 0;
    final diff = originalSize - compressedSize;
    if (diff <= 0) return 0;
    return (diff / originalSize) * 100;
  }

  /// Poids initial formaté en Ko ou Mo
  String get formattedOriginalSize => _formatBytes(originalSize);

  /// Poids final formaté en Ko ou Mo
  String get formattedCompressedSize => _formatBytes(compressedSize);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} Mo';
  }
}

/// Service de compression et d'optimisation d'images multiplateforme (Android, Windows, iOS, Web).
/// Garantit un poids maîtrisé en base de données locale (Isar) et lors des synchronisations réseau.
class ImageCompressionService {
  static const int defaultMaxDimension = 1024;
  static const int defaultQuality = 75;

  /// Nettoie une chaîne base64 en supprimant les espaces et les préfixes Data URI (ex: data:image/jpeg;base64,).
  static String? cleanBase64(String? base64String) {
    if (base64String == null) return null;
    final trimmed = base64String.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.contains(',') ? trimmed.split(',').last.trim() : trimmed;
  }

  /// Décode de façon sécurisée une chaîne base64 (avec ou sans préfixe Data URI).
  /// Renvoie null si la chaîne est nulle, vide ou corrompue au lieu de lever une exception.
  static Uint8List? decodeBase64(String? base64String) {
    final clean = cleanBase64(base64String);
    if (clean == null || clean.isEmpty) return null;
    try {
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  /// Compresse un flux d'octets d'image (JPEG, PNG, WebP, etc.).
  /// Redimensionne si les dimensions excèdent [maxDimension] en conservant le ratio d'aspect.
  /// Ré-encode en JPEG avec la qualité spécifiée [quality] (1 à 100).
  static Future<Uint8List> compressBytes(
    Uint8List rawBytes, {
    int maxDimension = defaultMaxDimension,
    int quality = defaultQuality,
  }) async {
    if (rawBytes.isEmpty) return rawBytes;

    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        // En cas de format binaire non reconnu par decodeImage, conserve les octets
        return rawBytes;
      }

      // Applique la rotation EXIF pour que l'orientation caméra mobile soit respectée
      final oriented = img.bakeOrientation(decoded);
      img.Image processed = oriented;
      final int originalW = oriented.width;
      final int originalH = oriented.height;

      // Redimensionnement proportionnel si dépassement du seuil max
      if (originalW > maxDimension || originalH > maxDimension) {
        if (originalW >= originalH) {
          processed = img.copyResize(
            oriented,
            width: maxDimension,
            interpolation: img.Interpolation.linear,
          );
        } else {
          processed = img.copyResize(
            oriented,
            height: maxDimension,
            interpolation: img.Interpolation.linear,
          );
        }
      }

      // Encodage JPEG compressé
      final compressedBytes = Uint8List.fromList(
        img.encodeJpg(processed, quality: quality),
      );

      // Si les dimensions étaient déjà conformes et que l'original est plus compact, on conserve l'original
      if (originalW <= maxDimension &&
          originalH <= maxDimension &&
          rawBytes.length <= compressedBytes.length) {
        return rawBytes;
      }

      return compressedBytes;
    } catch (_) {
      // Tolérance aux pannes : fallback transparent sur les octets d'origine
      return rawBytes;
    }
  }

  /// Compresse une chaîne base64 existante et renvoie la nouvelle chaîne optimisée.
  /// Si la chaîne est nulle, vide ou invalide, gère gracieusement le cas.
  static Future<String?> compressBase64(
    String? base64String, {
    int maxDimension = defaultMaxDimension,
    int quality = defaultQuality,
  }) async {
    final clean = cleanBase64(base64String);
    if (clean == null) return null;

    try {
      final rawBytes = base64Decode(clean);
      final compressedBytes = await compressBytes(
        rawBytes,
        maxDimension: maxDimension,
        quality: quality,
      );
      return base64Encode(compressedBytes);
    } catch (_) {
      return base64String;
    }
  }

  /// Analyse et compresse des octets avec renvoi des métriques de compression.
  static Future<ImageCompressionResult> processWithStats(
    Uint8List rawBytes, {
    int maxDimension = defaultMaxDimension,
    int quality = defaultQuality,
  }) async {
    final originalSize = rawBytes.length;
    final compressedBytes = await compressBytes(
      rawBytes,
      maxDimension: maxDimension,
      quality: quality,
    );
    final base64 = base64Encode(compressedBytes);

    return ImageCompressionResult(
      bytes: compressedBytes,
      base64: base64,
      originalSize: originalSize,
      compressedSize: compressedBytes.length,
    );
  }

  /// Sélectionne une image (via Caméra ou Galerie) et applique immédiatement la compression.
  static Future<ImageCompressionResult?> pickAndCompress({
    required ImageSource source,
    int maxDimension = defaultMaxDimension,
    int quality = defaultQuality,
    ImagePicker? picker,
  }) async {
    final imagePicker = picker ?? ImagePicker();
    final pickedFile = await imagePicker.pickImage(
      source: source,
      maxWidth: maxDimension.toDouble(),
      maxHeight: maxDimension.toDouble(),
      imageQuality: quality,
    );

    if (pickedFile == null) return null;

    final rawBytes = await pickedFile.readAsBytes();
    return processWithStats(
      rawBytes,
      maxDimension: maxDimension,
      quality: quality,
    );
  }
}
