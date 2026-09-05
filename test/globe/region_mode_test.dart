import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/goodmap.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mock_native_controller.dart';

class _FakeFill extends Fake implements Fill {}

final _bounds = LatLngBounds(
  southwest: const LatLng(39, -4),
  northeast: const LatLng(41, -2),
);

final _region = GoodMapRegionOptions(
  id: 'madrid',
  polygons: [
    GoodMapRegionPolygon(
      outerRing: [
        const LatLng(39, -4),
        const LatLng(39, -2),
        const LatLng(41, -2),
        const LatLng(39, -4),
      ],
    ),
  ],
  fillColor: Colors.blue,
  outlineColor: Colors.black,
);

void _stubNative(MockMapLibreMapController native) {
  when(
    () => native.toScreenLocation(any()),
  ).thenAnswer((_) async => const Point<num>(0, 0));
  when(() => native.addFill(any())).thenAnswer((_) async => _FakeFill());
  when(() => native.removeFill(any())).thenAnswer((_) async {});
  when(() => native.animateCamera(any())).thenAnswer((_) async => true);
  when(() => native.moveCamera(any())).thenAnswer((_) async => true);
}

void main() {
  setUpAll(registerGoodFallbacks);

  testWidgets('regions force flat, fit per token, and restore globe camera', (
    tester,
  ) async {
    final native = MockMapLibreMapController();
    _stubNative(native);
    final surfaces = <bool>[];
    final mapBuilder = testMapBuilder(native);

    Widget build({required List<GoodMapRegionOptions> regions, Object? token}) {
      return MaterialApp(
        home: GoodMapGlobe(
          initialCenter: const LatLng(40, -3),
          initialZoom: 2,
          regions: regions,
          focusBounds: regions.isEmpty ? null : _bounds,
          focusToken: token,
          transition: Duration.zero,
          onSurfaceChanged: surfaces.add,
          mapBuilder: mapBuilder,
        ),
      );
    }

    await tester.pumpWidget(build(regions: const []));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(regions: [_region], token: 'v1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flat')), findsOneWidget);
    verifyInOrder([
      () => native.addFill(any()),
      () => native.animateCamera(any()),
    ]);

    await tester.pumpWidget(build(regions: [_region], token: 'v1'));
    await tester.pumpAndSettle();
    verifyNever(() => native.animateCamera(any()));

    await tester.pumpWidget(build(regions: [_region], token: 'v2'));
    await tester.pumpAndSettle();
    verify(() => native.animateCamera(any())).called(1);

    await tester.pumpWidget(build(regions: const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flat')), findsNothing);
    final globe = tester.widget<GoodGlobe>(find.byKey(const ValueKey('globe')));
    expect(globe.initialCenter, const LatLng(40, -3));
    expect(globe.initialZoom, 2);
    verify(() => native.removeFill(any())).called(1);
    expect(surfaces, containsAllInOrder([true, false]));
  });

  testWidgets('clearing regions restores an already-flat camera and surface', (
    tester,
  ) async {
    final native = MockMapLibreMapController();
    _stubNative(native);
    void Function(CameraPosition)? reportFlatCamera;
    var created = false;

    Widget mapBuilder({
      required String styleString,
      required CameraPosition initialCameraPosition,
      required void Function(MapLibreMapController) onMapCreated,
      required void Function() onStyleLoaded,
      required void Function(CameraPosition) onCameraMove,
    }) {
      reportFlatCamera = onCameraMove;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!created) {
          created = true;
          onMapCreated(native);
          onStyleLoaded();
        }
      });
      return const SizedBox.expand();
    }

    Widget build(List<GoodMapRegionOptions> regions) {
      return MaterialApp(
        home: GoodMapGlobe(
          initialCenter: const LatLng(0, 0),
          initialZoom: 1,
          regions: regions,
          focusBounds: regions.isEmpty ? null : _bounds,
          focusToken: 'v1',
          transition: Duration.zero,
          mapBuilder: mapBuilder,
        ),
      );
    }

    await tester.pumpWidget(build(const []));
    await tester.pumpAndSettle();
    final globe = tester.widget<GoodGlobe>(find.byKey(const ValueKey('globe')));
    globe.onCameraChanged?.call(const LatLng(10, 20), 4);
    await tester.pumpAndSettle();
    reportFlatCamera?.call(
      const CameraPosition(target: LatLng(11, 21), zoom: 8),
    );

    await tester.pumpWidget(build([_region]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flat')), findsOneWidget);
    verify(() => native.moveCamera(any())).called(1);
  });
}
