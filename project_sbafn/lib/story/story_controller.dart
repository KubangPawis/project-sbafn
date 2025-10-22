import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'story_models.dart';

/// Glues scroll "scenes" to MapLibre camera + simple line overlays.
class StoryController {
  MapLibreMapController? _map;
  List<Scene> scenes = const [];
  List<SegmentFeature> segments = const [];

  final Map<String, Line> _lineBySegmentId = {};
  String? selectedSegmentId;

  // Filters
  String riskFilter = 'all'; // all|low|med|high
  double rainFilter = 45;
  String colorMode = 'risk'; // 'risk' | 'elevation'

  void attachMap(MapLibreMapController controller) {
    _map = controller;
  }

  Future<void> loadAssets() async {
    final scenesRaw = await rootBundle.loadString('assets/story.json');
    scenes = Scene.listFromJson(scenesRaw);

    final segRaw = await rootBundle.loadString('assets/segments.geojson');
    segments = SegmentFeature.listFromGeoJson(segRaw);

    // Optional: try to join elevations from CSV if present.
    try {
      await _joinElevationsCsv('assets/mnl_segments_with_elevation.csv');
    } catch (_) {/* no-op */}
  }

  Future<void> addSegmentsToMap() async {
    final map = _map;
    if (map == null) return;

    // Clear old
    for (final ln in _lineBySegmentId.values) {
      try { await map.removeLine(ln); } catch (_) {}
    }
    _lineBySegmentId.clear();

    // Draw lines
    for (final s in segments) {
      final line = await map.addLine(LineOptions(
        geometry: s.lineString.map((p) => LatLng(p[1], p[0])).toList(),
        lineColor: _colorForBand(s.riskBand),
        lineWidth: 6.0,
        lineOpacity: 0.85,
      ));
      _lineBySegmentId[s.id] = line;
    }

    // Tap handling
    map.onLineTapped.add((line) {
      for (final e in _lineBySegmentId.entries) {
        if (e.value.id == line.id) {
          selectSegment(e.key);
          break;
        }
      }
    });
  }

  Future<void> flyTo(CameraSpec cam) async {
    final map = _map;
    if (map == null) return;
    await map.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(cam.lat, cam.lng),
        zoom: cam.zoom,
        bearing: cam.bearing,
        tilt: cam.pitch,
      )),
      duration: Duration(milliseconds: cam.durationMs),
    );
  }

  void applyFilters({String? risk, double? rain}) {
    if (risk != null) riskFilter = risk;
    if (rain != null) rainFilter = rain;

    for (final s in segments) {
      final ln = _lineBySegmentId[s.id];
      if (ln == null) continue;

      final passesRisk = (riskFilter == 'all') || (s.riskBand == riskFilter);
      final passesRain = s.rainThreshold <= rainFilter + 0.0001;
      final visible = passesRisk && passesRain;

      _map?.updateLine(ln, LineOptions(
        lineColor: visible ? _colorForBand(s.riskBand) : '#00000000',
        lineWidth: visible ? 6.0 : 0.0,
        lineOpacity: visible ? 0.9 : 0.0,
      ));
    }
  }

  void selectSegment(String segmentId) {
    selectedSegmentId = segmentId;
    for (final e in _lineBySegmentId.entries) {
      final isSel = e.key == selectedSegmentId;
      _map?.updateLine(e.value, LineOptions(
        lineWidth: isSel ? 8.5 : 6.0,
        lineOpacity: isSel ? 1.0 : 0.85,
      ));
    }
  }

  SegmentFeature? get selected {
    if (selectedSegmentId == null) return null;
    for (final s in segments) {
      if (s.id == selectedSegmentId) return s;
    }
    return null;
  }

  String _colorForBand(String band) {
    switch (band) {
      case 'high':
        return '#E74C3C'; // Risk Red
      case 'med':
        return '#E67E22'; // Warning Orange
      case 'low':
      default:
        return '#2F6EA5'; // River Blue
    }
  }

  // ---------- CSV join + elevation coloring helpers (inside the class) ----------

  Future<void> _joinElevationsCsv(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final rows = const CsvToListConverter().convert(raw);
    if (rows.isEmpty) return;

    final header = rows.first.map((e) => e.toString()).toList();
    final idIdx = header.indexOf('segment_id');
    var elevIdx = header.indexOf('elevation_m');
    if (elevIdx == -1) elevIdx = header.indexOf('elevation');
    if (idIdx == -1 || elevIdx == -1) return;

    final map = <String, double>{};
    for (var i = 1; i < rows.length; i++) {
      final id = rows[i][idIdx].toString();
      final ev = (rows[i][elevIdx] as num).toDouble();
      map[id] = ev;
    }

    segments = [
      for (final s in segments) s.copyWith(elevationM: map[s.id]),
    ];
  }

  void setColorMode(String mode) {
    colorMode = mode;
    _restyleLines();
  }

  void _restyleLines() {
    // compute min/max elevation if needed
    double minE = double.infinity, maxE = -double.infinity;
    if (colorMode == 'elevation') {
      for (final s in segments) {
        final e = s.elevationM;
        if (e == null) continue;
        if (e < minE) minE = e;
        if (e > maxE) maxE = e;
      }
      if (minE == double.infinity) { minE = 0; maxE = 1; }
    }

    for (final s in segments) {
      final ln = _lineBySegmentId[s.id];
      if (ln == null) continue;

      String color;
      if (colorMode == 'risk') {
        color = _colorForBand(s.riskBand);
      } else {
        final e = s.elevationM;
        final t = (e == null || maxE == minE)
            ? 0.0
            : ((e - minE) / (maxE - minE)).clamp(0.0, 1.0);
        color = _lerpColor(t);
      }
      _map?.updateLine(ln, LineOptions(lineColor: color));
    }
  }

  String _lerpColor(double t) {
    t = t.clamp(0.0, 1.0);
    // blue -> orange -> red
    if (t <= 0.5) {
      final k = t / 0.5;
      return _mix('#2F6EA5', '#E67E22', k);
    } else {
      final k = (t - 0.5) / 0.5;
      return _mix('#E67E22', '#E74C3C', k);
    }
  }

  String _mix(String a, String b, double t) {
    final pa = int.parse(a.substring(1), radix: 16);
    final pb = int.parse(b.substring(1), radix: 16);
    final ar = (pa >> 16) & 0xFF, ag = (pa >> 8) & 0xFF, ab = pa & 0xFF;
    final br = (pb >> 16) & 0xFF, bg = (pb >> 8) & 0xFF, bb = pb & 0xFF;

    final rr = (ar + ((br - ar) * t)).round().clamp(0, 255);
    final rg = (ag + ((bg - ag) * t)).round().clamp(0, 255);
    final rb = (ab + ((bb - ab) * t)).round().clamp(0, 255);

    String hx(num v) => v.toInt().toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${hx(rr)}${hx(rg)}${hx(rb)}';
  }
}
