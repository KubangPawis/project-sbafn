import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'story_controller.dart';
import 'story_models.dart';

class StoryMapPage extends StatefulWidget {
  const StoryMapPage({super.key});
  @override
  State<StoryMapPage> createState() => _StoryMapPageState();
}

class _StoryMapPageState extends State<StoryMapPage> {
  final StoryController story = StoryController();
  int activeChapter = 0;

  final String styleUrl =
      'https://api.maptiler.com/maps/streets/style.json?key=YOUR_MAPTILER_KEY';

  @override
  void initState() {
    super.initState();
    story.loadAssets().then((_) => setState(() {}));
  }

  void _onMapCreated(MapLibreMapController c) async {
    story.attachMap(c);
    await story.addSegmentsToMap();
    if (story.scenes.isNotEmpty) {
      await story.flyTo(story.scenes.first.camera);
    }
  }

  void _applyChapter(int i) {
    if (i == activeChapter) return;
    setState(() => activeChapter = i);
    story.flyTo(story.scenes[i].camera);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('SBAFN Story Map')),
      endDrawer: _ExplainabilityDrawer(story: story),
      body: Stack(
        children: [
          // MAP
          Positioned.fill(
            child: MapLibreMap(
              styleString: styleUrl,
              onMapCreated: _onMapCreated,
              initialCameraPosition: const CameraPosition(
                target: LatLng(14.5995, 120.9842),
                zoom: 11,
              ),
              compassEnabled: false,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              minMaxZoomPreference: const MinMaxZoomPreference(9, 18),
            ),
          ),

          // FILTERS
          Positioned(
            left: 16,
            top: 16,
            child: _FiltersCard(
              initialRain: story.rainFilter,
              onRainChanged: (v) => setState(() => story.applyFilters(rain: v)),
              onRiskChanged:  (r) => setState(() => story.applyFilters(risk: r)),
              onColorModeChanged: (mode) => setState(() => story.setColorMode(mode)),
            ),
          ),

          // LEGEND
          Positioned(
            bottom: 90,
            left: 0,
            right: 0,
            child: Center(child: _RiskLegend()),
          ),

          // CHAPTERS
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints.tightFor(width: 430),
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                child: story.scenes.isEmpty
                    ? const SizedBox()
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120),
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemCount: story.scenes.length,
                        itemBuilder: (_, i) => VisibilityDetector(
                          key: Key('chapter-$i'),
                          onVisibilityChanged: (info) {
                            if (info.visibleFraction >= 0.6) _applyChapter(i);
                          },
                          child: _ChapterCard(
                            scene: story.scenes[i],
                            isActive: activeChapter == i,
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // SEGMENT POPOVER
          Positioned(
            bottom: 160,
            left: 0,
            right: 0,
            child: Center(
              child: _SegmentPopover(
                story: story,
                onWhy: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ),

          // FOOTER
          Positioned(left: 0, right: 0, bottom: 0, child: _Footer()),
        ],
      ),
    );
  }
}

// ---------------- UI pieces ----------------

class _ChapterCard extends StatelessWidget {
  final Scene scene;
  final bool isActive;
  const _ChapterCard({required this.scene, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: isActive ? 10 : 2,
      shadowColor: isActive ? theme.colorScheme.primary.withOpacity(0.4) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radio_button_checked,
                    size: 18,
                    color: isActive ? theme.colorScheme.primary : theme.disabledColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scene.title,
                    style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isActive)
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.flight_takeoff, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text('Flying', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(data: scene.bodyMd),
          ],
        ),
      ),
    );
  }
}

class _FiltersCard extends StatefulWidget {
  final double initialRain;
  final ValueChanged<double> onRainChanged;
  final ValueChanged<String> onRiskChanged;
  final ValueChanged<String>? onColorModeChanged;

  const _FiltersCard({
    Key? key,
    required this.initialRain,
    required this.onRainChanged,
    required this.onRiskChanged,
    this.onColorModeChanged,
  }) : super(key: key);

  @override
  State<_FiltersCard> createState() => _FiltersCardState();
}

