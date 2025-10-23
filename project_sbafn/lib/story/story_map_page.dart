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
  final StoryController story = StoryController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String scenario = '50';                  // "30" | "50" | "100"
  int activeChapter = 0;                   // index of the currently focused chapter
  Map<String, dynamic>? selectedProps;     // selected segment (from MapView)

  // Keep the latest visible fraction reported by each chapter card
  final Map<int, double> _visibleFractions = {};

  // Layout constants
  static const double _chaptersPaneWidth  = 430;
  static const double _chaptersPaneMargin = 8;
  static const double _framePadding       = 12;
  static const double _footerReserve      = 96;

  @override
  void initState() {
    super.initState();
    story.loadAssets().then((_) => setState(() {}));
  }

  // Pick the list item with the greatest visible fraction
  void _onCardVisibility(int index, double fraction) {
    _visibleFractions[index] = fraction;

    if (_visibleFractions.isEmpty) return;

    final bestIndex = _visibleFractions.entries
        .reduce((a, b) => (a.value >= b.value) ? a : b)
        .key;

    if (bestIndex != activeChapter) {
      setState(() => activeChapter = bestIndex);
    }
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
            child: Row(children: [
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
            ]),
          ),
        ],
      ),

      endDrawer: _ExplainabilityDrawer(props: selectedProps, scenario: scenario),

      body: Stack(
        children: [
          // Framed map area (keeps the map contained)
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
                    // Map
                    Positioned.fill(
                      child: MapView(
                        scenario: scenario,
                        chapter: activeChapter,
                        chapterCamera: cam,                 // ← drives auto fly/zoom
                        onFeatureSelected: (props) =>
                            setState(() => selectedProps = props),
                      ),
                    ),

                    // Floating Filters (anchored in the map frame)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _FiltersCard(
                        initialRain: story.rainFilter,
                        onRainChanged: (v) =>
                            setState(() => story.applyFilters(rain: v)),
                        onRiskChanged: (r) =>
                            setState(() => story.applyFilters(risk: r)),
                        onColorModeChanged: (mode) =>
                            setState(() => story.setColorMode(mode)),
                      ),
                    ),

                    // Flood risk legend (fixed to bottom-right of frame)
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
              constraints:
                  const BoxConstraints.tightFor(width: _chaptersPaneWidth),
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                    _chaptersPaneMargin, 16, _chaptersPaneMargin, 16),
                child: story.scenes.isEmpty
                    ? const SizedBox()
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120),
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemCount: story.scenes.length,
                        itemBuilder: (_, i) => VisibilityDetector(
                          key: Key('chapter-$i'),
                          onVisibilityChanged: (info) =>
                              _onCardVisibility(i, info.visibleFraction),
                          child: _ChapterCard(
                            scene: story.scenes[i],
                            isActive: activeChapter == i,
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // Segment popover (in the map area)
          Positioned(
            bottom: _footerReserve + 64,
            left: 0,
            right: _chaptersPaneWidth + _chaptersPaneMargin + 24,
            child: Center(
              child: _SegmentPopover(
                props: selectedProps,
                scenario: scenario,
                onWhy: () =>_scaffoldKey.currentState?.openEndDrawer(),
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

// ---------- UI pieces (unchanged below, minor tidy) ----------

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
                  style:
                      textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6)
              ],
            ),
            const SizedBox(height: 12),
            row(const Color(0xFFE74C3C), 'High', 'Score: 67–100'),
            const SizedBox(height: 8),
            row(const Color(0xFFE67E22), 'Medium', 'Score: 34–66'),
            const SizedBox(height: 8),
            row(const Color(0xFF2F6EA5), 'Low', 'Score: 0–33'),
            const SizedBox(height: 12),
            Text('0 = Lowest Risk • 100 = Highest Risk', style: textTheme.bodySmall),
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
  const _ScenarioPill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? Colors.black : Colors.white,
        foregroundColor: active ? Colors.white : Colors.black,
        side: BorderSide(color: active ? Colors.black : const Color(0xFFD1D5DB)),
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
                Icon(Icons.radio_button_checked,
                    size: 18,
                    color: isActive ? theme.colorScheme.primary : theme.disabledColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scene.title,
                    style: theme.textTheme.titleMedium!
                        .copyWith(fontWeight: FontWeight.w600),
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
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('All', 'all'),
                _chip('Low', 'low'),
                _chip('Med', 'med'),
                _chip('High', 'high'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Color by:'),
                ChoiceChip(
                  label: const Text('Risk'),
                  selected: colorBy == 'risk',
                  onSelected: (_) {
                    setState(() => colorBy = 'risk');
                    widget.onColorModeChanged?.call('risk');
                  },
                ),
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
              min: 30,
              max: 150,
              divisions: 120,
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

class _RiskLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget row(Color c, String title, String sub) => Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration:
                  BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
            ),
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
            row(const Color(0xFFE74C3C), 'High', 'Score: ≥ 0.66'),
            const SizedBox(height: 6),
            row(const Color(0xFFE67E22), 'Medium', 'Score: 0.33–0.66'),
            const SizedBox(height: 6),
            row(const Color(0xFF22C55E), 'Low', 'Score: < 0.33'),
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
  final VoidCallback? onClose; // NEW

  const _SegmentPopover({
    required this.props,
    required this.scenario,
    required this.onWhy,
    this.onClose, // NEW
  });

  double _risk(Map<String, dynamic> p) {
    final key = 'risk_$scenario';
    final v = p[key];
    return v is num ? v.toDouble() : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final p = props;
    if (p == null) return const SizedBox.shrink();

    final risk = _risk(p);
    final band = risk >= 0.66 ? 'high' : (risk >= 0.33 ? 'med' : 'low');
    final color = band == 'high'
        ? const Color(0xFFE74C3C)
        : (band == 'med' ? const Color(0xFFE67E22) : const Color(0xFF22C55E));

    String fmt(num? n, {int dp = 1}) => n == null ? '—' : n.toStringAsFixed(dp);

    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          // content
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with title and close
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Segment ID',
                                style: Theme.of(context).textTheme.labelLarge),
                            Text(p['seg_id']?.toString() ?? '—',
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Keeps the layout stable if no onClose provided
                      if (onClose != null)
                        IconButton(
                          tooltip: 'Close',
                          onPressed: onClose,
                          icon: const Icon(Icons.close),
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          constraints: const BoxConstraints.tightFor(
                            width: 32, height: 32,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${p['barangay'] ?? '—'}'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Risk ($scenario mm/hr)',
                          style: Theme.of(context).textTheme.labelLarge),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$scenario mm/hr'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: risk.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.black12,
                    color: color,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(''),
                      Text((risk * 100).toStringAsFixed(0)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _kv('HAND', '${fmt(p['HAND_m'])} m'),
                      _kv('Slope', '${fmt(p['slope_pct'])}%'),
                      _kv('Canal dist', '${fmt(p['dist_canal_m'], dp: 0)} m'),
                      _kv('Road', p['road_class']?.toString() ?? '—'),
                      _kv('Drain dens',
                          '${fmt((p['drain_density'] as num?)?.toDouble(), dp: 1)} /100m'),
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
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black87, fontSize: 12),
            children: [
              TextSpan(
                text: '$k: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: v),
            ],
          ),
        ),
      );
}

  Widget _kv(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black87, fontSize: 12),
            children: [
              const TextSpan(
                  text: '', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: v),
            ],
          ),
        ),
      );

