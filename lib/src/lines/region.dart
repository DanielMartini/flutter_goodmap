import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

enum GoodMapRegionState { loading, ready, error }

typedef GoodMapRegionStateChanged =
    void Function(Object? token, GoodMapRegionState state);

/// One polygon part of a declarative map region.
@immutable
class GoodMapRegionPolygon {
  const GoodMapRegionPolygon({required this.outerRing, this.holes = const []})
    : assert(outerRing.length >= 3);

  final List<LatLng> outerRing;
  final List<List<LatLng>> holes;
}

/// A geography-agnostic region rendered as one or more polygon parts.
@immutable
class GoodMapRegionOptions {
  const GoodMapRegionOptions({
    required this.id,
    required this.polygons,
    required this.fillColor,
    this.fillOpacity = .24,
    required this.outlineColor,
  }) : assert(id != ''),
       assert(polygons.length > 0),
       assert(fillOpacity >= 0 && fillOpacity <= 1);

  final String id;
  final List<GoodMapRegionPolygon> polygons;
  final Color fillColor;
  final double fillOpacity;
  final Color outlineColor;
}
