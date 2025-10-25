import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:visibility_detector/visibility_detector.dart';
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
  String riskFilter = 'all'; // "all" | "low" | "med" | "high"
  int activeChapter = 0;

  Map<String, dynamic>? selectedProps;

  static const double _chaptersPaneWidth = 430;
  static const double _chaptersPaneMargin = 8;
  static const double _framePadding = 12;
  static const double _footerReserve = 96;

  @override
  void initState() {
    super.initState();
    story.loadAssets().then((_) => setState(() {}));
  }

  void _applyChapter(int i) {
    if (i == activeChapter) return;
    setState(() => activeChapter = i);
  }

  @override
  Widget build(BuildContext context) {
    final cam = (activeChapter < story.scenes.length)
        ? story.scenes[activeChapter].camera
        : null;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('SBAFN Story Map'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                _ScenarioPill(
                  label: '30 mm/hr',
                  active: scenario == '30',
                  onTap: () => setState(() => scenario = '30'),
                ),
                const SizedBox(width: 6),
                _ScenarioPill(
                  label: '50 mm/hr',
                  active: scenario == '50',
                  onTap: () => setState(() => scenario = '50'),
                ),
                const SizedBox(width: 6),
                _ScenarioPill(
                  label: '100 mm/hr',
                  active: scenario == '100',
                  onTap: () => setState(() => scenario = '100'),
                ),
                const SizedBox(width: 8),
              ],
            ),
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
            bottom: _footerReserve,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
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
                        chapter: activeChapter,
                        chapterCamera: cam,
                        onFeatureSelected: (props) =>
                            setState(() => selectedProps = props),
                      ),
                    ),

                    // Filters card (only Risk band)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _RiskFiltersCard(
                        current: riskFilter,
                        onChanged: (v) => setState(() => riskFilter = v),
                      ),
                    ),

                    const Positioned(
                      right: 12,
                      bottom: 12,
                      child: _FloodRiskCard(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Chapters panel
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

          // Segment popover (simplified)
          Positioned(
            bottom: _footerReserve + 64,
            left: 0,
            right: _chaptersPaneWidth + _chaptersPaneMargin + 24,
            child: Center(
              child: _SegmentPopover(
                props: selectedProps,
                scenario: scenario,
                onWhy: () => _scaffoldKey.currentState?.openEndDrawer(),
                onClose: () => setState(() => selectedProps = null),
              ),
            ),
          ),

          const Positioned(left: 0, right: 0, bottom: 0, child: _Footer()),
        ],
      ),
    );
  }
}

// ---------- UI pieces ----------

class _RiskFiltersCard extends StatelessWidget {
  final String current; // "all" | "low" | "med" | "high"
  final ValueChanged<String> onChanged;
  const _RiskFiltersCard({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('All', 'all'),
                _chip('Low', 'low'),
                _chip('Med', 'med'),
                _chip('High', 'high'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(value),
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
        width: 240,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Flood Risk',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.info_outline, size: 16, color: Colors.black54),
              ],
            ),
            const SizedBox(height: 12),
            row(const Color(0xFFE74C3C), 'High', 'Score: 67–100'),
            const SizedBox(height: 8),
            row(const Color(0xFFFFFF33), 'Medium', 'Score: 34–66'),
            const SizedBox(height: 8),
            row(const Color(0xFF39FF14), 'Low', 'Score: 0–33'),
            const SizedBox(height: 12),
            Text(
              '0 = Lowest Risk • 100 = Highest Risk',
              style: textTheme.bodySmall,
            ),
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

  // Best-effort name
  String _nameOf(Map<String, dynamic> p) {
    return (p['name'] ?? p['road_name'] ?? p['street'] ?? p['highway'] ?? '—')
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
    // numeric fallback: risk_XX or p_EVTxx
    double? n;
    final r = p['risk_$scenario'];
    final q = p['p_$evt'];
    if (r is num) n = r.toDouble();
    if (n == null && r is String) n = double.tryParse(r);
    if (n == null && q is num) n = q.toDouble();
    if (n == null && q is String) n = double.tryParse(q);
    if (n == null) return ('—', ''); // nothing
    if (n > 1) n = n / 100.0; // normalize 0..100 → 0..1

    final band = (n >= 0.66) ? 'HIGH' : (n >= 0.33 ? 'MEDIUM' : 'LOW');
    final score = (n * 100).clamp(0, 100).toStringAsFixed(0);
    return (band, score);
  }

  @override
  Widget build(BuildContext context) {
    final p = props;
    if (p == null) return const SizedBox.shrink();

    final segId = p['seg_id']?.toString() ?? '—';
    final street = _nameOf(p);
    final (band, score) = _riskOf(p);

    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Segment ID: $segId',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(street),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Risk ($scenario mm/hr)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (score.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$score / 100'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(band, style: const TextStyle(fontWeight: FontWeight.w700)),
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
  final Map<String, dynamic>? props;
  final String scenario;
  const _ExplainabilityDrawer({required this.props, required this.scenario});

  @override
  Widget build(BuildContext context) {
    final p = props;
    return Drawer(
      width: 420,
      child: SafeArea(
        child: p == null
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
                        const Text(
                          'Why is this segment risky?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Segment ID: ${p['seg_id'] ?? '—'}'),
                    Text('Scenario: $scenario mm/hr'),
                    const SizedBox(height: 16),

                    const Text(
                      'Probable Causes',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),

                    const _CauseChip(text: 'Low drainage counts'),
                    const SizedBox(height: 8),
                    const _CauseChip(
                      text:
                          'Low relative elevation compared to adjacent streets',
                    ),
                    const SizedBox(height: 8),
                    const _CauseChip(text: 'High road width'),

                    const SizedBox(height: 16),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text(
                          'These are indicative factors based on available data. '
                          'For official flood risk assessments, consult local authorities.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
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
                    'Attribution',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Map data © OpenStreetMap contributors, MapTiler • Flood data: DPWH, PAGASA, NAMRIA',
                  ),
                ],
              ),
            ),
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
                    'Informational purposes only. For official flood risk assessments, consult local authorities.',
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
                    'Contact & Feedback',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text('sbafn@example.com'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
