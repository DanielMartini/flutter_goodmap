import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/src/theme/carto_basemap_config.dart';
import 'package:goodmap/src/theme/carto_style_loader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiKey = 'test key+/';

  test(
    'rewrites every CARTO style resource and preserves tile metadata',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/tiles.json')) {
          return http.Response(
            jsonEncode({
              'tiles': [
                'https://tiles.basemaps.cartocdn.com/data/{z}/{x}/{y}.pbf?lang=es',
              ],
              'attribution': 'CARTO',
              'minzoom': 1,
              'maxzoom': 14,
              'bounds': [-180, -85, 180, 85],
              'scheme': 'xyz',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'version': 8,
            'sources': {
              'tileJson': {
                'type': 'vector',
                'url': 'https://basemaps.cartocdn.com/tiles.json',
              },
              'inline': {
                'type': 'vector',
                'tiles': [
                  'https://tiles.basemaps.cartocdn.com/inline/{z}/{x}/{y}.pbf',
                ],
              },
              'external': {
                'type': 'vector',
                'tiles': ['https://example.com/{z}/{x}/{y}.pbf'],
              },
            },
            'sprite': 'https://basemaps.cartocdn.com/sprite',
            'glyphs':
                'https://basemaps.cartocdn.com/fonts/{fontstack}/{range}.pbf',
            'layers': [],
          }),
          200,
        );
      });
      final loader = CartoStyleLoader(client: client);

      final result =
          jsonDecode(
                await loader.load(
                  Brightness.light,
                  const GoodBasemapConfig(
                    cartoApiKey: apiKey,
                    requireApiKey: true,
                  ),
                ),
              )
              as Map<String, dynamic>;
      final sources = result['sources'] as Map<String, dynamic>;
      final tileJson = sources['tileJson'] as Map<String, dynamic>;
      expect(tileJson, isNot(contains('url')));
      expect(tileJson['attribution'], 'CARTO');
      expect(tileJson['minzoom'], 1);
      expect(tileJson['maxzoom'], 14);
      expect(tileJson['bounds'], [-180, -85, 180, 85]);
      expect(tileJson['scheme'], 'xyz');

      for (final url in <String>[
        ...(tileJson['tiles'] as List).cast<String>(),
        ...((sources['inline'] as Map)['tiles'] as List).cast<String>(),
        result['sprite'] as String,
        result['glyphs'] as String,
      ]) {
        expect(Uri.parse(url).queryParameters['key'], apiKey);
      }
      expect(result['glyphs'], contains('{fontstack}/{range}'));
      expect(
        ((sources['external'] as Map)['tiles'] as List).single,
        'https://example.com/{z}/{x}/{y}.pbf',
      );
      expect(requests, hasLength(2));
      expect(
        requests.every((uri) => uri.queryParameters['key'] == apiKey),
        isTrue,
      );
    },
  );

  group('process-wide completed-style cache', () {
    setUp(CartoStyleLoader.clearCompletedCache);
    tearDown(CartoStyleLoader.clearCompletedCache);

    const config = GoodBasemapConfig(cartoApiKey: 'key');

    CartoStyleLoader loaderCounting(List<Uri> requests, {bool shared = true}) =>
        CartoStyleLoader(
          client: MockClient((request) async {
            requests.add(request.url);
            return http.Response(
              '{"version":8,"sources":{},"layers":[]}',
              200,
            );
          }),
          shareCompleted: shared,
        );

    test('a second loader reuses a completed style instead of refetching', () async {
      final requests = <Uri>[];
      await loaderCounting(requests).load(Brightness.light, config);
      expect(requests, hasLength(1));

      // A remounted GoodMap builds a fresh loader — the globe -> flat handoff
      // does this on every pass and must not pay for the style again.
      await loaderCounting(requests).load(Brightness.light, config);
      expect(requests, hasLength(1));
    });

    test('failures are not cached', () async {
      final failing = CartoStyleLoader(
        client: MockClient((_) async => http.Response('nope', 500)),
        shareCompleted: true,
      );
      await expectLater(
        failing.load(Brightness.light, config),
        throwsA(isA<CartoStyleLoadException>()),
      );

      final requests = <Uri>[];
      await loaderCounting(requests).load(Brightness.light, config);
      expect(requests, hasLength(1));
    });

    test('loaders opt out of the shared cache by default', () async {
      final requests = <Uri>[];
      await loaderCounting(requests, shared: false).load(Brightness.light, config);
      await loaderCounting(requests, shared: false).load(Brightness.light, config);
      expect(requests, hasLength(2));
    });
  });

  test('concurrent identical loads share the same cached future', () {
    final client = MockClient(
      (_) async => http.Response('{"version":8,"sources":{},"layers":[]}', 200),
    );
    final loader = CartoStyleLoader(client: client);
    const config = GoodBasemapConfig(cartoApiKey: 'key');
    final first = loader.load(Brightness.light, config);
    final second = loader.load(Brightness.light, config);
    expect(identical(first, second), isTrue);
  });

  test('light and dark modes load their configured style URLs', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('{"version":8,"sources":{},"layers":[]}', 200);
    });
    final loader = CartoStyleLoader(client: client);
    const config = GoodBasemapConfig(
      lightStyleUrl: 'https://basemaps.cartocdn.com/light.json',
      darkStyleUrl: 'https://basemaps.cartocdn.com/dark.json',
    );
    await loader.load(Brightness.light, config);
    await loader.load(Brightness.dark, config);
    expect(requests.map((uri) => uri.path), ['/light.json', '/dark.json']);
  });

  test(
    'HTTP and JSON failures are deterministic and do not leak the key',
    () async {
      for (final response in <http.Response>[
        http.Response('nope', 500),
        http.Response('{not-json', 200),
      ]) {
        final loader = CartoStyleLoader(
          client: MockClient((_) async => response),
        );
        try {
          await loader.load(
            Brightness.light,
            const GoodBasemapConfig(cartoApiKey: apiKey),
          );
          fail('Expected style loading to fail');
        } catch (error) {
          expect(error, isA<CartoStyleLoadException>());
          expect(error.toString(), isNot(contains(apiKey)));
        }
      }
    },
  );

  test('tile JSON without tiles fails without exposing the key', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('tiles.json')) {
        return http.Response('{"attribution":"CARTO"}', 200);
      }
      return http.Response(
        '{"version":8,"sources":{"x":{"url":"https://basemaps.cartocdn.com/tiles.json"}},"layers":[]}',
        200,
      );
    });
    final loader = CartoStyleLoader(client: client);
    expect(
      loader.load(
        Brightness.light,
        const GoodBasemapConfig(cartoApiKey: apiKey),
      ),
      throwsA(
        isA<CartoStyleLoadException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(apiKey)),
        ),
      ),
    );
  });
}
