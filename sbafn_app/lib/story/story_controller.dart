import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'story_models.dart';

Map<String, dynamic> buildSegmentsGeojson(List<SegmentFeature> segs) {
  final withE = segs.where((s) => s.elevationM != null).toList();
  double minE = double.infinity, maxE = -double.infinity;
  for (final s in withE) {
    final e = s.elevationM!;
    if (e < minE) minE = e;
    if (e > maxE) maxE = e;
  }
  final hasRange = withE.isNotEmpty && maxE > minE;

  final features = <Map<String, dynamic>>[];
  for (final s in segs) {
    final props = <String, dynamic>{
      'id': s.id,
      'riskBand': s.riskBand, // 'low'|'med'|'high'
      'rainThreshold': s.rainThreshold,
    };
    if (s.elevationM != null && hasRange) {
      final t = ((s.elevationM! - minE) / (maxE - minE)).clamp(0.0, 1.0);
      props['elev_norm'] = t;
    }

    features.add({
      'type': 'Feature',
      'id': s.id,
      'properties': props,
      'geometry': {'type': 'LineString', 'coordinates': s.lineString},
    });
  }

  return {'type': 'FeatureCollection', 'features': features};
}

String segmentsToGeoJsonString(List<SegmentFeature> segs) =>
    jsonEncode(buildSegmentsGeojson(segs));

class StoryController {
  MapLibreMapController? _map;
  List<Scene> scenes = const [];
  List<SegmentFeature> segments = const [];

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
    try {
      await _joinElevationsCsv('assets/mnl_segments_with_elevation.csv');
    } catch (_) {}
  }

  Future<void> addSegmentsToMap() async {
    final map = _map;
    if (map == null) return;

    // GeoJSON source
    final geojsonStr = segmentsToGeoJsonString(segments);
    await map.addSource(
      'segments-src',
      GeojsonSourceProperties(data: geojsonStr, promoteId: 'id'),
    );

    await map.addLineLayer(
      'segments-src',
      'segments-line',
      const LineLayerProperties(
        lineJoin: 'round',
        lineCap: 'round',
        lineWidth: 3.2,
        lineOpacity: 0.9,
        lineColor: [
          'match',
          ['get', 'riskBand'],
          'high',
          '#E74C3C',
          'med',
          '#E67E22',
          '#2F6EA5',
        ],
      ),
    );

    await map.addLineLayer(
      'segments-src',
      'segments-selected',
      const LineLayerProperties(
        lineJoin: 'round',
        lineCap: 'round',
        lineColor: '#111111',
        lineWidth: 7.5,
        lineOpacity: 1.0,
      ),
    );

    await map.setFilter('segments-selected', [
      '==',
      ['get', 'id'],
      '__none__',
    ]);
  }

  Future<void> flyTo(CameraSpec cam) async {
    final map = _map;
    if (map == null) return;
    await map.animateCamera(
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

  Future<void> applyFilters({String? risk, double? rain}) async {
    if (risk != null) riskFilter = risk;
    if (rain != null) rainFilter = rain;

    final List<dynamic> filter = (riskFilter == 'all')
        ? [
            '<=',
            ['get', 'rainThreshold'],
            rainFilter,
          ]
        : [
            'all',
            [
              '==',
              ['get', 'riskBand'],
              riskFilter,
            ],
            [
              '<=',
              ['get', 'rainThreshold'],
              rainFilter,
            ],
          ];

    await _map?.setFilter('segments-line', filter);
  }

  Future<void> selectSegment(String id) async {
    selectedSegmentId = id;
    await _map?.setFilter('segments-selected', [
      '==',
      ['get', 'id'],
      id,
    ]);
  }

  SegmentFeature? get selected {
    if (selectedSegmentId == null) return null;
    for (final s in segments) {
      if (s.id == selectedSegmentId) return s;
    }
    return null;
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

    segments = [for (final s in segments) s.copyWith(elevationM: map[s.id])];
  }

  Future<void> setColorMode(String mode) async {
    colorMode = mode;
    final map = _map;
    if (map == null) return;

    if (mode == 'risk') {
      await map.setLayerProperties(
        'segments-line',
        LineLayerProperties(
          lineColor: [
            'match',
            ['get', 'riskBand'],
            'high',
            '#E74C3C',
            'med',
            '#E67E22',
            '#2F6EA5',
          ],
        ),
      );
    } else {
      await map.setLayerProperties(
        'segments-line',
        LineLayerProperties(
          lineColor: [
            'interpolate',
            ['linear'],
            [
              'coalesce',
              ['get', 'elev_norm'],
              0.0,
            ],
            0.0,
            '#2F6EA5',
            0.5,
            '#E67E22',
            1.0,
            '#E74C3C',
          ],
        ),
      );
    }
  }
}
