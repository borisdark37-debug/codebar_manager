import 'dart:typed_data';
import 'package:codebar_manager_app/core/services/image_compression_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('Image Compression Performance & Benchmark Tests', () {
    test('Benchmark: compresses high-resolution 1600x1200 image in < 2500ms with significant size reduction', () async {
      // 1. Synthèse d'une image haute résolution 1600x1200 simulant une photo non-compressée (qualité 100)
      final rawImage = img.Image(width: 1600, height: 1200);
      for (var y = 0; y < 1200; y++) {
        for (var x = 0; x < 1600; x++) {
          rawImage.setPixelRgb(
            x,
            y,
            (x * 7 + y * 13) % 256,
            (x * 17 + y * 5) % 256,
            (x * 3 + y * 23) % 256,
          );
        }
      }

      final highQualityJpgBytes = Uint8List.fromList(img.encodeJpg(rawImage, quality: 100));
      final initialSizeBytes = highQualityJpgBytes.lengthInBytes;

      // 2. Mesure du temps d'exécution de la compression
      final stopwatch = Stopwatch()..start();
      final result = await ImageCompressionService.processWithStats(
        highQualityJpgBytes,
        quality: 75,
        maxDimension: 1024,
      );
      stopwatch.stop();

      final durationMs = stopwatch.elapsedMilliseconds;

      // 3. Assertions de performance et qualité
      expect(result.originalSize, initialSizeBytes);
      expect(result.compressedSize, lessThan(result.originalSize));
      expect(result.savingsPercentage, greaterThan(40.0), reason: 'Doit réduire d\'au moins 40% la taille');
      expect(durationMs, lessThan(3500), reason: 'La compression doit prendre moins de 3.5 secondes (mesuré: ${durationMs}ms)');

      // 4. Décodage et vérification du redimensionnement
      final decodedCompressed = img.decodeImage(result.bytes);
      expect(decodedCompressed, isNotNull);
      expect(decodedCompressed!.width, 1024);
      expect(decodedCompressed.height, 768);
    });

    test('Benchmark: fast processing of small icons (128x128) without unnecessary downscaling', () async {
      final small = img.Image(width: 128, height: 128);
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          small.setPixelRgb(x, y, 100, 150, 200);
        }
      }
      final smallBytes = Uint8List.fromList(img.encodePng(small));

      final sw = Stopwatch()..start();
      final result = await ImageCompressionService.processWithStats(
        smallBytes,
        maxDimension: 1024,
      );
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(400), reason: 'Petite image traitée rapidement');
      final decoded = img.decodeImage(result.bytes);
      expect(decoded?.width, 128);
      expect(decoded?.height, 128);
    });
  });
}