class _ExplainabilityDrawer extends StatelessWidget {
  final Map<String, dynamic>? props;
  final String scenario;
  const _ExplainabilityDrawer({required this.props, required this.scenario});

  double _risk(Map<String, dynamic> p) {
    final v = p['risk_$scenario'];
    return v is num ? v.toDouble() : 0.0;
  }

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
                    Row(children: [
                      const Icon(Icons.place_outlined),
                      const SizedBox(width: 8),
                      const Text('Why is this segment risky?',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('Segment ID: ${p['seg_id'] ?? '—'}'),
                    Text('Barangay: ${p['barangay'] ?? '—'}'),
                    const SizedBox(height: 12),
                    const Text('Contribution Weights',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    _contrib('Low elevation (HAND)',
                        _clamp01((1.5 - ((p['HAND_m'] as num?) ?? 1.5)) / 1.5)),
                    const SizedBox(height: 8),
                    _contrib('Flat slope',
                        _clamp01((1 - ((p['slope_pct'] as num?) ?? 1.0)) / 1)),
                    const SizedBox(height: 8),
                    _contrib('Near canal',
                        _clamp01((100 - ((p['dist_canal_m'] as num?) ?? 100)) / 100)),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'At ${scenario} mm/hr, the risk score is ${( _risk(p) * 100).toStringAsFixed(0)}. '
                          'Low relative elevation, flatter slope, and canal proximity are key contributors for this segment.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  double _clamp01(num v) => v.isNaN ? 0 : v.clamp(0, 1).toDouble();

  Widget _contrib(String label, double v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label),
            Text('${(v * 100).round()}%'),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: v, minHeight: 8),
        ],
      );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).bottomAppBarTheme.color,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: DefaultTextStyle(
        style: Theme.of(context)
            .textTheme
            .bodySmall!
            .copyWith(color: Colors.white.withOpacity(0.9)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Attribution',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Map data © OpenStreetMap contributors, MapTiler • Flood data: DPWH, PAGASA, NAMRIA'),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Disclaimer',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Informational purposes only. For official flood risk assessments, consult local authorities.'),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Contact & Feedback',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
