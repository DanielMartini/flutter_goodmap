// lib/src/good_map.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'controls/controls.dart';
import 'good_map_controller.dart';
import 'lines/region.dart';
import 'popups/popup_layer.dart';
import 'theme/basemaps.dart';
import 'theme/carto_basemap_config.dart';
import 'theme/carto_style_loader.dart';
import 'theme/good_map_theme.dart';

export 'controls/controls.dart' show GoodControls;

/// Test seam: builds the native map view. Production uses [_defaultMapBuilder].
typedef GoodMapBuilder =
    Widget Function({
      required String styleString,
      required CameraPosition initialCameraPosition,
      required void Function(MapLibreMapController) onMapCreated,
      required void Function() onStyleLoaded,
      required void Function(CameraPosition) onCameraMove,
    });

/// A theme-aware map with overlay markers/popups and zoom/compass controls.
class GoodMap extends StatefulWidget {
  const GoodMap({
    required this.initialCenter,
    this.onMapReady,
    this.onCameraChanged,
    this.initialZoom = 11,
    this.controls = const GoodControls(),
    this.theme,
    this.markers = const [],
    this.popups = const [],
    this.regions = const [],
    this.locale,
    this.waterColor,
    this.basemapConfig,
    this.onBasemapError,
    this.mapBuilder,
    super.key,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final GoodControls controls;
  final GoodMapTheme? theme;
  final void Function(GoodMapController)? onMapReady;
  final List<MarkerOptions> markers;
  final List<PopupOptions> popups;
  final List<GoodMapRegionOptions> regions;

  /// Locale used for CARTO vector labels.
  ///
  /// Defaults to the nearest [Localizations] locale. Labels fall back to their
  /// native name and then English when the requested translation is missing.
  final Locale? locale;

  /// Optional fill colour applied to the CARTO water layer.
  final Color? waterColor;

  final GoodBasemapConfig? basemapConfig;
  final void Function(Object error)? onBasemapError;

  /// Called on camera moves with the current position (target + zoom).
  final void Function(CameraPosition)? onCameraChanged;
  final GoodMapBuilder? mapBuilder;

  @override
  State<GoodMap> createState() => _GoodMapState();
}

class _DeclarativeRegionPart {
  const _DeclarativeRegionPart(this.id, this.options);

  final PolygonId id;
  final PolygonOptions options;
}

class _GoodMapState extends State<GoodMap> {
  MapLibreMapController? _native;
  GoodMapController? _controller;
  int _cameraVersion = 0;
  bool _readyCalled = false;
  final http.Client _basemapClient = http.Client();
  late final CartoStyleLoader _styleLoader = CartoStyleLoader(
    client: _basemapClient,
    shareCompleted: true,
  );
  Future<String>? _styleFuture;
  String? _styleLoadKey;

  final Set<MarkerId> _declarativeMarkerIds = {};
  final Set<PopupId> _declarativePopupIds = {};
  final Map<String, _DeclarativeRegionPart> _declarativeRegionParts = {};
  Map<String, PolygonOptions> _desiredRegionParts = const {};
  int _regionSyncGeneration = 0;

  void _syncMarkers() {
    final c = _controller;
    if (c == null) return;
    for (final id in _declarativeMarkerIds) {
      c.removeMarker(id);
    }
    _declarativeMarkerIds.clear();
    for (final marker in widget.markers) {
      final id = c.addMarker(marker);
      _declarativeMarkerIds.add(id);
    }
  }

  void _syncPopups() {
    final c = _controller;
    if (c == null) return;
    for (final id in _declarativePopupIds) {
      c.hidePopup(id);
    }
    _declarativePopupIds.clear();
    for (final popup in widget.popups) {
      final id = c.showPopup(
        popup.position,
        popup.child,
        alignment: popup.alignment,
      );
      _declarativePopupIds.add(id);
    }
  }

  Future<void> _syncRegions() async {
    final c = _controller;
    if (c == null) return;

    final desired = <String, PolygonOptions>{};
    for (final region in widget.regions) {
      for (var index = 0; index < region.polygons.length; index++) {
        final polygon = region.polygons[index];
        desired['${region.id}:$index'] = PolygonOptions(
          points: polygon.outerRing,
          holes: polygon.holes,
          color: region.fillColor,
          opacity: region.fillOpacity,
          outlineColor: region.outlineColor,
        );
      }
    }

    final generation = ++_regionSyncGeneration;
    _desiredRegionParts = desired;

    for (final entry in _declarativeRegionParts.entries.toList()) {
      final next = desired[entry.key];
      if (next == null || !_samePolygonOptions(entry.value.options, next)) {
        c.removePolygon(entry.value.id);
        _declarativeRegionParts.remove(entry.key);
      }
    }

    for (final entry in desired.entries) {
      if (_declarativeRegionParts.containsKey(entry.key)) continue;
      final id = await c.addPolygonAsync(entry.value);
      final current = _desiredRegionParts[entry.key];
      if (!mounted ||
          generation != _regionSyncGeneration ||
          current == null ||
          !_samePolygonOptions(current, entry.value)) {
        c.removePolygon(id);
        continue;
      }
      _declarativeRegionParts[entry.key] = _DeclarativeRegionPart(
        id,
        entry.value,
      );
    }
  }

  bool _samePolygonOptions(PolygonOptions a, PolygonOptions b) {
    return a.color == b.color &&
        a.opacity == b.opacity &&
        a.outlineColor == b.outlineColor &&
        _sameRing(a.points, b.points) &&
        _sameHoles(a.holes, b.holes);
  }

  bool _sameRing(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].latitude != b[index].latitude ||
          a[index].longitude != b[index].longitude) {
        return false;
      }
    }
    return true;
  }

  bool _sameHoles(List<List<LatLng>>? a, List<List<LatLng>>? b) {
    final first = a ?? const <List<LatLng>>[];
    final second = b ?? const <List<LatLng>>[];
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_sameRing(first[index], second[index])) return false;
    }
    return true;
  }

  void _onMapCreated(MapLibreMapController native) {
    if (_controller != null) return; // idempotent: ignore re-fires
    setState(() {
      _native = native;
      _controller = GoodMapController(native)..addListener(_onOverlayChanged);
    });
  }

  void _onOverlayChanged() => setState(() {});

  Future<void> _onStyleLoaded() async {
    if (!_readyCalled) {
      _readyCalled = true;
      _syncMarkers();
      _syncPopups();
      await _syncRegions();
      if (!mounted) return;
      widget.onMapReady?.call(_controller!);
    } else {
      // Theme changed mid-session: GL-scene objects (symbols + lines) must be
      // re-applied to the new style.
      _controller!.reapplyGlObjects();
    }
  }

  void _onCameraMove(CameraPosition position) {
    setState(() => _cameraVersion++);
    widget.onCameraChanged?.call(position);
  }

  @override
  void didUpdateWidget(GoodMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.basemapConfig != widget.basemapConfig ||
        oldWidget.locale != widget.locale ||
        oldWidget.waterColor != widget.waterColor) {
      _ensureStyleFuture(Theme.of(context).brightness, force: true);
    }
    if (_controller != null && _readyCalled) {
      if (oldWidget.markers != widget.markers) {
        _syncMarkers();
      }
      if (oldWidget.popups != widget.popups) {
        _syncPopups();
      }
      if (oldWidget.regions != widget.regions) {
        unawaited(_syncRegions());
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureStyleFuture(Theme.of(context).brightness);
  }

  void _ensureStyleFuture(Brightness brightness, {bool force = false}) {
    if (!_requiresStyleRewrite) {
      _styleFuture = null;
      _styleLoadKey = null;
      return;
    }
    final config = widget.basemapConfig ?? const GoodBasemapConfig();
    final locale = widget.locale ?? Localizations.localeOf(context);
    final languageCode = _mapLabelLanguage(locale);
    final waterColor =
        widget.waterColor == null ? null : _mapStyleColor(widget.waterColor!);
    final key =
        '${brightness.name}|${config.lightStyleUrl}|'
        '${config.darkStyleUrl}|${cartoApiKeyFingerprint(config.cartoApiKey ?? '')}|'
        '${config.requireApiKey}|$languageCode|${waterColor ?? ''}';
    if (!force && key == _styleLoadKey) return;
    _styleLoadKey = key;
    _styleFuture = _loadStyle(brightness, config, languageCode, waterColor);
  }

  Future<String> _loadStyle(
    Brightness brightness,
    GoodBasemapConfig config,
    String languageCode,
    String? waterColor,
  ) async {
    try {
      return await _styleLoader.load(
        brightness,
        config,
        languageCode: languageCode,
        waterColor: waterColor,
      );
    } catch (error) {
      if (mounted) widget.onBasemapError?.call(error);
      rethrow;
    }
  }

  @override
  void dispose() {
    _regionSyncGeneration++;
    _desiredRegionParts = const {};
    _controller?.removeListener(_onOverlayChanged);
    _controller?.dispose();
    _basemapClient.close();
    super.dispose();
  }

  Widget _buildMap(BuildContext context, String style) {
    final scheme = Theme.of(context).colorScheme;
    final theme = widget.theme ?? GoodMapTheme.fromColorScheme(scheme);

    return Stack(
      fit: StackFit.expand,
      children: [
        (widget.mapBuilder ?? _defaultMapBuilder)(
          styleString: style,
          initialCameraPosition: CameraPosition(
            target: widget.initialCenter,
            zoom: widget.initialZoom,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
          onCameraMove: _onCameraMove,
        ),
        if (_native != null && _controller != null)
          GoodOverlayLayer(
            native: _native!,
            entries: _controller!.overlayEntries,
            cameraVersion: _cameraVersion,
          ),
        if (_native != null)
          GoodControlsView(
            native: _native!,
            config: widget.controls,
            theme: theme,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (!_requiresStyleRewrite) {
      return _buildMap(context, basemapStyleFor(brightness));
    }
    final future = _styleFuture;
    if (future == null) {
      return ColoredBox(color: _placeholderColor(context));
    }
    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        final style = snapshot.data;
        if (style != null) return _buildMap(context, style);
        return ColoredBox(color: _placeholderColor(context));
      },
    );
  }

  /// Shown while the style is still loading. Uses the water colour when the
  /// host provided one so the wait blends into the map instead of flashing the
  /// surface grey.
  Color _placeholderColor(BuildContext context) =>
      widget.waterColor ?? Theme.of(context).colorScheme.surface;

  bool get _requiresStyleRewrite =>
      widget.basemapConfig != null ||
      widget.locale != null ||
      widget.waterColor != null;
}

String _mapLabelLanguage(Locale locale) {
  if (locale.languageCode.toLowerCase() == 'sr' &&
      locale.scriptCode?.toLowerCase() == 'latn') {
    return 'sr-Latn';
  }
  return locale.languageCode.toLowerCase();
}

String _mapStyleColor(Color color) {
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

Widget _defaultMapBuilder({
  required String styleString,
  required CameraPosition initialCameraPosition,
  required void Function(MapLibreMapController) onMapCreated,
  required void Function() onStyleLoaded,
  required void Function(CameraPosition) onCameraMove,
}) {
  return MapLibreMap(
    styleString: styleString,
    initialCameraPosition: initialCameraPosition,
    trackCameraPosition: true,
    compassEnabled: false, // we render our own compass control
    onMapCreated: onMapCreated,
    onStyleLoadedCallback: onStyleLoaded,
    onCameraMove: onCameraMove,
  );
}
