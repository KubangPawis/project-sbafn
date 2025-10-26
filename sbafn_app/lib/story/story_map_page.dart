import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:project_sbafn/pages/map_view.dart';

import 'story_controller.dart';
import 'story_models.dart';

class StoryMapPage extends StatefulWidget {
  const StoryMapPage({super.key});
  @override
  State<StoryMapPage> createState() => _StoryMapPageState();
}

class _StoryMapPageState extends State<StoryMapPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final StoryController story = StoryController();

  String scenario = '50'; // "30" | "50" | "100"
  bool storyStarted = false; // Handle for story start
  int activeChapter = 0;

  Map<String, dynamic>? selectedProps;

  static const double _chaptersPaneWidth = 430;
  static const double _chaptersPaneMargin = 8;
  static const double _framePadding = 0;

  @override
  void initState() {
    super.initState();
    story.loadAssets().then((_) => setState(() {}));
  }

  void _onChapterTap(int i) {
    setState(() {
      storyStarted = true; // start the story on first tap
      activeChapter = i; // go to the tapped chapter
    });
  }

  @override
  Widget build(BuildContext context) {
    final cam = (activeChapter < story.scenes.length)
        ? story.scenes[activeChapter].camera
        : null;

    return Scaffold(
      key: _scaffoldKey,
      bottomNavigationBar: _Footer(),
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(children: []),
          ),
        ],
      ),

      endDrawer: _ExplainabilityDrawer(
        props: selectedProps,
        scenario: scenario,
      ),

      body: Stack(
        children: [
          // Map frame
          Positioned(
            left: _framePadding,
            top: _framePadding,
            right: _chaptersPaneWidth + _chaptersPaneMargin + _framePadding,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MapView(
                      scenario: scenario,
                      isStoryStarted: storyStarted,
                      chapter: activeChapter,
                      chapterCamera:
                          (storyStarted &&
                              activeChapter < story.scenes.length &&
                              activeChapter >= 0)
                          ? story.scenes[activeChapter].camera
                          : null,
                      onFeatureSelected: (props) =>
                          setState(() => selectedProps = props),
                    ),
                  ),

                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: const IgnorePointer(
                        child: Image(
                          image: AssetImage('assets/sbafn_logo.png'),
                          height: 128,
                        ),
                      ),
                    ),
                  ),

                  // [RAINFALL EVENT SIMULATOR PANEL]
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _RainEventSimulatorCard(
                      currentScenario: scenario,
                      onChanged: (v) => setState(() => scenario = v),
                    ),
                  ),

                  const Positioned(
                    left: 12,
                    bottom: 12,
                    child: _FloodRiskCard(),
                  ),
                ],
              ),
            ),
          ),

          // [CHAPTERS PANEL]
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints.tightFor(
                width: _chaptersPaneWidth,
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  _chaptersPaneMargin,
                  16,
                  _chaptersPaneMargin,
                  16,
                ),

                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Icon(Icons.location_pin, size: 32),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Manila, Philippines",
                                  style: GoogleFonts.inter(
                                    color: Color(0xFF004AAD),
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "Story",
                                  style: GoogleFonts.inter(
                                    color: Color(0x99004AAD),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: story.scenes.isEmpty
                          ? const SizedBox()
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 120),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 16),
                              itemCount: story.scenes.length,
                              itemBuilder: (_, i) => _ChapterCard(
                                scene: story.scenes[i],
                                isActive: activeChapter == i,
                                onTap: () => _onChapterTap(i),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Segment popover (simplified)
          Positioned(
            bottom: 32,
            left: 0,
            right: _chaptersPaneWidth + _chaptersPaneMargin + 24,
            child: Center(
              child: PointerInterceptor(
                child: _SegmentPopover(
                  props: selectedProps,
                  scenario: scenario,
                  onWhy: () => _scaffoldKey.currentState?.openEndDrawer(),
                  onClose: () => setState(() => selectedProps = null),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- UI pieces ----------

class _RainEventSimulatorCard extends StatelessWidget {
  final String currentScenario; // "30" | "50" | "100"
  final ValueChanged<String> onChanged;
  const _RainEventSimulatorCard({
    required this.currentScenario,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ScenarioPill(
              label: '30 mm/hr',
              active: currentScenario == '30',
              onTap: () => onChanged('30'),
            ),
            _ScenarioPill(
              label: '50 mm/hr',
              active: currentScenario == '50',
              onTap: () => onChanged('50'),
            ),
            _ScenarioPill(
              label: '100 mm/hr',
              active: currentScenario == '100',
              onTap: () => onChanged('100'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ScenarioPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? Colors.black : Colors.white,
        foregroundColor: active ? Colors.white : Colors.black,
        side: BorderSide(
          color: active ? Colors.black : const Color(0xFFD1D5DB),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final Scene scene;
  final bool isActive;
  final VoidCallback? onTap;

  const _ChapterCard({required this.scene, required this.isActive, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isActive ? 10 : 2,
      shadowColor: isActive ? theme.colorScheme.primary.withOpacity(0.4) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.radio_button_checked,
                    size: 18,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scene.title,
                      style: theme.textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.flight_takeoff,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Flying',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 12,
                            ),
                          ),
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
      ),
    );
  }
}

class _FloodRiskCard extends StatelessWidget {
  const _FloodRiskCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(Color c, String title, String sub) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(sub, style: textTheme.bodySmall),
          ],
        ),
      ],
    );

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Flood Risk',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.info_outline, size: 16, color: Colors.black54),
              ],
            ),
            const SizedBox(height: 12),
            row(const Color(0xFFF56969), 'High', 'Score: 67–100'),
            const SizedBox(height: 8),
            row(const Color(0xFFFFFF33), 'Medium', 'Score: 34–66'),
            const SizedBox(height: 8),
            row(const Color(0xFF39FF14), 'Low', 'Score: 0–33'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SegmentPopover extends StatelessWidget {
  final Map<String, dynamic>? props;
  final String scenario; // "30" | "50" | "100"
  final VoidCallback onWhy;
  final VoidCallback onClose;

  const _SegmentPopover({
    required this.props,
    required this.scenario,
    required this.onWhy,
    required this.onClose,
  });

  // Best-effort name (street first)
  String _nameOf(Map<String, dynamic> p) {
    return (p['street_label'] ??
            p['name'] ??
            p['road_name'] ??
            p['street'] ??
            p['highway'] ??
            'Unnamed Street')
        .toString();
  }

  // Risk (band + percent if available)
  (String band, String score) _riskOf(Map<String, dynamic> p) {
    final evt =
        {'30': 'EVT_01', '50': 'EVT_03', '100': 'EVT_06'}[scenario] ?? 'EVT_03';
    final tier = (p['tier_$evt'] ?? '').toString().toLowerCase();
    if (tier == 'low' || tier == 'medium' || tier == 'med' || tier == 'high') {
      final display = tier == 'med' ? 'MEDIUM' : tier.toUpperCase();
      return (display, '');
    }
    double? n;
    final r = p['risk_$scenario'];
    final q = p['p_$evt'];
    if (r is num) n = r.toDouble();
    if (n == null && r is String) n = double.tryParse(r);
    if (n == null && q is num) n = q.toDouble();
    if (n == null && q is String) n = double.tryParse(q);
    if (n == null) return ('—', '');
    if (n > 1) n = n / 100.0;
    final band = (n >= 0.66) ? 'HIGH' : (n >= 0.33 ? 'MEDIUM' : 'LOW');
    final score = (n * 100).clamp(0, 100).toStringAsFixed(0);
    return (band, score);
  }

  // Top contributor labels (same heuristics as the drawer; swap with real weights later)
  List<String> _topContributorLabels(Map<String, dynamic> p) {
    double clamp01(num? v) => (v ?? 0).clamp(0, 1).toDouble();

    final hand = (p['HAND_m'] as num?) ?? 1.2; // meters
    final slope = (p['slope_pct'] as num?) ?? 0.7; // %
    final dist = (p['dist_canal_m'] as num?) ?? 60; // meters
    final drains = (p['drain_density'] as num?) ?? 1;

    final lowElev = clamp01((1.5 - hand) / 1.5);
    final canalPx = clamp01((100 - dist) / 100);
    final poorDrain = clamp01((2 - drains) / 2);
    final flatSlope = clamp01((1 - slope) / 1);

    final Map<String, double> weights = {
      'Low Elevation': lowElev,
      'Canal Proximity': canalPx,
      'Poor Drainage': poorDrain,
      'Minimal Slope': flatSlope,
    };

    final ranked = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ranked.map((e) => e.key).take(5).toList();
  }

  Color _riskColorFromBand(String band) {
    switch (band.toUpperCase()) {
      case 'HIGH':
        return const Color(0xFFF56969);
      case 'MEDIUM':
        return const Color(0xFFEAB308);
      default:
        return const Color(0xFF16A34A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = props;
    if (p == null) return const SizedBox.shrink();

    final street = _nameOf(p);
    final (band, score) = _riskOf(p); // score available if you want to show it

    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Street name + risk level
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        street,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF004AAD), // indigo headline
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text(
                            'Risk Level: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            band == '—'
                                ? '—'
                                : band[0].toUpperCase() +
                                      band.substring(1).toLowerCase(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _riskColorFromBand(band),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Risk details pill + close
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onWhy,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        shape: const StadiumBorder(),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        backgroundColor: const Color(0xFFF3F4F6),
                      ),
                      icon: const Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: Color(0xFF374151),
                      ),
                      label: const Text(
                        'Risk Details',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Contributor preview chips
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _topContributorLabels(
                p,
              ).map((t) => _OutlineChip(label: t)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple outlined chip used below the headline
class _OutlineChip extends StatelessWidget {
  final String label;
  const _OutlineChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: StadiumBorder(
          side: BorderSide(color: Color(0xFF6366F1)), // indigo outline
        ),
        shadows: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF004AAD),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ExplainabilityDrawer extends StatefulWidget {
  final Map<String, dynamic>? props;
  final String scenario; // "30" | "50" | "100"
  const _ExplainabilityDrawer({required this.props, required this.scenario});

  @override
  State<_ExplainabilityDrawer> createState() => _ExplainabilityDrawerState();
}

class _ExplainabilityDrawerState extends State<_ExplainabilityDrawer>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final p = widget.props;
    final riskKey = 'risk_${widget.scenario}';
    final risk = (p?[riskKey] as num?)?.toDouble() ?? 0.0;
    final riskScore = (risk * 100).clamp(0, 100).round();
    final riskBand = _riskBand(risk);

    return Drawer(
      width: 420,
      child: SafeArea(
        child: p == null
            ? const Center(child: Text('Select a segment to see details.'))
            : DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Why is this segment risky?',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Understanding flood risk factors for this street segment',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Meta card
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _MetaCard(
                        segmentId: p['seg_id']?.toString() ?? '—',
                        location: _locationText(p),
                        rainThreshold: '${widget.scenario} mm/hr',
                        riskScore: '$riskScore/100 • ${riskBand.label}',
                        riskColor: riskBand.color,
                      ),
                    ),

                    // Tabs
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const TabBar(
                          indicator: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          labelColor: Colors.black,
                          unselectedLabelColor: Color(0xFF6B7280),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: [
                            Tab(text: 'Overview'),
                            Tab(text: 'Context'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Body
                    Expanded(
                      child: TabBarView(
                        children: [
                          _OverviewTab(props: p, scenario: widget.scenario),
                          _ContextTab(props: p),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String _locationText(Map<String, dynamic> p) {
    final bgy = p['barangay']?.toString();
    final city = p['city']?.toString();
    if (bgy != null && city != null) return 'Barangay $bgy, $city';
    if (bgy != null) return 'Barangay $bgy';
    return '—';
  }
}

// ---------- Tabs ----------

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> props;
  final String scenario;
  const _OverviewTab({required this.props, required this.scenario});

  @override
  Widget build(BuildContext context) {
    // Compute contributor weights (0..1), then rank
    final weights = _computeWeights(props);
    final ranked = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topTags = ranked.take(4).map((e) => e.keyLabel).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
          'Top Contributors',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topTags.map((t) => _TagChip(label: t)).toList(),
        ),
        const SizedBox(height: 16),

        const Text(
          'Contribution Weights',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final e in ranked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BarRow(label: e.keyLabel, value: e.value),
          ),

        const SizedBox(height: 16),
        _InfoCard(
          child: const Text(
            'This street segment is at higher risk primarily due to low relative '
            'elevation and proximity to drainage/canal networks. Values are demo-grade; '
            'replace with your model outputs when available.',
            style: TextStyle(fontSize: 12, color: Color(0xFF374151)),
          ),
        ),
      ],
    );
  }

  // Heuristics mirrored from your earlier code; adjust as you get real drivers
  Map<_Driver, double> _computeWeights(Map<String, dynamic> p) {
    double clamp01(num v) => v.isNaN ? 0 : v.clamp(0, 1).toDouble();

    final hand = (p['HAND_m'] as num?) ?? 1.2; // meters
    final slope = (p['slope_pct'] as num?) ?? 0.7; // %
    final dist = (p['dist_canal_m'] as num?) ?? 60; // meters
    final drains = (p['drain_density'] as num?) ?? 1;

    final lowElev = clamp01((1.5 - hand) / 1.5);
    final canalPx = clamp01((100 - dist) / 100);
    final poorDrain = clamp01((2 - drains) / 2);
    final flatSlope = clamp01((1 - slope) / 1);

    // Normalize to 0..1 so bars sum visually
    final raw = {
      _Driver.lowElevation: lowElev,
      _Driver.canalProximity: canalPx,
      _Driver.poorDrainage: poorDrain,
      _Driver.minimalSlope: flatSlope,
    };
    final sum = raw.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return raw.map((k, v) => MapEntry(k, 0));
    return raw.map((k, v) => MapEntry(k, v / sum));
  }
}

class _ContextTab extends StatelessWidget {
  final Map<String, dynamic> props;
  const _ContextTab({required this.props});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Metrics', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _KV('Relative elevation (HAND)', '${props['HAND_m'] ?? '—'} m'),
        _KV('Slope', '${props['slope_pct'] ?? '—'} %'),
        _KV('Distance to canal', '${props['dist_canal_m'] ?? '—'} m'),
        _KV('Road class', '${props['road_class'] ?? '—'}'),
        _KV('Drain density', '${props['drain_density'] ?? '—'} /100 m'),
        const SizedBox(height: 16),
        _InfoCard(
          child: const Text(
            'These are indicative factors based on available data. For official '
            'flood risk assessments, consult local authorities.',
            style: TextStyle(fontSize: 12, color: Color(0xFF374151)),
          ),
        ),
      ],
    );
  }
}

// ---------- Small widgets / theming helpers ----------

class _MetaCard extends StatelessWidget {
  final String segmentId;
  final String location;
  final String rainThreshold;
  final String riskScore;
  final Color riskColor;

  const _MetaCard({
    required this.segmentId,
    required this.location,
    required this.rainThreshold,
    required this.riskScore,
    required this.riskColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KV('Segment ID', segmentId),
          _KV('Location', location),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: rainThreshold,
                color: Colors.black,
                inverted: true,
                icon: Icons.water_drop,
              ),
              _Pill(
                label: riskScore,
                color: riskColor,
                inverted: true,
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE5EEF7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value; // 0..1 normalized
  const _BarRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$pct%',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFFF3F4F6)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(0, 1),
                  child: Container(color: const Color(0xFFEF4444)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool inverted;
  final IconData? icon;
  const _Pill({
    required this.label,
    required this.color,
    this.inverted = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = inverted ? color : Colors.white;
    final fg = inverted ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: color, width: 1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(k, style: const TextStyle(color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ---------- enums / helpers ----------

enum _Driver { lowElevation, canalProximity, poorDrainage, minimalSlope }

extension on MapEntry<_Driver, double> {
  String get keyLabel {
    switch (key) {
      case _Driver.lowElevation:
        return 'Low Elevation';
      case _Driver.canalProximity:
        return 'Canal Proximity';
      case _Driver.poorDrainage:
        return 'Poor Drainage';
      case _Driver.minimalSlope:
        return 'Minimal Slope';
    }
  }
}

class _RiskBand {
  final String label;
  final Color color;
  const _RiskBand(this.label, this.color);
}

_RiskBand _riskBand(double risk01) {
  if (risk01 >= 0.66) return const _RiskBand('HIGH', Color(0xFFF56969));
  if (risk01 >= 0.33) return const _RiskBand('MEDIUM', Color(0xFFEAB308));
  return const _RiskBand('LOW', Color(0xFF22C55E));
}

class _CauseChip extends StatelessWidget {
  final String text;
  const _CauseChip({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).bottomAppBarTheme.color,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: DefaultTextStyle(
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: Colors.white.withOpacity(0.9)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Disclaimer',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Info is provided as-is from early-stage models; may contain errors. Use responsibly; consult LGU/DRRM.",
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Contact Us',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text('sbafn.team@gmail.com'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
