import 'dart:convert';

class CameraSpec {
  final double lat;
  final double lng;
  final double zoom;
  final double bearing;
  final double pitch;
  final int durationMs;

  const CameraSpec({
    required this.lat,
    required this.lng,
    required this.zoom,
    this.bearing = 0,
    this.pitch = 0,
    this.durationMs = 1200,
  });

  factory CameraSpec.fromJson(Map<String, dynamic> j) => CameraSpec(
        lat: (j['lat'] ?? 0).toDouble(),
        lng: (j['lng'] ?? 0).toDouble(),
        zoom: (j['zoom'] ?? 12).toDouble(),
        bearing: (j['bearing'] ?? 0).toDouble(),
        pitch: (j['pitch'] ?? 0).toDouble(),
        durationMs: (j['durationMs'] ?? 1200) as int,
      );
}

class Scene {
  final String id;
  final String title;
  final String bodyMd;
  final CameraSpec camera;
  final String? image;
  final String? caption;

  const Scene({
    required this.id,
    required this.title,
    required this.bodyMd,
    required this.camera,
    this.image,
    this.caption,
  });

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'] as String,
        title: j['title'] as String,
        bodyMd: j['bodyMd'] as String,
        camera: CameraSpec.fromJson(j['camera'] as Map<String, dynamic>),
        image: j['media'] != null ? j['media']['image'] as String? : null,
        caption: j['media'] != null ? j['media']['caption'] as String? : null,
      );

  static List<Scene> listFromJson(String raw) =>
      (json.decode(raw) as List).map((e) => Scene.fromJson(e)).toList();
}

class SegmentFeature {
  final String id;
  final String barangay;
  final String city;
  final String riskBand;           
  final double riskScore;         
  final double rainThreshold;
  final List<List<double>> lineString; 
  final List<String> driversTop;
  final Map<String, double> driversContrib;
  final double? elevationM;     

  SegmentFeature({
    required this.id,
    required this.barangay,
    required this.city,
    required this.riskBand,
    required this.riskScore,
    required this.rainThreshold,
    required this.lineString,
    required this.driversTop,
    required this.driversContrib,
    this.elevationM,             
  });

  factory SegmentFeature.fromGeoJson(Map<String, dynamic> f) {
    final props = Map<String, dynamic>.from(f['properties'] as Map);
    final geom  = Map<String, dynamic>.from(f['geometry'] as Map);
    return SegmentFeature(
      id: props['segment_id'].toString(),
      barangay: (props['barangay'] ?? '') as String,
      city: (props['city'] ?? '') as String,
      riskBand: (props['risk_band'] ?? 'low') as String,
      riskScore: (props['risk_score'] ?? 0).toDouble(),
      rainThreshold: (props['rain_threshold_mmhr'] ?? 45).toDouble(),
      lineString: (geom['coordinates'] as List)
          .map<List<double>>((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
          .toList(),
      driversTop: (props['drivers_top'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      driversContrib: (props['drivers_contrib'] as Map? ?? const {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      elevationM: (props['elevation_m'] ?? props['elevation']) == null
          ? null
          : (props['elevation_m'] ?? props['elevation'] as num).toDouble(),
    );
  }
  SegmentFeature copyWith({
    String? riskBand,
    double? riskScore,
    double? rainThreshold,
    double? elevationM,
  }) {
    return SegmentFeature(
      id: id,
      barangay: barangay,
      city: city,
      riskBand: riskBand ?? this.riskBand,
      riskScore: riskScore ?? this.riskScore,
      rainThreshold: rainThreshold ?? this.rainThreshold,
      lineString: lineString,
      driversTop: driversTop,
      driversContrib: driversContrib,
      elevationM: elevationM ?? this.elevationM,
    );
  }
  static List<SegmentFeature> listFromGeoJson(String raw) {
    final Map<String, dynamic> j = json.decode(raw) as Map<String, dynamic>;
    final List<Map<String, dynamic>> features =
        (j['features'] as List).cast<Map<String, dynamic>>();
    return features.map(SegmentFeature.fromGeoJson).toList();
  }
}

