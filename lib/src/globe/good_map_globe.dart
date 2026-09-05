import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng, LatLngBounds;

import '../good_map.dart';
import '../good_map_controller.dart' show GoodMapController;
import '../heatmap/heatmap.dart';
import '../lines/region.dart';
import '../markers/marker.dart';
import '../popups/popup.dart';
import '../theme/carto_basemap_config.dart';
import 'globe_overlays.dart';
import 'good_globe.dart';
import 'sphere_projection.dart';

/// A globe that becomes a street map when you zoom in.
///
/// Shows a [GoodGlobe] (world/regional view, with arcs + points) at low zoom,
/// then fades through black to the native [GoodMap] — full vector streets and
/// cities — once you pinch past [globeZoomToFlat]. Zooming the flat map back out
/// below [flatZoomToGlobe] returns to the globe. Centre *and* scale carry
/// across: by default each surface mounts at the zoom that matches the other's
/// on-screen ground scale, so the handoff has no visible jump.
///
/// The blackout is held until the incoming surface has actually painted — the
/// native map needs its style plus a first composited frame — so the fade never
/// reveals a half-built map.
class GoodMapGlobe extends StatefulWidget {
  const GoodMapGlobe({
    required this.initialCenter,
    this.initialZoom = 1.0,
    this.minZoom = 0.0,
    this.resetToken = 0,
    this.cameraResetCurve = Curves.easeInOut,
    this.cameraResetDuration = const Duration(milliseconds: 350),
    this.markers = const [],
    this.regions = const [],
    this.focusBounds,
    this.focusToken,
    this.focusPadding = const EdgeInsets.all(40),
    @Deprecated('Use markers instead') this.points = const [],
    this.popups = const [],
    this.arcs = const [],
    this.heatmaps = const [],
    this.atmosphere = false,
    this.atmosphereColor,
    this.atmosphereGlowIntensity = 1.0,
    this.controls = const GoodControls(),
    this.globeZoomToFlat = 3.5,
    this.flatZoomToGlobe,
    this.flatEntryZoom,
    this.globeEntryZoom,
    this.transition = const Duration(milliseconds: 280),
    this.onTap,
    this.onSurfaceChanged,
    this.showDottedGrid = false,
    this.dottedGridColor,
    this.dottedGridRadius = 1.2,
    this.dateTime,
    this.sunPosition,
    this.timeRange,
    this.locale,
    this.waterColor,
    this.basemapConfig,
    this.onBasemapError,
    @visibleForTesting this.mapBuilder,
    super.key,
  }) : assert(minZoom >= 0.0 && minZoom <= 6.0),
       assert(atmosphereGlowIntensity >= 0.0 && atmosphereGlowIntensity <= 2.0);

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

  /// Curve used when [resetToken] returns the globe camera to its initial state.
  final Curve cameraResetCurve;

  /// Duration of the [resetToken] globe camera animation. Surface handoffs
  /// always snap the globe camera instead, since they happen behind the
  /// blackout.
  final Duration cameraResetDuration;

  /// Custom markers (widgets, assets, or fallback dots) plotted on the map and globe.
  final List<MarkerOptions> markers;

  /// Generic polygon regions rendered on the flat surface.
  final List<GoodMapRegionOptions> regions;

  /// Bounds framed after the flat surface and region fills are ready.
  final LatLngBounds? focusBounds;

  /// A changed token requests one new [focusBounds] fit.
  final Object? focusToken;

  final EdgeInsets focusPadding;

  /// Labelled points plotted on the globe.
  @Deprecated('Use markers instead')
  final List<GlobePoint> points;

  /// Declarative popups on the map and globe.
  final List<PopupOptions> popups;

  final List<GlobeArc> arcs;

  /// Heatmap layers rendered on the globe canvas.
  final List<HeatmapOptions> heatmaps;

  final bool atmosphere;

  /// Atmosphere colour; defaults to the theme's primary colour.
  final Color? atmosphereColor;

  /// Strength of the atmospheric glow from 0 (hidden) to 2 (double strength).
  /// A value of 1 preserves the default appearance.
  final double atmosphereGlowIntensity;

  final GoodControls controls;

  /// Globe zoom at which it hands off to the flat map.
  final double globeZoomToFlat;

  /// Flat-map zoom below which it hands back to the globe.
  ///
  /// Defaults to the flat-map equivalent of [globeZoomToFlat] minus a small
  /// hysteresis margin, so the two surfaces can't ping-pong at the boundary.
  /// Set it explicitly only if you also set [flatEntryZoom]: the two live in
  /// the same zoom space and an entry zoom below this threshold flips straight
  /// back to the globe.
  final double? flatZoomToGlobe;

