# Changelog

## 0.7.0

### Declarative regions
- Added geography-agnostic `GoodMapRegionOptions` and `GoodMapRegionPolygon` models with MultiPolygon and hole support.
- `GoodMap.regions` now diffs stable region-part IDs, reapplies fills after style reloads, and removes stale asynchronous fills.
- `GoodMapGlobe` now forces the flat surface while regions are active, frames `focusBounds` once per `focusToken`, and restores the prior surface and camera when regions are cleared.

### Globe
- Added configurable `minZoom` support to `GoodGlobe` and `GoodMapGlobe`. The default remains `0.0` for backward compatibility.
- Added `GoodGlobe.cameraResetDuration` (default 350ms). `Duration.zero` applies the `resetToken` camera in the same frame instead of animating.

### Hybrid (`GoodMapGlobe`) — smoother globe -> map handoff
- **No more flicker on the way in.** The blackout is now held until the native map has loaded its style *and* composited a first frame, instead of fading out one frame after mounting it. That removed the grey flash, the brief reappearance of the globe through the not-yet-painted platform view, and the pop-in of the map.
- **Matching zoom across surfaces.** `flatEntryZoom`, `globeEntryZoom` and `flatZoomToGlobe` are now `double?` and default to `null` = automatic: each surface mounts at the zoom whose on-screen ground scale matches the one it replaces, so the handoff no longer jumps (the old fixed `flatEntryZoom: 5.0` was ~1.6 zoom levels past the `globeZoomToFlat: 3.5` handoff on a phone-sized viewport). Passing explicit values keeps the previous behaviour.
- The flat -> globe threshold derives from `globeZoomToFlat` with a hysteresis margin, so the two surfaces can't ping-pong at the boundary.
- The globe camera now snaps (rather than animating) when returning from the flat map, since that move happens behind the blackout.
- The globe is hidden, and an opaque water-coloured backdrop sits under the native map, while the flat surface is active.
- `GoodMap` paints its `waterColor` instead of the theme surface colour while the basemap style is still loading.
- The CARTO style JSON is cached process-wide once it has loaded, so a remounted `GoodMap` (every globe -> flat handoff) no longer refetches it before it can paint.

## 0.6.0

Web Support.

### Flutter Web
- **Web Support**: The `goodmap` package now fully supports Flutter Web! Both the native MapLibre flat map and the 3D `ui.FragmentProgram` globe have been updated to run efficiently in the browser.
- **Cross-platform Tile Fetching**: Replaced `dart:io` `HttpClient` with `package:http` in the globe's tile fetching logic, enabling it to compile and run on the web.
## 0.4.0

Data visualization & richness.

### Dotted World Map ("pointed map")
- **`GoodGlobe.showDottedGrid`** — draws a stylized dotted landmass grid (1,710 pre-computed points from a diagonal dot-map grid) on the globe canvas using `GlobeOverlayPainter`. Configurable dot colour (`dottedGridColor`) and radius (`dottedGridRadius`).
- **`GoodMapGlobe.showDottedGrid`** — threads the same props through the hybrid globe→flat widget.
- **`world_land_dots.dart`** — internal file with the pre-compiled `kWorldLandDots` constant; generated with `dotted-map` (height: 45, diagonal grid).

### Heatmaps
- **`GoodMapController.addHeatmap(HeatmapOptions)`** — adds a heatmap layer backed by a native MapLibre `heatmap` paint layer on a generated GeoJSON source. Returns a `HeatmapId`.
- **`updateHeatmap`**, **`removeHeatmap`**, **`clearHeatmaps`** — full lifecycle management.
- **`HeatmapOptions`** — points, per-point weights, radius, intensity, opacity, and custom gradient ramp.
- **`HeatmapId`** — opaque typed handle.

### 3D Building Extrusions (flat map)
- **`GoodMapController.enableBuildings3D()`** / **`disableBuildings3D()`** — inserts a native `fill-extrusion` layer on the `building` source layer using height/min_height fields from the active basemap, re-applied automatically after theme changes.

### Polygons & Circles (flat map)
- **`GoodMapController.addPolygon(PolygonOptions)`** — draws a filled polygon on the map with outer rings and optional inner rings (holes) using native fills. Returns a `PolygonId`.
- **`GoodMapController.addCircle(CircleOptions)`** — draws a circular area scaling with zoom (approximated as a regular polygon with geodesic calculations). Returns a `CircleId`.
- **`removePolygon`**, **`clearPolygons`**, **`removeCircle`**, **`clearCircles`** — full lifecycle management for polygon and circle layers.

## 0.3.0


Windowed Per-Region Level of Detail (LOD) on the 3D globe.

### 3D Globe
- **Windowed LOD System**: Added dynamic viewport-bound calculation and tile fetching (up to z12 city level) only for the visible portion of the globe when zoom > 3.0.
- **Background Reprojection**: Compiled tiles into local mosaics reprojected Mercator→equirectangular in a background isolate (`compute`) to eliminate main thread jank.
- **Atmosphere Shader Integration**: Upgraded the sphere fragment shader (`shaders/sphere.frag`) and painter (`SphereShaderPainter`) to overlay dynamic high-resolution detail textures seamlessly with meridian-wrapping calculations.
- **Lifecycle & Gestures Throttling**: Added a 250ms debounce for loading high-res details when the camera remains stationary, resetting builder tasks during active dragging, pinch-zooms, and inertial scrolling to maintain smooth 60fps interaction.

## 0.2.0

Shared overlay vocabulary unifying flat map and globe marker/popup types.

### Overlays
- **Shared overlay vocabulary**: Unified `MarkerOptions` and `PopupOptions` across `GoodMap`, `GoodGlobe`, and `GoodMapGlobe` to enable seamless transition and reuse of overlays.
- Deprecated `GlobePoint` in favor of `MarkerOptions` while keeping a backwards-compatible `GlobePoint` subclass.
- Added support for declarative `markers` and `popups` list parameters directly to `GoodMap` and `GoodMapGlobe` constructors, which synchronize dynamically with the underlying `GoodMapController`.
- Project and render interactive custom widget and image asset markers on the 3D globe stack.
- Retained custom high-performance canvas path for simple dot markers on the globe.

## 0.1.0

Initial release. Two map surfaces, inspired by mapcn.

### Flat map — `GoodMap`
- Theme-aware CARTO basemaps (positron / dark-matter) by `Theme` brightness.
- `GoodMapController`: camera (`flyTo` / `animateTo` / `fitBounds` / `moveTo`),
  overlay-widget and asset GL-symbol markers, overlay popups, and polylines /
  great-circle routes.
- Zoom + compass controls; `GoodMapTheme` tokens derived from the `ColorScheme`.

### Globe — `GoodGlobe`
- Native 3D globe rendered with a single `ui.FragmentProgram` orthographic sphere
  shader (no `flutter_gpu`); works on iOS, Android, web and desktop.
- Theme-aware CARTO raster basemap reprojected Mercator→equirectangular in a
  background isolate.
- Inertial drag-rotate, pinch-zoom, and `onTap` → lat/lng.
- `GlobePoint` (dot + label) and `GlobeArc` (great-circle, bowed, animated
  marching dashes) with back-of-globe occlusion; tap a point for a popup.
- Opt-in atmosphere glow (`atmosphere: true`).

### Hybrid — `GoodMapGlobe`
- A globe that becomes a street map: shows `GoodGlobe` at world/regional zoom,
  then cross-fades to the native `GoodMap` (full vector streets/cities) past a
  zoom threshold, and back. The centre coordinate carries across.
