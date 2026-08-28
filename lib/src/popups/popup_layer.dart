// lib/src/popups/popup_layer.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../good_map_controller.dart' show OverlayEntryData;

/// Projects geographically-anchored overlay entries onto screen offsets and
/// positions each in the enclosing [Stack]. Re-projects whenever [entries] or
/// [cameraVersion] changes. Off-screen entries are placed far out of view
/// rather than removed, to avoid flicker during gestures.
class GoodOverlayLayer extends StatefulWidget {
  const GoodOverlayLayer({
    required this.native,
    required this.entries,
    required this.cameraVersion,
    super.key,
  });

  final MapLibreMapController native;
  final List<OverlayEntryData> entries;
  final int cameraVersion;

  @override
  State<GoodOverlayLayer> createState() => _GoodOverlayLayerState();
}

class _GoodOverlayLayerState extends State<GoodOverlayLayer> {
  Map<Object, Offset> _offsets = <Object, Offset>{};
  bool _reprojecting = false;
  bool _reprojectPending = false;
  int _reprojectGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleReproject();
  }

  @override
  void didUpdateWidget(GoodOverlayLayer old) {
    super.didUpdateWidget(old);
    if (old.cameraVersion != widget.cameraVersion ||
        old.entries != widget.entries) {
      _scheduleReproject();
    }
  }

  void _scheduleReproject() {
    _reprojectGeneration++;
    _reprojectPending = true;
    if (!_reprojecting) unawaited(_drainReprojections());
  }

  Future<void> _drainReprojections() async {
    _reprojecting = true;
    while (mounted && _reprojectPending) {
      _reprojectPending = false;
      await _reprojectOnce(_reprojectGeneration);
    }
    _reprojecting = false;
  }

  Future<void> _reprojectOnce(int generation) async {
    // `toScreenLocation` returns physical pixels on Android but logical points
    // on iOS; `Positioned` is logical, so scale Android down by the DPR.
    final divisor = defaultTargetPlatform == TargetPlatform.android
        ? MediaQuery.of(context).devicePixelRatio
        : 1.0;
    final entries = widget.entries;
    if (entries.isEmpty) {
      if (mounted && generation == _reprojectGeneration) {
        setState(() => _offsets = <Object, Offset>{});
      }
      return;
    }

    late final List<Point> points;
    try {
      points = await widget.native.toScreenLocationBatch(
        entries.map((entry) => entry.position),
      );
    } catch (_) {
      // Projection can fail transiently mid-gesture. A pending camera update
      // will retry with the latest position.
      return;
    }

    // Drop the result if the camera or entries changed while awaiting the
    // platform channel. The drain loop will immediately project the latest.
    if (!mounted || generation != _reprojectGeneration) return;

    final next = <Object, Offset>{};
    final count = min(entries.length, points.length);
    for (var index = 0; index < count; index++) {
      final point = points[index];
      next[entries[index].key] = Offset(
        point.x.toDouble() / divisor,
        point.y.toDouble() / divisor,
      );
    }
    setState(() => _offsets = next);
  }

  // Fraction of child size to shift so [alignment] sits on the screen offset.
  Offset _anchorFraction(Alignment a) => Offset(-(a.x + 1) / 2, -(a.y + 1) / 2);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final e in widget.entries)
          if (_offsets.containsKey(e.key))
            Positioned(
              left: _offsets[e.key]!.dx,
              top: _offsets[e.key]!.dy,
              child: FractionalTranslation(
                translation: _anchorFraction(e.alignment),
                child: e.onTap == null
                    ? e.child
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: e.onTap,
                        child: e.child,
                      ),
              ),
            ),
      ],
    );
  }
}
