import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../good_map.dart';
import '../heatmap/heatmap.dart';
import '../markers/marker.dart';
import '../popups/popup.dart';
import '../theme/carto_basemap_config.dart';
import 'globe_overlays.dart';
import 'good_globe.dart';

/// A globe that becomes a street map when you zoom in.
///
/// Shows a [GoodGlobe] (world/regional view, with arcs + points) at low zoom,
/// then cross-fades to the native [GoodMap] — full vector streets and cities —
/// once you pinch past [globeZoomToFlat]. Zooming the flat map back out below
/// [flatZoomToGlobe] returns to the globe. The centre coordinate carries across.
class GoodMapGlobe extends StatefulWidget {
  const GoodMapGlobe({
    required this.initialCenter,
    this.initialZoom = 1.0,
    this.minZoom = 0.0,
    this.resetToken = 0,
    this.markers = const [],
    @Deprecated('Use markers instead') this.points = const [],
    this.popups = const [],
    this.arcs = const [],
    this.heatmaps = const [],
    this.atmosphere = false,
    this.controls = const GoodControls(),
    this.globeZoomToFlat = 3.5,
    this.flatZoomToGlobe = 4.0,
    this.flatEntryZoom = 5.0,
    this.globeEntryZoom = 3.0,
    this.transition = const Duration(milliseconds: 280),
    this.onTap,
    this.onSurfaceChanged,
    this.showDottedGrid = false,
    this.dottedGridColor,
    this.dottedGridRadius = 1.2,
    this.dateTime,
    this.sunPosition,
    this.timeRange,
    this.basemapConfig,
    this.onBasemapError,
    super.key,
  }) : assert(minZoom >= 0.0 && minZoom <= 6.0);

  final LatLng initialCenter;

  /// Initial globe zoom (0 = far, ~6 = close).
  final double initialZoom;

  /// Minimum zoom allowed while the globe surface is active.
  ///
  /// Must be between 0 and 6. Defaults to 0 to preserve the full zoom range.
  final double minZoom;

  /// Changes to this value animate the camera to the initial globe position.
  /// The widget remains mounted so loaded globe resources can be reused.
  final int resetToken;

  /// Custom markers (widgets, assets, or fallback dots) plotted on the map and globe.
  final List<MarkerOptions> markers;

  /// Labelled points plotted on the globe.
  @Deprecated('Use markers instead')
  final List<GlobePoint> points;

  /// Declarative popups on the map and globe.
  final List<PopupOptions> popups;

  final List<GlobeArc> arcs;

  /// Heatmap layers rendered on the globe canvas.
  final List<HeatmapOptions> heatmaps;

  final bool atmosphere;
  final GoodControls controls;

  /// Globe zoom at which it hands off to the flat map.
  final double globeZoomToFlat;

  /// Flat-map zoom below which it hands back to the globe.
  final double flatZoomToGlobe;

  /// Flat-map zoom the map mounts at when entering from the globe.
  final double flatEntryZoom;

  /// Globe zoom the globe mounts at when returning from the flat map.
  final double globeEntryZoom;

  final Duration transition;

  /// Tapped coordinate on the globe surface (globe mode only).
  final void Function(LatLng? coordinate)? onTap;

  /// Called when the surface flips (true = flat map, false = globe).
  final void Function(bool isFlat)? onSurfaceChanged;

  /// When true, draws the dotted world landmass grid on the globe surface.
  final bool showDottedGrid;

  /// Colour of the dotted grid dots.
  final Color? dottedGridColor;

  /// Radius of each dot on the globe. Default: 1.2.
  final double dottedGridRadius;

  /// Enables the day/night terminator on the globe surface.
  final DateTime? dateTime;

  /// Explicit subsolar point (lat/lng) for the day/night terminator.
  final LatLng? sunPosition;

  /// Time range `(start, end)` to filter markers and arcs on the globe.
  final (double, double)? timeRange;
  final GoodBasemapConfig? basemapConfig;
  final void Function(Object error)? onBasemapError;

  @override
  State<GoodMapGlobe> createState() => _GoodMapGlobeState();
}

class _GoodMapGlobeState extends State<GoodMapGlobe> {
  late LatLng _center = widget.initialCenter;
  late double _globeStartZoom = widget.initialZoom;
  int _globeCameraToken = 0;
  bool _globeCameraResetting = false;
  bool _flat = false;

  @override
  void didUpdateWidget(GoodMapGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _center = widget.initialCenter;
      _globeStartZoom = widget.initialZoom;
      _globeCameraResetting = true;
      _globeCameraToken++;
      _flat = false;
      widget.onSurfaceChanged?.call(false);
    }
  }

  void _setFlat(bool flat) {
    if (_flat == flat) return;
    setState(() {
      _flat = flat;
      if (!flat) {
        _globeStartZoom = widget.globeEntryZoom;
        _globeCameraResetting = true;
        _globeCameraToken++;
      }
    });
    widget.onSurfaceChanged?.call(flat);
  }

  @override
  Widget build(BuildContext context) {
    final globe = GoodGlobe(
      key: const ValueKey('globe'),
      initialCenter: _center,
      initialZoom: _globeStartZoom,
      minZoom: widget.minZoom,
      resetToken: _globeCameraToken,
      markers: widget.markers,
      points: widget.points,
      popups: widget.popups,
      arcs: widget.arcs,
      heatmaps: widget.heatmaps,
      atmosphere: widget.atmosphere,
      onTap: widget.onTap,
      showDottedGrid: widget.showDottedGrid,
      dottedGridColor: widget.dottedGridColor,
      dottedGridRadius: widget.dottedGridRadius,
      dateTime: widget.dateTime,
      sunPosition: widget.sunPosition,
      timeRange: widget.timeRange,
      basemapConfig: widget.basemapConfig,
      onBasemapError: widget.onBasemapError,
      onCameraResetEnd: () => _globeCameraResetting = false,
      onCameraChanged: (center, zoom) {
        _center = center;
        if (!_globeCameraResetting && zoom >= widget.globeZoomToFlat) {
          _setFlat(true);
        }
      },
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !_flat,
          child: IgnorePointer(ignoring: _flat, child: globe),
        ),
        IgnorePointer(
          ignoring: !_flat,
          child: AnimatedSwitcher(
            duration: widget.transition,
            child:
                _flat
                    ? GoodMap(
                      key: const ValueKey('flat'),
                      initialCenter: _center,
                      initialZoom: widget.flatEntryZoom,
                      controls: widget.controls,
                      markers: widget.markers,
                      popups: widget.popups,
                      basemapConfig: widget.basemapConfig,
                      onBasemapError: widget.onBasemapError,
                      onCameraChanged: (pos) {
                        _center = pos.target;
                        if (pos.zoom < widget.flatZoomToGlobe) {
                          _setFlat(false);
                        }
                      },
                    )
                    : const SizedBox.expand(key: ValueKey('flat-placeholder')),
          ),
        ),
      ],
    );
  }
}
