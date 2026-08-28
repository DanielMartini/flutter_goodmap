import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/goodmap.dart';
import 'package:goodmap/src/globe/detail_tile_atlas.dart';
import 'package:goodmap/src/globe/sphere_projection.dart';
import 'package:goodmap/src/globe/tile_atlas.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const config = GoodBasemapConfig(
    cartoApiKey: 'globe key+/',
    requireApiKey: true,
  );

  test('regular globe raster requests carry the encoded key', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('', 404);
    });
    final atlas = TileAtlas(
      brightness: Brightness.light,
      tileZoom: 0,
      width: 1,
      height: 1,
      basemapConfig: config,
      client: client,
    );
    addTearDown(atlas.dispose);
    expect(await atlas.build(), isNull);
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['key'], config.cartoApiKey);
  });

  test('detail globe raster requests carry the encoded key', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('', 404);
    });
    const size = Size(200, 200);
    const projection = SphereProjection(
      center: Offset(100, 100),
      radius: 5000,
      rotationX: 0,
      rotationZ: 0,
    );
    final atlas = DetailTileAtlas(
      brightness: Brightness.dark,
      center: const LatLng(0, 0),
      zoom: 6,
      viewportSize: size,
      projection: projection,
      width: 1,
      height: 1,
      basemapConfig: config,
      client: client,
    );
    addTearDown(atlas.dispose);
    expect(await atlas.build(), isNull);
    expect(requests, isNotEmpty);
    expect(
      requests.every((uri) => uri.queryParameters['key'] == config.cartoApiKey),
      isTrue,
    );
  });

  test('required missing key fails before any raster request', () async {
    var calls = 0;
    final atlas = TileAtlas(
      brightness: Brightness.light,
      tileZoom: 0,
      basemapConfig: const GoodBasemapConfig(requireApiKey: true),
      client: MockClient((_) async {
        calls++;
        return http.Response('', 404);
      }),
    );
    addTearDown(atlas.dispose);
    await expectLater(
      atlas.build(),
      throwsA(isA<GoodBasemapConfigurationException>()),
    );
    expect(calls, 0);
  });
}
