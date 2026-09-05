import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/goodmap.dart';
import 'package:goodmap/src/good_map.dart' show GoodMapBuilder;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/mock_native_controller.dart';

class _FakeFill extends Fake implements Fill {}

GoodMapRegionOptions _region({
  String id = 'region',
  Color fillColor = Colors.blue,
  bool multipleParts = false,
}) {
  const outer = <LatLng>[
    LatLng(0, 0),
    LatLng(0, 4),
    LatLng(4, 4),
    LatLng(0, 0),
  ];
  const hole = <LatLng>[LatLng(1, 1), LatLng(1, 2), LatLng(2, 2), LatLng(1, 1)];
  const island = <LatLng>[
    LatLng(10, 10),
    LatLng(10, 11),
    LatLng(11, 11),
    LatLng(10, 10),
  ];
  return GoodMapRegionOptions(
    id: id,
    polygons: [
      GoodMapRegionPolygon(outerRing: outer, holes: const [hole]),
      if (multipleParts) GoodMapRegionPolygon(outerRing: island),
    ],
    fillColor: fillColor,
    outlineColor: Colors.black,
  );
}

void _stubNative(MockMapLibreMapController native) {
  when(
    () => native.toScreenLocation(any()),
  ).thenAnswer((_) async => const Point<num>(0, 0));
  when(() => native.addFill(any())).thenAnswer((_) async => _FakeFill());
  when(() => native.removeFill(any())).thenAnswer((_) async {});
}

Widget _map(GoodMapBuilder builder, List<GoodMapRegionOptions> regions) {
  return MaterialApp(
    home: GoodMap(
      initialCenter: const LatLng(0, 0),
      regions: regions,
      mapBuilder: builder,
    ),
  );
}

void main() {
  setUpAll(registerGoodFallbacks);

  test('region models preserve MultiPolygon parts and holes', () {
    final region = _region(multipleParts: true);

    expect(region.polygons, hasLength(2));
    expect(region.polygons.first.holes, hasLength(1));
    expect(region.fillOpacity, .24);
    expect(
      () => GoodMapRegionOptions(
        id: '',
        polygons: region.polygons,
        fillColor: Colors.blue,
        outlineColor: Colors.black,
      ),
      throwsAssertionError,
    );
    expect(
      () => GoodMapRegionPolygon(outerRing: const <LatLng>[]),
      throwsAssertionError,
    );
  });

  testWidgets('adds MultiPolygon parts and preserves holes', (tester) async {
    final native = MockMapLibreMapController();
    _stubNative(native);
    final builder = testMapBuilder(native);

    await tester.pumpWidget(_map(builder, [_region(multipleParts: true)]));
    await tester.pumpAndSettle();

    final calls = verify(() => native.addFill(captureAny())).captured;
    expect(calls, hasLength(2));
    final first = calls.first as FillOptions;
    expect(first.geometry, hasLength(2));
    expect(first.fillOpacity, .24);
    expect(first.fillColor, '#2196f3');
    expect(first.fillOutlineColor, '#000000');
  });

  testWidgets('diffs replacements and clearing by stable part id', (
    tester,
  ) async {
    final native = MockMapLibreMapController();
    _stubNative(native);
    final builder = testMapBuilder(native);

    await tester.pumpWidget(_map(builder, [_region()]));
    await tester.pumpAndSettle();
    verify(() => native.addFill(any())).called(1);

    await tester.pumpWidget(_map(builder, [_region()]));
    await tester.pumpAndSettle();
    verifyNever(() => native.addFill(any()));
    verifyNever(() => native.removeFill(any()));

    await tester.pumpWidget(_map(builder, [_region(fillColor: Colors.red)]));
    await tester.pumpAndSettle();
    verify(() => native.removeFill(any())).called(1);
    verify(() => native.addFill(any())).called(1);

    await tester.pumpWidget(_map(builder, const []));
    await tester.pumpAndSettle();
    verify(() => native.removeFill(any())).called(1);
  });

  testWidgets('removes a fill that completes after the region was cleared', (
    tester,
  ) async {
    final native = MockMapLibreMapController();
    final pending = Completer<Fill>();
    when(
      () => native.toScreenLocation(any()),
    ).thenAnswer((_) async => const Point<num>(0, 0));
    when(() => native.addFill(any())).thenAnswer((_) => pending.future);
    when(() => native.removeFill(any())).thenAnswer((_) async {});
    final builder = testMapBuilder(native);

    await tester.pumpWidget(_map(builder, [_region()]));
    await tester.pump();
    await tester.pumpWidget(_map(builder, const []));
    await tester.pump();

    pending.complete(_FakeFill());
    await tester.pumpAndSettle();

    verify(() => native.removeFill(any())).called(1);
  });

  testWidgets('reapplies declarative regions after style reload', (
    tester,
  ) async {
    final native = MockMapLibreMapController();
    _stubNative(native);
    late void Function() reloadStyle;
    var mapCreated = false;

    Widget builder({
      required String styleString,
      required CameraPosition initialCameraPosition,
      required void Function(MapLibreMapController) onMapCreated,
      required void Function() onStyleLoaded,
      required void Function(CameraPosition) onCameraMove,
    }) {
      reloadStyle = onStyleLoaded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mapCreated) {
          mapCreated = true;
          onMapCreated(native);
          onStyleLoaded();
        }
      });
      return const SizedBox.expand();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: GoodMap(
          initialCenter: const LatLng(0, 0),
          regions: [_region()],
          mapBuilder: builder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    verify(() => native.addFill(any())).called(1);

    reloadStyle();
    await tester.pumpAndSettle();

    verify(() => native.addFill(any())).called(1);
  });
}
