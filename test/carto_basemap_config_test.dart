import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/src/theme/carto_basemap_config.dart';

void main() {
  group('GoodBasemapConfig', () {
    test('defaults preserve the existing public CARTO styles', () {
      const config = GoodBasemapConfig();
      expect(config.lightStyleUrl, contains('positron'));
      expect(config.darkStyleUrl, contains('dark-matter'));
      expect(config.validatedApiKey(), isEmpty);
    });

    test('required keys reject null, empty, and whitespace values', () {
      for (final key in <String?>[null, '', '   ']) {
        final config = GoodBasemapConfig(cartoApiKey: key, requireApiKey: true);
        expect(
          config.validatedApiKey,
          throwsA(isA<GoodBasemapConfigurationException>()),
        );
      }
    });

    test('keys are encoded once and existing query parameters survive', () {
      final uri = cartoUriWithApiKey(
        Uri.parse('https://basemaps.cartocdn.com/style.json?lang=es'),
        'a+b/c =',
      );
      expect(uri.queryParameters['lang'], 'es');
      expect(uri.queryParameters['key'], 'a+b/c =');
      expect(uri.toString(), contains('a%2Bb%2Fc+%3D'));
    });

    test('tile placeholders survive URL rewriting', () {
      final url = cartoUrlWithApiKey(
        'https://tiles.basemaps.cartocdn.com/data/{z}/{x}/{y}.pbf',
        'key',
      );
      expect(url, contains('/{z}/{x}/{y}.pbf'));
      expect(Uri.parse(url).queryParameters['key'], 'key');
    });

    test('non-CARTO URLs are untouched', () {
      const value = 'https://example.com/style.json?lang=es';
      expect(cartoUrlWithApiKey(value, 'secret'), value);
    });
  });
}
