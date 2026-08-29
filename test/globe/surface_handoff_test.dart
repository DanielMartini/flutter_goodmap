import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/goodmap.dart';
import 'package:goodmap/src/globe/sphere_projection.dart';

/// Screen pixels per metre of ground at the centre of the globe.
double _globePixelsPerMetre(double globeZoom, double shortSide) =>
    globeRadius(globeZoom, shortSide) / 6378137.0;

/// Screen pixels per metre of ground for Web-Mercator at [latitude].
double _flatPixelsPerMetre(double flatZoom, double latitude) =>
    kMercatorTileSize *
    math.pow(2.0, flatZoom) /
    (2 * math.pi * 6378137.0 * math.cos(latitude * math.pi / 180.0));

void main() {
  group('globe <-> flat zoom matching', () {
    test('matched zooms show the same ground scale', () {
      const shortSide = 412.0;
      for (final latitude in [0.0, -8.8, 40.4, 64.0]) {
        for (final globeZoom in [2.0, 3.5, 4.75, 6.0]) {
          final flatZoom = flatZoomForGlobeZoom(
            globeZoom: globeZoom,
            shortSide: shortSide,
            latitude: latitude,
          );
          expect(
            _flatPixelsPerMetre(flatZoom, latitude),
            closeTo(_globePixelsPerMetre(globeZoom, shortSide), 1e-9),
            reason: 'lat $latitude, globe zoom $globeZoom',
          );
        }
      }
    });

    test('the conversion round-trips', () {
      const shortSide = 390.0;
      const latitude = 51.5;
      const globeZoom = 3.5;
      final flatZoom = flatZoomForGlobeZoom(
        globeZoom: globeZoom,
        shortSide: shortSide,
        latitude: latitude,
      );
      expect(
        globeZoomForFlatZoom(
          flatZoom: flatZoom,
          shortSide: shortSide,
          latitude: latitude,
        ),
        closeTo(globeZoom, 1e-9),
      );
    });

    test('one zoom level on the globe is one zoom level on the map', () {
      double flat(double globeZoom) =>
          flatZoomForGlobeZoom(globeZoom: globeZoom, shortSide: 400);

      expect(flat(4) - flat(3), closeTo(1.0, 1e-9));
    });

    test('the handoff threshold maps well above the default entry zoom', () {
      // The old fixed 5.0 entry zoom was ~1.6 levels past the globe's 3.5
      // handoff on a phone-sized viewport — the jump this replaces.
      final matched = flatZoomForGlobeZoom(globeZoom: 3.5, shortSide: 412);
      expect(matched, lessThan(5.0));
      expect(matched, greaterThan(2.0));
    });
  });

  test('hybrid surface zooms default to automatic matching', () {
    const hybrid = GoodMapGlobe(initialCenter: LatLng(0, 0));

    expect(hybrid.flatEntryZoom, isNull);
    expect(hybrid.globeEntryZoom, isNull);
    expect(hybrid.flatZoomToGlobe, isNull);
    expect(hybrid.globeZoomToFlat, 3.5);
  });

  test('explicit surface zooms are still honoured', () {
    const hybrid = GoodMapGlobe(
      initialCenter: LatLng(0, 0),
      flatEntryZoom: 5,
      globeEntryZoom: 3,
      flatZoomToGlobe: 4,
    );

    expect(hybrid.flatEntryZoom, 5);
    expect(hybrid.globeEntryZoom, 3);
    expect(hybrid.flatZoomToGlobe, 4);
  });

  test('globe exposes a zero-duration camera reset for surface handoffs', () {
    const globe = GoodGlobe(
      initialCenter: LatLng(0, 0),
      cameraResetDuration: Duration.zero,
      renderEnabled: false,
    );

    expect(globe.cameraResetDuration, Duration.zero);
    expect(
      const GoodGlobe(initialCenter: LatLng(0, 0)).cameraResetDuration,
      const Duration(milliseconds: 350),
    );
  });

  group('camera reset duration', () {
    Future<double?> pumpReset(WidgetTester tester, Duration duration) async {
      double? zoom;
      late StateSetter setOuter;
      var token = 0;
      var initialZoom = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return GoodGlobe(
                initialCenter: const LatLng(0, 0),
                initialZoom: initialZoom,
                resetToken: token,
                cameraResetDuration: duration,
                onCameraChanged: (_, z) => zoom = z,
                renderEnabled: false,
              );
            },
          ),
        ),
      );

      setOuter(() {
        token = 1;
        initialZoom = 3.0;
      });
      await tester.pump();
      return zoom;
    }

    testWidgets('zero duration snaps within the same frame', (tester) async {
      expect(await pumpReset(tester, Duration.zero), 3.0);
    });

    testWidgets('a non-zero duration still animates', (tester) async {
      expect(
        await pumpReset(tester, const Duration(milliseconds: 350)),
        anyOf(isNull, lessThan(3.0)),
      );
      await tester.pumpAndSettle();
    });
  });
}