class _FiltersCardState extends State<_FiltersCard> {
  late double rain = widget.initialRain;
  String risk = 'all';
  String colorBy = 'risk';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                _chip('All', 'all'),
                _chip('Low', 'low'),
                _chip('Med', 'med'),
                _chip('High', 'high'),
              ],
            ),
            const SizedBox(height: 12),

            // Color-by
            Row(
              children: [
                const Text('Color by:'),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Risk'),
                  selected: colorBy == 'risk',
                  onSelected: (_) {
                    setState(() => colorBy = 'risk');
                    widget.onColorModeChanged?.call('risk');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Elevation'),
                  selected: colorBy == 'elevation',
                  onSelected: (_) {
                    setState(() => colorBy = 'elevation');
                    widget.onColorModeChanged?.call('elevation');
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Rain slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Rainfall', style: theme.textTheme.labelLarge),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('${rain.toStringAsFixed(0)} mm/hr',
                      style: theme.textTheme.labelSmall),
                ),
              ],
            ),
            Slider(
              min: 30, max: 150, divisions: 120,
              value: rain,
              onChanged: (v) => setState(() => rain = v),
              onChangeEnd: widget.onRainChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [Text('30'), Text('150')],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = risk == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => risk = value);
        widget.onRiskChanged(value);
      },
    );
  }
}

// Optional helper UI row (unused here but kept handy)
Widget _toggleRow(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(label)),
      Switch(value: false, onChanged: (_) {}),
    ],
  );
}

class _RiskLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget row(Color c, String title, String sub) => Row(
          children: [
            Container(width: 16, height: 16, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ])
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(const Color(0xFFE74C3C), 'High', 'Score: 67–100'),
            const SizedBox(height: 6),
            row(const Color(0xFFE67E22), 'Medium', 'Score: 34–66'),
            const SizedBox(height: 6),
            row(const Color(0xFF2F6EA5), 'Low', 'Score: 0–33'),
            const SizedBox(height: 8),
            Text('0 = Lowest Risk • 100 = Highest Risk',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SegmentPopover extends StatelessWidget {
  final StoryController story;
  final VoidCallback onWhy;
  const _SegmentPopover({required this.story, required this.onWhy});

  @override
  Widget build(BuildContext context) {
    final sel = story.selected;
    if (sel == null) return const SizedBox.shrink();
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Segment ID', style: Theme.of(context).textTheme.labelLarge),
            Text(sel.id, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${sel.barangay}, ${sel.city}'),
            if (sel.elevationM != null)
              Text('Elevation: ${sel.elevationM!.toStringAsFixed(1)} m'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Risk Assessment', style: Theme.of(context).textTheme.labelLarge),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${sel.rainThreshold.toStringAsFixed(0)} mm/hr'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (sel.riskScore.clamp(0, 100)) / 100.0,
              minHeight: 10,
              backgroundColor: Colors.black12,
              color: sel.riskBand == 'high'
                  ? const Color(0xFFE74C3C)
                  : sel.riskBand == 'med'
                      ? const Color(0xFFE67E22)
                      : const Color(0xFF2F6EA5),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(sel.riskBand.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(sel.riskScore.toStringAsFixed(0)),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onWhy,
              icon: const Icon(Icons.info_outline),
              label: const Text('Why is this risky?'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplainabilityDrawer extends StatelessWidget {
  final StoryController story;
  const _ExplainabilityDrawer({required this.story});

  @override
  Widget build(BuildContext context) {
    final sel = story.selected;
    return Drawer(
      width: 420,
      child: SafeArea(
        child: sel == null
            ? const Center(child: Text('Select a segment to see details.'))
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place_outlined),
                        const SizedBox(width: 8),
                        const Text('Why is this segment risky?',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).maybePop(),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Segment ID: ${sel.id}'),
                    Text('Location: ${sel.barangay}, ${sel.city}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sel.driversTop.map((d) => Chip(label: Text(d))).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('Contribution Weights',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...sel.driversContrib.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: e.value, minHeight: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'This street segment is at ${sel.riskBand.toUpperCase()} risk primarily due to ${sel.driversTop.take(2).join(" and ")}. '
                          'Heavy rainfall above ${sel.rainThreshold.toStringAsFixed(0)} mm/hr increases the likelihood of flooding.',
                        ),
                      ),
                    )
                  ],
                ),
              ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.98),
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Attribution', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text(
                  'Map data © OpenStreetMap contributors, MapTiler • Flood data: DPWH, PAGASA, NAMRIA',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Disclaimer', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text(
                  'Informational purposes only. For official flood risk assessments, consult local authorities.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Contact & Feedback', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('sbafn@example.com', style: TextStyle(fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
