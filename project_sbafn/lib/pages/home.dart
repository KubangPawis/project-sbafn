import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = Completer<MapLibreMapController>();
  bool _styleLoaded = false;

  // Philippines bounding box (approx)
  static final LatLngBounds _phBounds = LatLngBounds(
    southwest: LatLng(4.6433, 116.7000),
    northeast: LatLng(21.1206, 126.6000),
  );

  // Initial camera
  static final CameraPosition _initial = const CameraPosition(
    target: LatLng(12.8797, 121.7740),
    zoom: 5.0,
  );

  // Public demo style (no API key). Replace with your own style.json when ready.
  static const String _styleUrl = 'https://demotiles.maplibre.org/style.json';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _styleUrl,
            initialCameraPosition: _initial,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            trackCameraPosition: true,
            onMapCreated: (c) => _controller.complete(c),
            onStyleLoadedCallback: () async {
              setState(() => _styleLoaded = true);
              final c = await _controller.future;
              await c.animateCamera(
                CameraUpdate.newLatLngBounds(
                  _phBounds,
                  left: 24, top: 24, right: 24, bottom: 24,
                ),
              );
            },
            onMapClick: (point, latLng) async {
              final c = await _controller.future;
              await c.addCircle(CircleOptions(
                geometry: latLng,
                circleRadius: 6.0,
                circleColor: '#1E88E5',
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 2.0,
              ));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Pinned: ${latLng.latitude.toStringAsFixed(5)}, '
                    '${latLng.longitude.toStringAsFixed(5)}',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),

          // Top-left hint
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _styleLoaded
                      ? 'Click the map to drop a pin · Philippines'
                      : 'Loading map…',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),

          // Bottom-right controls
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoundBtn(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onTap: () async {
                    final c = await _controller.future;
                    await c.animateCamera(CameraUpdate.zoomIn());
                  },
                ),
                const SizedBox(height: 8),
                _RoundBtn(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onTap: () async {
                    final c = await _controller.future;
                    await c.animateCamera(CameraUpdate.zoomOut());
                  },
                ),
                const SizedBox(height: 8),
                _RoundBtn(
                  icon: Icons.flag,
                  label: 'PH',
                  tooltip: 'Reset to Philippines',
                  onTap: () async {
                    final c = await _controller.future;
                    await c.animateCamera(
                      CameraUpdate.newLatLngBounds(
                        _phBounds,
                        left: 24, top: 24, right: 24, bottom: 24,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;
  const _RoundBtn({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Ink(
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: CircleBorder(),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87),
        onPressed: onTap,
        tooltip: tooltip,
      ),
    );

    if (label == null) return btn;
    return Column(
      children: [
        btn,
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label!,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
