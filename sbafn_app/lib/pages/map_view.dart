import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:project_sbafn/story/story_models.dart';

class MapView extends StatefulWidget {
  final String scenario;
  final int chapter;
  final CameraSpec? chapterCamera;
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
  final _dartDefineEnv = const String.fromEnvironment(
    'MAPTILER_KEY',
    defaultValue: '',
  );

  late final String _maptilerKey = _dartDefineEnv;

  late final String _styleUrl =
      'https://api.maptiler.com/maps/dataviz/style.json?key=$_maptilerKey';

  MapLibreMapController? _map;
  bool _styleReady = false;

  // --- Data & layers ---------------------------------------------------------
  static const String streetsSrcId = 'streets-src';
  static const String streetsLyrId = 'streets-lyr';
  static const String streetsSelLyrId = 'streets-selected';

  Map<String, dynamic>? _segmentsGeo; // parsed GeoJSON for picking
  String? _selectedSegId;

  static const _manila = LatLng(14.5995, 120.9842);

  // --- Cursor hover (clickable cue) ------------------------------------------
  final bool _hoverClickable = false;

  static const Map<String, String> _scenarioToEvt = {
    '30': 'EVT_01',
    '50': 'EVT_03',
    '100': 'EVT_06',
  };

  @override
  Widget build(BuildContext context) {
    assert(
      _maptilerKey.isNotEmpty,
      'MAPTILER_KEY is missing (.env or --dart-define).',
    );

    return MouseRegion(
      cursor: _hoverClickable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: MapLibreMap(
        styleString: _styleUrl,
        onMapCreated: (c) => _map = c,
        onStyleLoadedCallback: _onStyleLoaded,
        myLocationEnabled: false,
        initialCameraPosition: const CameraPosition(target: _manila, zoom: 12),
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: true,
        onMapClick: _onMapTap,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Style loaded → add sources/layers
  // ---------------------------------------------------------------------------
  Future<void> _onStyleLoaded() async {
    if (_map == null) return;

    await _addStreetsFromAsset(); // base colored layer

    // Selected overlay layer (above base layer). Start hidden via filter.
    await _map!.addLineLayer(
      streetsSrcId,
      streetsSelLyrId,
      const LineLayerProperties(
        lineColor: '#0EA5E9',
        lineWidth: 6.0,
        lineOpacity: 1.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await _setSelectedFilter(null);

    _styleReady = true;
    await _applyChapterCamera();
  }

  dynamic _streetColorExpr(String scenario) {
    final evt = _scenarioToEvt[scenario] ?? 'EVT_03';
    final tierProp = 'tier_$evt';
    final riskProp = 'risk_$scenario';
    final probProp = 'p_$evt';

    const low = '#7ED957';
    const med = '#F59E0B';
    const high = '#F56969';
    const miss = '#CBD5E1';

    return [
      'case',
      ['has', tierProp],
      [
        'match',
        [
          'downcase',
          [
            'to-string',
            ['get', tierProp],
          ],
        ],
        'low',
        low,
        'medium',
        med,
        'med',
        med,
        'high',
        high,
        miss,
      ],

      [
        'let',
        'raw',
        [
          'coalesce',
          [
            'to-number',
            ['get', riskProp],
          ],
          [
            'to-number',
            ['get', probProp],
          ],
          -1,
        ],
        [
          'case',
          [
            '<',
            ['var', 'raw'],
            0,
          ],
          miss, // no data
          [
            'step',
            // normalize raw to 0..1 if needed, clamp to [0,1]
            [
              'min',
              1,
              [
                'max',
                0,
                [
                  'case',
                  [
                    '>',
                    ['var', 'raw'],
                    1,
                  ],
                  [
                    '/',
                    ['var', 'raw'],
                    100.0,
                  ],
                  ['var', 'raw'],
                ],
              ],
            ],
            low, 0.33, med, 0.66, high,
          ],
        ],
      ],
    ];
  }

  Future<void> _addStreetsFromAsset() async {
    final raw = await rootBundle.loadString('mnl_segments_enriched.geojson');
    _segmentsGeo = json.decode(raw) as Map<String, dynamic>;

    await _map!.addSource(
      streetsSrcId,
      GeojsonSourceProperties(data: _segmentsGeo),
    );

    await _map!.addLineLayer(
      streetsSrcId,
      streetsLyrId,
      LineLayerProperties(
        lineColor: _streetColorExpr(widget.scenario),
        lineWidth: [
          'interpolate',
          ['linear'],
          ['zoom'],
          10,
          1.4,
          14,
          2.2,
          17,
          3.0,
        ],
        lineOpacity: 0.95,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
  }

  Future<void> _applyScenarioPaint() async {
    if (_map == null) return;
    final ids = await _map!.getLayerIds();
    if (!ids.contains(streetsLyrId)) return;

    await _map!.setLayerProperties(
      streetsLyrId,
      LineLayerProperties(lineColor: _streetColorExpr(widget.scenario)),
    );
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------
  Future<void> _onMapTap(math.Point<double> point, LatLng latLng) async {
    if (_map == null || !_styleReady) return;

    // Prefer the renderer for picking (fast). Falls back to your CPU scan if needed.
    try {
      final feats = await _map!.queryRenderedFeatures(point, [
        streetsLyrId,
      ], null);
      if (feats.isNotEmpty) {
        final f = feats.first;

        // Robustly get the segment id: prefer properties.seg_id, else properties.id, else feature id
        final props =
            (f.feature['properties'] as Map?)?.cast<String, dynamic>() ??
            const {};
        final segId =
            (props['seg_id'] ?? props['id'] ?? f.id)?.toString() ?? '';

        if (segId.isNotEmpty) {
          _selectedSegId = segId;
          await _setSelectedFilter(
            segId,
          ); // keep selection layer filtered to 1 feature

          // Optional: zoom/focus
          await _map!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15.5));

          // Let the parent show details
          widget.onFeatureSelected(
            props.isNotEmpty ? props : {'seg_id': segId},
          );
          return;
        }
      }
    } catch (_) {
      // Some plugin versions may not support queryRenderedFeatures—fall back.
    }

    // Fallback: your existing nearest-line scanner (kept for safety)
    final hit = _pickNearestFeature(latLng, maxMeters: 80.0);
    if (hit == null) {
      await _setSelectedFilter(null);
      _selectedSegId = null;
      return;
    }
    _selectedSegId = (hit['seg_id'] ?? hit['id'])?.toString();
    await _setSelectedFilter(_selectedSegId);
    await _map!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15.5));
    widget.onFeatureSelected(hit);
  }

  Future<void> _setSelectedFilter(String? segId) async {
    if (_map == null) return;
    final filter = (segId == null)
        ? [
            '==',
            ['get', 'seg_id'],
            '__none__',
          ] // matches nothing
        : [
            '==',
            ['get', 'seg_id'],
            segId,
          ];
    await _map!.setFilter(streetsSelLyrId, filter);
  }

  Map<String, dynamic>? _pickNearestFeature(
    LatLng p, {
    required double maxMeters,
  }) {
    if (_segmentsGeo?['type'] != 'FeatureCollection') return null;

    final feats =
        (_segmentsGeo?['features'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];

    double best = double.infinity;
    Map<String, dynamic>? bestProps;

    for (final f in feats) {
      final geom = (f['geometry'] as Map?)?.cast<String, dynamic>();
      if (geom == null) continue;

      final type = geom['type'] as String? ?? '';
      final props =
          (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};

      if (type == 'LineString') {
        final coords = (geom['coordinates'] as List?)?.cast<List>() ?? const [];
        _scanLineString(p, coords, props, (d, pr) {
          if (d < best) {
            best = d;
            bestProps = pr;
          }
        });
      } else if (type == 'MultiLineString') {
        final lines = (geom['coordinates'] as List?)?.cast<List>() ?? const [];
        for (final line in lines) {
          final coords = (line as List).cast<List>();
          _scanLineString(p, coords, props, (d, pr) {
            if (d < best) {
              best = d;
              bestProps = pr;
            }
          });
        }
      }
    }

    return (best <= maxMeters) ? bestProps : null;
  }

  void _scanLineString(
    LatLng p,
    List<List> coords,
    Map<String, dynamic> props,
    void Function(double d, Map<String, dynamic> props) onCandidate,
  ) {
    for (int i = 0; i < coords.length - 1; i++) {
      final a = _ll(coords[i]);
      final b = _ll(coords[i + 1]);
      final d = _pointToSegmentMeters(p, a, b);
      onCandidate(d, props);
    }
  }

  LatLng _ll(List c) =>
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());

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

  // ---------------------------------------------------------------------------
  // Scrollytelling camera
  // ---------------------------------------------------------------------------
  Future<void> _applyChapterCamera() async {
    if (_map == null || !_styleReady) return;

    if (widget.chapterCamera != null) {
      final cam = widget.chapterCamera!;
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
      return;
    }

    // Simple fallback
    if (widget.chapter == 0) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 12));
    } else if (widget.chapter == 2) {
      await _map!.animateCamera(CameraUpdate.newLatLngZoom(_manila, 15));
    }
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
