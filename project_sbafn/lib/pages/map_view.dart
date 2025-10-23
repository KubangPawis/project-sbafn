import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:project_sbafn/story/story_models.dart';

import 'package:flutter/gestures.dart' show PointerHoverEvent;

class MapView extends StatefulWidget {
  final String scenario;                 // "30" | "50" | "100"
  final int chapter;                     // active chapter index
  final CameraSpec? chapterCamera;       // camera for scrollytelling
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
  // --- Style/Map -------------------------------------------------------------
  late final String _maptilerKey =
      dotenv.env['MAPTILER_KEY'] ??
      const String.fromEnvironment('MAPTILER_KEY', defaultValue: '');

  late final String _styleUrl =
      'https://api.maptiler.com/maps/dataviz/style.json?key=$_maptilerKey';

  MapLibreMapController? _map;
  bool _styleReady = false;

  // --- Data & layers ---------------------------------------------------------
  static const String streetsSrcId   = 'streets-src';
  static const String streetsLyrId   = 'streets-layer';
  static const String streetsSelLyrId = 'streets-selected';

  Map<String, dynamic>? _segmentsGeo; // parsed GeoJSON
  String? _selectedSegId;

  static const _manila = LatLng(14.5995, 120.9842);

  // --- Cursor Hover -----------------------------------------------------------

  bool _hoverClickable = false;
  bool _hoverBusy = false;

  @override
  Widget build(BuildContext context) {
    assert(_maptilerKey.isNotEmpty, 'MAPTILER_KEY is missing (.env or --dart-define).');
    return MouseRegion(                                 
      cursor: _hoverClickable? SystemMouseCursors.click : SystemMouseCursors.basic,
      onHover: _handleHover,                           
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

  Future<void> _handleHover(PointerHoverEvent e) async {
    if (_hoverBusy || _map == null || !_styleReady) return;
    _hoverBusy = true;
    try {
      final pt = math.Point<double>(e.localPosition.dx, e.localPosition.dy);
      final latLng = await _map!.toLatLng(pt); // <-- works on older versions
      final clickable = _pickNearestFeature(latLng, maxMeters: 20.0) != null;
      if (clickable != _hoverClickable) {
        setState(() => _hoverClickable = clickable);
      }
    } finally {
      _hoverBusy = false;
    }
  }


  Future<void> _onStyleLoaded() async {
    if (_map == null) return;

    // Add your segments (all blue)
    await _addStreetsFromAsset('assets/mnl_segments.geojson');

    // Selected overlay layer (initially matches nothing)
    await _map!.addLineLayer(
      streetsSrcId,
      streetsSelLyrId,
      const LineLayerProperties(
        lineColor: '#0EA5E9', // blue-accent
        lineWidth: 6.0,
        lineOpacity: 1.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await _setSelectedFilter(null);

    _styleReady = true;
    await _applyChapterCamera(); // let scrollytelling drive the camera initially
  }

  Future<void> _addStreetsFromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    _segmentsGeo = json.decode(raw) as Map<String, dynamic>;

    await _map!.addSource(
      streetsSrcId,
      GeojsonSourceProperties(
        data: _segmentsGeo!,
        // generateId: true, // not needed since we filter by seg_id
      ),
    );

    await _map!.addLineLayer(
      streetsSrcId,
      streetsLyrId,
      const LineLayerProperties(
        lineColor: '#2F6EA5',
        lineWidth: 2.0,
        lineOpacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
  }

  // --- Selection -------------------------------------------------------------

  Future<void> _onMapTap(math.Point<double> point, LatLng latLng) async {
    if (_map == null || !_styleReady || _segmentsGeo == null) return;

    // Find nearest segment (80 m tolerance is forgiving but practical)
    const tolMeters = 80.0;
    final hit = _pickNearestFeature(latLng, maxMeters: tolMeters);

    if (hit == null) {
      await _setSelectedFilter(null);
      _selectedSegId = null;
      return;
    }

    _selectedSegId = hit['seg_id']?.toString();
    await _setSelectedFilter(_selectedSegId);

    // Nudge camera in a bit
    await _map!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15.5));

    // Let the host page show the popover & drawer from properties
    widget.onFeatureSelected(hit);
  }

  Future<void> _setSelectedFilter(String? segId) async {
    if (_map == null) return;
    // Filter that matches nothing when segId == null
    final filter = (segId == null)
        ? ['==', ['get', 'seg_id'], '__none__']
        : ['==', ['get', 'seg_id'], segId];
    await _map!.setFilter(streetsSelLyrId, filter);
  }

  Map<String, dynamic>? _pickNearestFeature(LatLng p, {required double maxMeters}) {
    final fcType = _segmentsGeo?['type'];
    if (fcType != 'FeatureCollection') return null;

    final feats = (_segmentsGeo?['features'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    double best = double.infinity;
    Map<String, dynamic>? bestProps;

    for (final f in feats) {
      final geom = (f['geometry'] as Map?)?.cast<String, dynamic>();
      if (geom == null) continue;

      final type = geom['type'] as String? ?? '';
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (type == 'LineString') {
        final coords = (geom['coordinates'] as List?)?.cast<List>() ?? const [];
        _scanLineString(p, coords, props, (d, pr) { if (d < best) { best = d; bestProps = pr; } });
      } else if (type == 'MultiLineString') {
        final lines = (geom['coordinates'] as List?)?.cast<List>() ?? const [];
        for (final line in lines) {
          final coords = (line as List).cast<List>();
          _scanLineString(p, coords, props, (d, pr) { if (d < best) { best = d; bestProps = pr; } });
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

  LatLng _ll(List c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());

  double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    const double mPerDegLat = 111320.0;
    final double cosLat = math.cos(p.latitude * math.pi / 180.0);

    double x(num lon) => (lon - p.longitude) * mPerDegLat * cosLat;
    double y(num lat) => (lat - p.latitude) * mPerDegLat;

    final ax = x(a.longitude), ay = y(a.latitude);
    final bx = x(b.longitude), by = y(b.latitude);

    final vx = bx - ax, vy = by - ay;
    final wx = -ax,    wy = -ay;

    final vv = vx * vx + vy * vy;
    final t = (vv == 0) ? 0.0 : ((wx * vx + wy * vy) / vv).clamp(0.0, 1.0);

    final cx = ax + t * vx, cy = ay + t * vy;
    return math.sqrt(cx * cx + cy * cy);
  }

  // --- Scrollytelling camera -------------------------------------------------

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

    // If scenario styling later controls color, update here.
    // if (oldWidget.scenario != widget.scenario) { ... }

    final chapterChanged = oldWidget.chapter != widget.chapter;
    final camChanged = oldWidget.chapterCamera != widget.chapterCamera;
    if (chapterChanged || camChanged) {
      _applyChapterCamera();
    }
  }
}
