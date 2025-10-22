import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:project_sbafn/story/story_models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MapView extends StatefulWidget {
  final String scenario;                 // "30" | "50" | "100"
  final int chapter;                     // index of the active chapter
  final CameraSpec? chapterCamera;       // camera to fly to for this chapter
  final ValueChanged<Map<String, dynamic>> onFeatureSelected;

  const MapView({
    super.key,
    required this.scenario,
    required this.chapter,
    required this.onFeatureSelected,
    this.chapterCamera,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late final String _maptilerKey =
      dotenv.env['MAPTILER_KEY'] ??
      const String.fromEnvironment('MAPTILER_KEY', defaultValue: '');

  late final String _styleUrl =
      'https://api.maptiler.com/maps/dataviz/style.json?key=$_maptilerKey';

  MapLibreMapController? _map;
  bool _styleReady = false;

  // --- NEW: Streets overlay ids ---
  static const String streetsSrcId = 'streets-src';
  static const String streetsLyrId = 'streets-layer';

  static const _manila = LatLng(14.5995, 120.9842);

  // Demo FeatureCollection (kept as-is)
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

  Map<String, dynamic> _riskData = _demoRisk;

  // Risk color ramp (kept as-is)
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
    assert(
      _maptilerKey.isNotEmpty,
      'MAPTILER_KEY is missing. Add it via .env or --dart-define.',
    );

    return MapLibreMap(
      styleString: _styleUrl,
      onMapCreated: (c) => _map = c,
      onStyleLoadedCallback: _onStyleLoaded,
      myLocationEnabled: false,
      initialCameraPosition: const CameraPosition(target: _manila, zoom: 12),
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      onMapClick: _onMapTap,
    );
  }

  Future<void> _onStyleLoaded() async {
    if (_map == null) return;

    // 1) Optional: hillshade (leave as placeholder)
    await _map!.addSource(
      'hillshade-src',
      const RasterSourceProperties(
        tiles: ['https://YOUR_HOST/tiles_hillshade/{z}/{x}/{y}.png'],
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

    // 2) NEW: draw all Manila streets (plain blue)
    await _addStreetsFromAsset('assets/mnl_segments.geojson');

    _styleReady = true;
    await _applyChapterCamera();
  }

  /// Load GeoJSON from assets and render it as blue lines.
  Future<void> _addStreetsFromAsset(String assetPath) async {
    if (_map == null) return;

    final raw = await rootBundle.loadString(assetPath);
    final geo = json.decode(raw) as Map<String, dynamic>;

    // Add as a source
    await _map!.addSource(
      streetsSrcId,
      GeojsonSourceProperties(data: geo),
    );

    // Draw it
    await _map!.addLineLayer(
      streetsSrcId,
      streetsLyrId,
      const LineLayerProperties(
        lineColor: '#2F6EA5',  // blue
        lineWidth: 2.0,
        lineOpacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      // belowLayerId: 'place-label', // use if your basemap has label layer ids you want to respect
    );
  }

  Future<void> _flyTo(CameraSpec cam) async {
    if (_map == null) return;
    await _map!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(cam.lat, cam.lng),
          zoom: cam.zoom,
          bearing: cam.bearing,
          tilt: cam.pitch,
        ),
      ),
      duration: Duration(milliseconds: cam.durationMs),
    );
  }

  // Recolor demo risk when scenario changes
  Future<void> _applyScenarioPaint() async {
    if (_map == null || !_styleReady) return;
    final ids = await _map!.getLayerIds();
  }

  // Camera per chapter – prefers provided camera
  Future<void> _applyChapterCamera() async {
    if (_map == null || !_styleReady) return;

    if (widget.chapterCamera != null) {
      await _flyTo(widget.chapterCamera!);
      return;
    }
    // Fallback demo
    if (widget.chapter == 0) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 12));
    } else if (widget.chapter == 2) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 15));
    }
  }

  // --- Picking (still uses demo risk features) ---
  Future<void> _onMapTap(math.Point<double> point, LatLng latLng) async {
    if (_map == null || !_styleReady) return;

    const tolMeters = 80.0;
    final props = _pickNearestFeature(latLng, maxMeters: tolMeters);
    if (props == null) return;

    widget.onFeatureSelected(props);
    await _map!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
  }

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

  LatLng _ll(List c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());

  double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    const double mPerDegLat = 111320.0;
    final double cosLat = math.cos(p.latitude * math.pi / 180.0);
    double x(num lon) => (lon - p.longitude) * mPerDegLat * cosLat;
    double y(num lat) => (lat - p.latitude) * mPerDegLat;

    final ax = x(a.longitude), ay = y(a.latitude);
    final bx = x(b.longitude), by = y(b.latitude);

    final vx = bx - ax, vy = by - ay;
    final wx = -ax, wy = -ay;

    final vv = vx * vx + vy * vy;
    final t = (vv == 0) ? 0.0 : ((wx * vx + wy * vy) / vv).clamp(0.0, 1.0);

    final cx = ax + t * vx, cy = ay + t * vy;
    return math.sqrt(cx * cx + cy * cy);
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.scenario != widget.scenario) {
      _applyScenarioPaint();
    }
    final chapterChanged = oldWidget.chapter != widget.chapter;
    final camChanged = oldWidget.chapterCamera != widget.chapterCamera;
    if (chapterChanged || camChanged) {
      _applyChapterCamera();
    }
  }
}