  /// Flat-map zoom the map mounts at when entering from the globe.
  ///
  /// Defaults to the zoom whose ground scale matches the globe at the moment of
  /// the handoff, which is what keeps the transition from jumping.
  final double? flatEntryZoom;

  /// Globe zoom the globe mounts at when returning from the flat map.
  ///
  /// Defaults to the zoom whose ground scale matches the flat map at the moment
  /// of the handoff.
  final double? globeEntryZoom;

  /// Total duration of the fade-to-black surface transition.
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

  /// Locale used for labels when the flat map surface is active.
  /// Defaults to the nearest [Localizations] locale.
  final Locale? locale;

  /// Water colour used by the flat map. By default it matches the CARTO raster
  /// ocean colour used by the globe for the active theme.
  final Color? waterColor;

  final GoodBasemapConfig? basemapConfig;
  final void Function(Object error)? onBasemapError;

  @visibleForTesting
  final GoodMapBuilder? mapBuilder;

  @override
  State<GoodMapGlobe> createState() => _GoodMapGlobeState();
}

class _GoodMapGlobeState extends State<GoodMapGlobe>
    with SingleTickerProviderStateMixin {
  /// Gap between the globe->flat threshold and the flat->globe threshold, in
  /// flat-map zoom levels. Without it the matched entry zoom would sit right on
  /// the return threshold and the surfaces would ping-pong.
  static const double _handoffHysteresis = 0.6;

  /// How long the blackout waits for the native map before giving up. Only hit
  /// when the basemap style fails to load.
  static const Duration _flatReadyTimeout = Duration(seconds: 4);

  /// `onStyleLoaded` fires a beat before MapLibre's first composited frame
  /// reaches the Flutter scene; revealing earlier shows a blank native view.
  static const Duration _flatFirstFrameDelay = Duration(milliseconds: 120);

  late LatLng _center = widget.initialCenter;
  late double _globeStartZoom = widget.initialZoom;
  late double _globeZoom = widget.initialZoom;
  late final AnimationController _surfaceTransition = AnimationController(
    vsync: this,
    duration: widget.transition,
  );
  int _globeCameraToken = 0;
  bool _globeCameraResetting = false;
  bool _globeCameraSnap = false;
  bool _surfaceTransitionInProgress = false;
  bool _flat = false;

  double _flatZoom = 0;
  double _flatEntryZoom = 0;
  double _flatReturnZoom = 0;
  double _shortSide = 0;
  Completer<void>? _flatReady;
  GoodMapController? _flatController;

  bool? _regionRestoreFlat;
  LatLng? _regionRestoreCenter;
  double? _regionRestoreGlobeZoom;
  double? _regionRestoreFlatZoom;
  int _regionModeGeneration = 0;
  Object? _lastFocusToken;
  bool _hasFocusedRegion = false;

  @override
  void initState() {
    super.initState();
    if (widget.regions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.regions.isNotEmpty) {
          unawaited(_enterRegionMode());
        }
      });
    }
  }

  @override
  void didUpdateWidget(GoodMapGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transition != widget.transition) {
      _surfaceTransition.duration = widget.transition;
    }
    if (oldWidget.resetToken != widget.resetToken) {
      _surfaceTransition.stop();
      _surfaceTransition.value = 0;
      _surfaceTransitionInProgress = false;
      _flatReady = null;
      _center = widget.initialCenter;
      _globeStartZoom = widget.initialZoom;
      _globeZoom = widget.initialZoom;
      _globeCameraResetting = true;
      _globeCameraSnap = false;
      _globeCameraToken++;
      _flat = widget.regions.isNotEmpty;
      widget.onSurfaceChanged?.call(_flat);
    }

    final hadRegions = oldWidget.regions.isNotEmpty;
    final hasRegions = widget.regions.isNotEmpty;
    if (!hadRegions && hasRegions) {
      unawaited(_enterRegionMode());
    } else if (hadRegions && !hasRegions) {
      unawaited(_exitRegionMode());
    } else if (hasRegions &&
        (oldWidget.focusToken != widget.focusToken ||
            oldWidget.focusBounds != widget.focusBounds)) {
      unawaited(_focusRegion());
    }
  }

  Future<void> _enterRegionMode() async {
    final generation = ++_regionModeGeneration;
    _regionRestoreFlat ??= _flat;
    _regionRestoreCenter ??= _center;
    _regionRestoreGlobeZoom ??= _globeZoom;
    _regionRestoreFlatZoom ??= _flatZoom;
    _hasFocusedRegion = false;
    _lastFocusToken = null;

    while (mounted && _surfaceTransitionInProgress) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted ||
        generation != _regionModeGeneration ||
        widget.regions.isEmpty) {
      return;
    }
    if (!_flat) await _setFlat(true);
    if (!mounted ||
        generation != _regionModeGeneration ||
        widget.regions.isEmpty) {
      return;
    }
    await _focusRegion();
  }

  Future<void> _exitRegionMode() async {
    final generation = ++_regionModeGeneration;
    _hasFocusedRegion = false;
    _lastFocusToken = null;

    // Let the mounted GoodMap receive the empty region list and synchronously
    // remove its fills before restoring the previous surface and camera.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _regionModeGeneration ||
        widget.regions.isNotEmpty) {
      return;
    }

    final restoreFlat = _regionRestoreFlat ?? false;
    final restoreCenter = _regionRestoreCenter ?? widget.initialCenter;
    final restoreGlobeZoom = _regionRestoreGlobeZoom ?? widget.initialZoom;
    final restoreFlatZoom = _regionRestoreFlatZoom ?? _flatZoom;

    if (restoreFlat) {
      _center = restoreCenter;
      _flatZoom = restoreFlatZoom;
      _flatEntryZoom = restoreFlatZoom;
      if (!_flat) {
        setState(() => _flat = true);
        widget.onSurfaceChanged?.call(true);
      }
      await _flatController?.moveTo(restoreCenter, zoom: restoreFlatZoom);
    } else {
      _surfaceTransition.stop();
      _surfaceTransition.value = 0;
      final surfaceChanged = _flat;
      setState(() {
        _surfaceTransitionInProgress = false;
        _center = restoreCenter;
        _globeStartZoom = restoreGlobeZoom;
        _globeZoom = restoreGlobeZoom;
        _globeCameraResetting = true;
        _globeCameraSnap = true;
        _globeCameraToken++;
        _flatReady = null;
        _flatController = null;
        _flat = false;
      });
      if (surfaceChanged) widget.onSurfaceChanged?.call(false);
    }

    _regionRestoreFlat = null;
    _regionRestoreCenter = null;
    _regionRestoreGlobeZoom = null;
    _regionRestoreFlatZoom = null;
  }

  Future<void> _focusRegion() async {
    final controller = _flatController;
    final bounds = widget.focusBounds;
    if (!_flat ||
        widget.regions.isEmpty ||
        controller == null ||
        bounds == null) {
      return;
    }
    if (_hasFocusedRegion && _lastFocusToken == widget.focusToken) return;
    _hasFocusedRegion = true;
    _lastFocusToken = widget.focusToken;
    await controller.fitBounds(bounds, padding: widget.focusPadding);
  }

  // --- Zoom continuity ------------------------------------------------------

  double get _viewportShortSide => _shortSide > 0 ? _shortSide : 400.0;

  /// Flat-map zoom to mount at, matching the globe's current ground scale.
  double _entryZoomForFlat() {
    final explicit = widget.flatEntryZoom;
    if (explicit != null) return explicit;
    return flatZoomForGlobeZoom(
      globeZoom: _globeZoom,
      shortSide: _viewportShortSide,
      latitude: _center.latitude,
    ).clamp(0.0, 22.0);
  }

  /// Flat-map zoom below which the globe takes over again.
  double _returnZoomForFlat() {
    final explicit = widget.flatZoomToGlobe;
    if (explicit != null) return explicit;
    return flatZoomForGlobeZoom(
          globeZoom: widget.globeZoomToFlat,
          shortSide: _viewportShortSide,
          latitude: _center.latitude,
        ) -
        _handoffHysteresis;
  }

  /// Globe zoom to return to, matching the flat map's current ground scale.
  double _entryZoomForGlobe() {
    final explicit = widget.globeEntryZoom;
    if (explicit != null) return math.max(explicit, widget.minZoom);
    return globeZoomForFlatZoom(
      flatZoom: _flatZoom,
      shortSide: _viewportShortSide,
      latitude: _center.latitude,
    ).clamp(widget.minZoom, 6.0);
  }

  // --- Surface handoff ------------------------------------------------------

  Future<void> _setFlat(bool flat) async {
    if (_flat == flat || _surfaceTransitionInProgress) return;
    setState(() => _surfaceTransitionInProgress = true);

    final phaseDuration = Duration(
      microseconds: widget.transition.inMicroseconds ~/ 2,
    );
    await _surfaceTransition.animateTo(
      1,
      duration: phaseDuration,
      curve: Curves.easeIn,
    );
    if (!mounted) return;

    if (flat) {
      _flatEntryZoom = _entryZoomForFlat();
      _flatReturnZoom = _returnZoomForFlat();
      _flatZoom = _flatEntryZoom;
      _flatReady = Completer<void>();
    }

    setState(() {
      _flat = flat;
      if (!flat) {
        _globeStartZoom = _entryZoomForGlobe();
        _globeCameraResetting = true;
        _globeCameraSnap = true;
        _globeCameraToken++;
        _flatReady = null;
      }
    });
    widget.onSurfaceChanged?.call(flat);

    // Hold the blackout until the incoming surface has really painted. The
    // native map has to load its style and composite a first frame; the globe
    // repaints synchronously and only needs the frame.
    if (flat && !await _awaitFlatReady()) return;
    if (!await _awaitFrame() || !await _awaitFrame()) return;

    await _surfaceTransition.animateBack(
      0,
      duration: phaseDuration,
      curve: Curves.easeOut,
    );
    if (mounted) {
      setState(() {
        _surfaceTransitionInProgress = false;
        _globeCameraSnap = false;
      });
    }
  }

  /// Waits for the native map's style, then for its first frame. Returns false
  /// if the widget went away while waiting.
  Future<bool> _awaitFlatReady() async {
    final ready = _flatReady;
    if (ready != null && !ready.isCompleted) {
      await ready.future.timeout(_flatReadyTimeout, onTimeout: () {});
      if (!mounted) return false;
    }
    await Future<void>.delayed(_flatFirstFrameDelay);
    return mounted;
  }

  Future<bool> _awaitFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    return mounted;
  }

  void _onFlatMapReady(GoodMapController controller) {
    _flatController = controller;
    final ready = _flatReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    unawaited(_focusRegion());
  }

  @override
  void dispose() {
    _surfaceTransition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waterColor =
        widget.waterColor ??
        _cartoGlobeWaterColor(Theme.of(context).brightness);

    final globe = GoodGlobe(
      key: const ValueKey('globe'),
      initialCenter: _center,
      initialZoom: _globeStartZoom,
      minZoom: widget.minZoom,
      resetToken: _globeCameraToken,
      cameraResetCurve: widget.cameraResetCurve,
      cameraResetDuration:
          _globeCameraSnap ? Duration.zero : widget.cameraResetDuration,
      markers: widget.markers,
      points: widget.points,
      popups: widget.popups,
      arcs: widget.arcs,
      heatmaps: widget.heatmaps,
      atmosphere: widget.atmosphere,
      atmosphereColor: widget.atmosphereColor,
      atmosphereGlowIntensity: widget.atmosphereGlowIntensity,
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
        _globeZoom = zoom;
        if (!_globeCameraResetting && zoom >= widget.globeZoomToFlat) {
          _setFlat(true);
        }
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          _shortSide = math.min(constraints.maxWidth, constraints.maxHeight);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            TickerMode(
              enabled: !_flat,
              child: IgnorePointer(
                ignoring: _flat,
                // Hidden rather than unmounted: the globe keeps its atlas and
                // shader, and can't bleed through the native view before its
                // first frame lands.
                child: Visibility(
                  visible: !_flat,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: globe,
                ),
              ),
            ),
            IgnorePointer(
              ignoring: !_flat,
              child:
                  _flat
                      ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Opaque floor under the platform view so nothing
                          // shows through while it composites its first frame.
                          ColoredBox(color: waterColor),
                          GoodMap(
                            key: const ValueKey('flat'),
                            initialCenter: _center,
                            initialZoom: _flatEntryZoom,
                            controls: widget.controls,
                            markers: widget.markers,
                            popups: widget.popups,
                            regions: widget.regions,
                            locale: widget.locale,
                            waterColor:
                                widget.mapBuilder == null ? waterColor : null,
                            basemapConfig: widget.basemapConfig,
                            onBasemapError: widget.onBasemapError,
                            mapBuilder: widget.mapBuilder,
                            onMapReady: _onFlatMapReady,
                            onCameraChanged: (pos) {
                              _center = pos.target;
                              _flatZoom = pos.zoom;
                              if (widget.regions.isEmpty &&
                                  pos.zoom < _flatReturnZoom) {
                                _setFlat(false);
                              }
                            },
                          ),
                        ],
                      )
                      : const SizedBox.expand(
                        key: ValueKey('flat-placeholder'),
                      ),
            ),
            IgnorePointer(
              ignoring: !_surfaceTransitionInProgress,
              child: FadeTransition(
                opacity: _surfaceTransition,
                child: const ColoredBox(
                  key: ValueKey('surface-transition-blackout'),
                  color: Colors.black,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Color _cartoGlobeWaterColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xff262626)
        : const Color(0xffd4dadc);
