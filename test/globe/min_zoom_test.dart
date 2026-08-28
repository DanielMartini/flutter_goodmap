import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodmap/goodmap.dart';

void main() {
  test('globe widgets expose a configurable minimum zoom', () {
    const globe = GoodGlobe(
      initialCenter: LatLng(0, 0),
      minZoom: 0.75,
      renderEnabled: false,
    );
    const hybrid = GoodMapGlobe(initialCenter: LatLng(0, 0), minZoom: 0.75);

    expect(globe.minZoom, 0.75);
    expect(hybrid.minZoom, 0.75);
  });

  testWidgets('pinch zoom respects minZoom', (tester) async {
    double? seenZoom;
    await tester.pumpWidget(
      MaterialApp(
        home: GoodGlobe(
          initialCenter: const LatLng(0, 0),
          initialZoom: 1,
          minZoom: 0.75,
          onCameraChanged: (_, zoom) => seenZoom = zoom,
          renderEnabled: false,
        ),
      ),
    );

    final center = tester.getCenter(find.byType(GoodGlobe));
    final first = await tester.startGesture(center - const Offset(100, 0));
    final second = await tester.startGesture(
      center + const Offset(100, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(5, 0));
    await second.moveTo(center + const Offset(5, 0));
    await tester.pump();

    expect(seenZoom, 0.75);
    await first.up();
    await second.up();
  });
}
