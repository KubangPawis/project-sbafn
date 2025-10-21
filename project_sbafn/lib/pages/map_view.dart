import 'dart:convert';
import 'dart:math' as math; // for min/max and Point
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  // IDs
  final String riskSourceId = 'risk';
  final String riskLayerId = 'risk-lines';
  final String boundarySourceId = 'manila-boundary';
  final String boundaryFillId = 'mnl-fill';
  final String boundaryLineId = 'mnl-line';

  static const _manila = LatLng(14.5995, 120.9842);

  // Demo FeatureCollection (unchanged)
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

  // step(get("risk_{s}"), green, 0.33, yellow, 0.66, red)
  dynamic _colorExpr(String s) => [
        'step',
        ['get', 'risk_$s'],
        '#22c55e',
        0.33,
        '#eab308',
        0.66,
        '#dc2626',
      ];

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _map = controller;

    await _addManilaBoundary();

    await _map!.addSource(riskSourceId, GeojsonSourceProperties(data: _demoRisk));
    await _map!.addLineLayer(
      riskSourceId,
      riskLayerId,
      const LineLayerProperties(
        lineWidth: 5,
        lineOpacity: 0.9,
      ),
    );

    // ❗ setPaintProperty → setLayerProperty
    await _map!.setLayerProperties(
      riskLayerId,
      LineLayerProperties(
        lineColor: _colorExpr(widget.scenario),
      ),
    );
  }

  Future<void> _addManilaBoundary() async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/search?city=Manila&country=Philippines&format=jsonv2&polygon_geojson=1&email=you@example.com';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return;
      final items = json.decode(res.body) as List<dynamic>;
      Map<String, dynamic>? admin = items.cast<Map<String, dynamic>>().firstWhere(
            (it) =>
                it['category'] == 'boundary' &&
                it['type'] == 'administrative' &&
                (it['display_name'] ?? '').toString().contains('City of Manila'),
            orElse: () => items.isNotEmpty ? (items.first as Map<String, dynamic>) : {},
          );
      if (admin == null || admin.isEmpty || admin['geojson'] == null) return;

      final feature = {
        'type': 'Feature',
        'geometry': admin['geojson'],
        'properties': <String, dynamic>{},
      };

      await _map!.addSource(boundarySourceId, GeojsonSourceProperties(data: feature));
      await _map!.addFillLayer(
        boundarySourceId,
        boundaryFillId,
        const FillLayerProperties(fillColor: '#000000', fillOpacity: 0.06),
      );
      await _map!.addLineLayer(
        boundarySourceId,
        boundaryLineId,
        const LineLayerProperties(lineColor: '#111111', lineWidth: 1.2),
      );

      // Fit bounds to exterior ring
      final geom = (feature['geometry'] as Map<String, dynamic>);
      final coords = (geom['type'] == 'Polygon'
              ? [geom['coordinates']]
              : geom['coordinates'])
          .expand((e) => e)
          .first as List<dynamic>;
      var sw = const LatLng(90, 180);
      var ne = const LatLng(-90, -180);
      for (final c in coords.cast<List<dynamic>>()) {
        final lat = (c[1] as num).toDouble();
        final lng = (c[0] as num).toDouble();
        sw = LatLng(math.min(sw.latitude, lat), math.min(sw.longitude, lng));
        ne = LatLng(math.max(ne.latitude, lat), math.max(ne.longitude, lng));
      }
      await _map!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: sw, northeast: ne),
          left: 40, top: 40, right: 40, bottom: 40,
        ),
      );
    } catch (_) {
      // ok to skip on wireframe
    }
  }

    Future<void> _applyScenarioPaint() async {
      if (_map == null) return;

      // Correct way to check if layer exists
      final allLayerIds = await _map!.getLayerIds();
      final hasLayer = allLayerIds.contains(riskLayerId);

      if (hasLayer) {
        // Your call to setLayerProperties is correct
        await _map!.setLayerProperties(
          riskLayerId,
          LineLayerProperties(
            lineColor: _colorExpr(widget.scenario),
          ),
        );
      }
    }

  Future<void> _applyChapterCamera() async {
    if (_map == null) return;
    if (widget.chapter == 0) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 12));
    } else if (widget.chapter == 2) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 15));
    }
  }

  // ❗ Use math.Point for the first argument
  Future<void> _onMapTap(math.Point<double> point, LatLng latLng) async {
    if (_map == null) return;
    final features = await _map!.queryRenderedFeatures(point, [riskLayerId], null);
    if (features.isEmpty) return;

    final first = features.first;
    final props = Map<String, dynamic>.from(first['properties'] as Map);
    widget.onFeatureSelected(props);

    await _map!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
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

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: 'https://demotiles.maplibre.org/style.json',
      onMapCreated: _onMapCreated,
      myLocationEnabled: false,
      initialCameraPosition: const CameraPosition(target: _manila, zoom: 12),
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      onMapClick: _onMapTap,
    );
  }
}
