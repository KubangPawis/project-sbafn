// lib/map_view.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class MapView extends StatefulWidget {
  final String scenario; // "30" | "50" | "100"
  final int chapter;     // 0..4
  final ValueChanged<Map<String, dynamic>> onFeatureSelected;

  const MapView({
    super.key,
    required this.scenario,
    required this.chapter,
    required this.onFeatureSelected,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  MapLibreMapController? _map;

  // Layer/source IDs
  static const String riskSourceId = 'risk';
  static const String riskLayerId  = 'risk-lines';

  static const _manila = LatLng(14.5995, 120.9842);

  // Demo FeatureCollection (same as before)
  static const Map<String, dynamic> _demoRisk = {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "properties": {
          "seg_id": "MNL_0001",
          "barangay": "669",
          "risk_30": 0.4,
          "risk_50": 0.72,
          "risk_100": 0.86,
          "HAND_m": 1.2,
          "slope_pct": 0.7,
          "dist_canal_m": 38,
          "road_class": "collector",
          "drain_density": 2
        },
        "geometry": {
          "type": "LineString",
          "coordinates": [
            [120.9818, 14.5838],
            [120.9868, 14.5839]
          ]
        }
      },
      {
        "type": "Feature",
        "properties": {
          "seg_id": "MNL_0002",
          "barangay": "720",
          "risk_30": 0.22,
          "risk_50": 0.48,
          "risk_100": 0.61,
          "HAND_m": 1.8,
          "slope_pct": 0.9,
          "dist_canal_m": 55,
          "road_class": "residential",
          "drain_density": 1
        },
        "geometry": {
          "type": "LineString",
          "coordinates": [
            [120.9868, 14.5839],
            [120.9895, 14.5869]
          ]
        }
      },
      {
        "type": "Feature",
        "properties": {
          "seg_id": "MNL_0003",
          "barangay": "721",
          "risk_30": 0.12,
          "risk_50": 0.24,
          "risk_100": 0.38,
          "HAND_m": 2.6,
          "slope_pct": 1.3,
          "dist_canal_m": 140,
          "road_class": "primary",
          "drain_density": 0.3
        },
        "geometry": {
          "type": "LineString",
          "coordinates": [
            [120.9792, 14.5888],
            [120.9836, 14.5908]
          ]
        }
      }
    ]
  };

  // Keep data in memory for picking
  Map<String, dynamic> _riskData = _demoRisk;

  // Color ramp expression: step(get("risk_{s}"), green, 0.33, yellow, 0.66, red)
  dynamic _colorExpr(String s) => [
        'step',
        ['get', 'risk_$s'],
        '#22c55e',
        0.33,
        '#eab308',
        0.66,
        '#dc2626',
      ];

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: 'https://demotiles.maplibre.org/style.json',
      onMapCreated: (c) => _map = c,
      onStyleLoadedCallback: _onStyleLoaded, // add after style is loaded
      myLocationEnabled: false,
      initialCameraPosition: const CameraPosition(target: _manila, zoom: 12),
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      onMapClick: _onMapTap,
    );
  }

  Future<void> _onStyleLoaded() async {
    // 1) HILLSHADE (pre-rendered PNG tiles)
    await _map!.addSource(
      'hillshade-src',
      RasterSourceProperties(
        tiles: const ['https://YOUR_HOST/tiles_hillshade/{z}/{x}/{y}.png'],
        tileSize: 256,
        minzoom: 8,
        maxzoom: 16,
      ),
    );
    await _map!.addRasterLayer(
      'hillshade-src',
      'hillshade',
      const RasterLayerProperties(rasterOpacity: 0.7),
    );

    // 2) STREETS (your existing code)
    await _map!.addSource(riskSourceId, GeojsonSourceProperties(data: _riskData));
    await _map!.addLineLayer(
      riskSourceId,
      riskLayerId,
      LineLayerProperties(
        lineColor: _colorExpr(widget.scenario),
        lineWidth: 10,
        lineOpacity: 0.95,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
  }


  // Recolor when scenario changes
  Future<void> _applyScenarioPaint() async {
    if (_map == null) return;
    final ids = await _map!.getLayerIds();
    if (!ids.contains(riskLayerId)) return;
    await _map!.setLayerProperties(
      riskLayerId,
      LineLayerProperties(lineColor: _colorExpr(widget.scenario)),
    );
  }

  // Camera per chapter
  Future<void> _applyChapterCamera() async {
    if (_map == null) return;
    if (widget.chapter == 0) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 12));
    } else if (widget.chapter == 2) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 15));
    }
  }

  // --- Reliable picking: ignore renderer queries; choose nearest line by distance ---
  Future<void> _onMapTap(math.Point<double> point, LatLng latLng) async {
    if (_map == null) return;

    // Fixed geographic tolerance (meters). 80–100 m is forgiving but still precise
    // for your small demo dataset; tweak if needed.
    const tolMeters = 80.0;

    final props = _pickNearestFeature(latLng, maxMeters: tolMeters);
    if (props == null) return;

    widget.onFeatureSelected(props);
    await _map!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
  }


  // Convert pixel tolerance to meters at given lat/zoom (Web Mercator)
  double _metersForPixels(double lat, double zoom, double pixels) {
    final metersPerPixel = 156543.03392 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, zoom);
    return metersPerPixel * pixels;
  }

  // Find nearest line segment within maxMeters; return its properties if found
  Map<String, dynamic>? _pickNearestFeature(LatLng p, {required double maxMeters}) {
    if (_riskData['type'] != 'FeatureCollection') return null;
    final List feats = (_riskData['features'] as List?) ?? const [];

    double best = double.infinity;
    Map<String, dynamic>? bestProps;

    for (final f in feats.cast<Map<String, dynamic>>()) {
      final geom = f['geometry'] as Map<String, dynamic>?;
      if (geom == null || geom['type'] != 'LineString') continue;
      final coords = (geom['coordinates'] as List?)?.cast<List>() ?? const [];

      for (int i = 0; i < coords.length - 1; i++) {
        final a = _ll(coords[i]);
        final b = _ll(coords[i + 1]);
        final d = _pointToSegmentMeters(p, a, b);
        if (d < best) {
          best = d;
          bestProps = (f['properties'] as Map).cast<String, dynamic>();
        }
      }
    }

    return (best <= maxMeters) ? bestProps : null;
  }

  // Convert [lon,lat] to LatLng
  LatLng _ll(List c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());

  // Distance from point P to line segment AB in meters (local equirectangular)
  double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    const double mPerDegLat = 111320.0;
    final double cosLat = math.cos(p.latitude * math.pi / 180.0);

    double x(num lon) => (lon - p.longitude) * mPerDegLat * cosLat;
    double y(num lat) => (lat - p.latitude) * mPerDegLat;

    final ax = x(a.longitude), ay = y(a.latitude);
    final bx = x(b.longitude), by = y(b.latitude);

    final vx = bx - ax, vy = by - ay;
    final wx = -ax,    wy = -ay;

    final vv = vx*vx + vy*vy;
    final t = (vv == 0) ? 0.0 : ((wx*vx + wy*vy) / vv).clamp(0.0, 1.0);

    final cx = ax + t*vx, cy = ay + t*vy; // closest point to P (which we set as origin)
    return math.sqrt(cx*cx + cy*cy);
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenario != widget.scenario) {
      _applyScenarioPaint();
    }
    if (oldWidget.chapter != widget.chapter) {
      _applyChapterCamera();
    }
  }
}
