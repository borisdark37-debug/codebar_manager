import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:codebar_manager_app/core/services/image_compression_service.dart';

void main() {
  group('ImageCompressionService Tests', () {
    late Uint8List largePhotoBytes;
    late Uint8List smallPngBytes;

    setUp(() {
      // Image haute résolution 1600x1200 simulant une photo non-compressée (qualité 100)
      final largeImage = img.Image(width: 1600, height: 1200);
      for (var y = 0; y < 1200; y++) {
        for (var x = 0; x < 1600; x++) {
          largeImage.setPixelRgb(
            x,
            y,
            (x * 7 + y * 13) % 256,
            (x * 17 + y * 5) % 256,
            (x * 3 + y * 23) % 256,
          );
        }
      }
      largePhotoBytes = Uint8List.fromList(img.encodeJpg(largeImage, quality: 100));

      // Petite image 200x150 déjà en-dessous de 1024px
      final smallImage = img.Image(width: 200, height: 150);
      for (var y = 0; y < 150; y++) {
        for (var x = 0; x < 200; x++) {
          smallImage.setPixelRgb(x, y, 100, 150, 200);
        }
      }
      smallPngBytes = Uint8List.fromList(img.encodePng(smallImage));
    });

    test('compressBytes downscales image exceeding maxDimension to <= 1024px', () async {
      final compressedBytes = await ImageCompressionService.compressBytes(
        largePhotoBytes,
        maxDimension: 1024,
        quality: 75,
      );

      expect(compressedBytes, isNotEmpty);
      final decoded = img.decodeImage(compressedBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1024));
      expect(decoded.height, lessThanOrEqualTo(1024));
      // Vérification du ratio d'aspect préservé (1600/1200 = 4/3)
      expect(decoded.width, equals(1024));
      expect(decoded.height, equals(768));
    });

    test('compressBytes preserves small image dimensions without upscaling', () async {
      final compressedBytes = await ImageCompressionService.compressBytes(
        smallPngBytes,
        maxDimension: 1024,
        quality: 75,
      );

      final decoded = img.decodeImage(compressedBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(200));
      expect(decoded.height, equals(150));
    });

    test('compressBytes drastically reduces file size for photographic/large images', () async {
      final result = await ImageCompressionService.processWithStats(
        largePhotoBytes,
        maxDimension: 1024,
        quality: 75,
      );

      expect(result.compressedSize, lessThan(result.originalSize));
      expect(result.savingsPercentage, greaterThan(0));
      expect(result.formattedCompressedSize, isNotEmpty);
      expect(result.formattedOriginalSize, isNotEmpty);
      expect(result.base64, isNotEmpty);
    });

    test('compressBase64 handles valid base64 strings and data URI prefixes', () async {
      final base64Input = base64Encode(largePhotoBytes);
      final compressedBase64 = await ImageCompressionService.compressBase64(base64Input);

      expect(compressedBase64, isNotNull);
      expect(compressedBase64!.length, lessThan(base64Input.length));

      // Test avec préfixe data URI
      final dataUriInput = 'data:image/jpeg;base64,$base64Input';
      final compressedFromDataUri = await ImageCompressionService.compressBase64(dataUriInput);
      expect(compressedFromDataUri, isNotNull);
      expect(compressedFromDataUri, equals(compressedBase64));
    });

    test('compressBase64 handles null, empty, and whitespace strings gracefully', () async {
      expect(await ImageCompressionService.compressBase64(null), isNull);
      expect(await ImageCompressionService.compressBase64(''), isNull);
      expect(await ImageCompressionService.compressBase64('   '), isNull);
    });

    test('compressBytes handles empty and corrupted byte arrays without crashing', () async {
      final emptyResult = await ImageCompressionService.compressBytes(Uint8List(0));
      expect(emptyResult, isEmpty);

      final corrupted = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final fallbackResult = await ImageCompressionService.compressBytes(corrupted);
      expect(fallbackResult, equals(corrupted));
    });

    test('ImageCompressionResult calculations and byte formatting are correct', () {
      final stats = ImageCompressionResult(
        bytes: Uint8List(0),
        base64: '',
        originalSize: 1000000, // ~976 Ko
        compressedSize: 200000,  // ~195 Ko
      );

      expect(stats.savingsPercentage, closeTo(80.0, 0.1));
      expect(stats.formattedOriginalSize, contains('Ko'));
      expect(stats.formattedCompressedSize, contains('Ko'));

      final zeroStats = ImageCompressionResult(
        bytes: Uint8List(0),
        base64: '',
        originalSize: 0,
        compressedSize: 0,
      );
      expect(zeroStats.savingsPercentage, equals(0));
      expect(zeroStats.formattedOriginalSize, equals('0 B'));
    });

    test('cleanBase64 and decodeBase64 handle data URIs, corrupt data, and null safely', () {
      const rawText = 'Hello Flutter!';
      final rawBytes = Uint8List.fromList(utf8.encode(rawText));
      final standardBase64 = base64Encode(rawBytes);
      final dataUriBase64 = 'data:image/png;base64,$standardBase64';

      expect(ImageCompressionService.cleanBase64(standardBase64), equals(standardBase64));
      expect(ImageCompressionService.cleanBase64(dataUriBase64), equals(standardBase64));
      expect(ImageCompressionService.cleanBase64(null), isNull);
      expect(ImageCompressionService.cleanBase64('   '), isNull);

      final decodedFromStandard = ImageCompressionService.decodeBase64(standardBase64);
      expect(decodedFromStandard, isNotNull);
      expect(utf8.decode(decodedFromStandard!), equals(rawText));

      final decodedFromDataUri = ImageCompressionService.decodeBase64(dataUriBase64);
      expect(decodedFromDataUri, isNotNull);
      expect(utf8.decode(decodedFromDataUri!), equals(rawText));

      expect(ImageCompressionService.decodeBase64('invalid base64 %%%!'), isNull);
      expect(ImageCompressionService.decodeBase64(null), isNull);
      expect(ImageCompressionService.decodeBase64(''), isNull);
    });
  });
}
