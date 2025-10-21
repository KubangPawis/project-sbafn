import 'package:flutter/material.dart';
import 'map_view.dart';

// Top-level page: holds app state (scenario, chapter, selected feature)
// and renders the left chapters, center map, right-side details pane.

class StoryMapHomePage extends StatefulWidget {
  const StoryMapHomePage({super.key});

  @override
  State<StoryMapHomePage> createState() => _StoryMapHomePageState();
}

class _StoryMapHomePageState extends State<StoryMapHomePage> {
  String scenario = '50'; // "30" | "50" | "100"
  int chapter = 2;        // 0..4
  Map<String, dynamic>? selected; // feature properties from MapView

  String get scenarioText => {
        '30': 'Rain 30 mm/hr',
        '50': 'Rain 50 mm/hr',
        '100': 'Rain 100 mm/hr',
      }[scenario]!;

  ({String label, Color color}) get riskBand => {
        '30': (label: 'Medium', color: const Color(0xFFEAB308)),   // yellow-500
        '50': (label: 'High', color: const Color(0xFFEA580C)),     // orange-600
        '100': (label: 'Very High', color: const Color(0xFFDC2626))// red-600
      }[scenario]!;

  @override
  Widget build(BuildContext context) {
    final md = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: 56,
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB)))),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('MNL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      const Text('Manila Street Flood Risk — Story Map (Wireframe)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Spacer(),
                  if (md)
                    Row(
                      children: [
                        RiskPill(label: '30 mm/hr', active: scenario == '30', onTap: () => setState(() => scenario = '30')),
                        const SizedBox(width: 8),
                        RiskPill(label: '50 mm/hr', active: scenario == '50', onTap: () => setState(() => scenario = '50')),
                        const SizedBox(width: 8),
                        RiskPill(label: '100 mm/hr', active: scenario == '100', onTap: () => setState(() => scenario = '100')),
                      ],
                    ),
                ],
              ),
            ),

            // Body grid
            Expanded(
              child: Row(
                children: [
                  // Left: Chapters
                  if (md)
                    Container(
                      width: 320,
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE5E7EB)))),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Chapters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView(
                              children: [
                                _chapterButton(0, 'City overview', 'Hillshade + water mask'),
                                _chapterButton(1, 'Why it floods', 'Elevation pockets, canals, road class'),
                                _chapterButton(2, 'Intersection vignette', 'Your sketched pooling site'),
                                _chapterButton(3, 'Scenarios', '30 / 50 / 100 mm/hr toggles'),
                                _chapterButton(4, 'Explore', 'Click any street for drivers'),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const DefaultTextStyle(
                                    style: TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
                                        SizedBox(height: 6),
                                        _Bullet('2D-first; add 3D terrain later.'),
                                        _Bullet('Scenario switch updates risk coloring.'),
                                        _Bullet('Street click shows top drivers.'),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Center: Map (in its own file)
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MapView(
                            scenario: scenario,
                            chapter: chapter,
                            onFeatureSelected: (props) => setState(() => selected = props),
                          ),
                        ),

                        // Overlay: scenario chip + legend
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Row(
                            children: [
                              _OverlayCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(scenarioText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('Risk band:', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: riskBand.color,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            riskBand.label,
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (md)
                                _OverlayCard(
                                  child: Row(
                                    children: const [
                                      LegendItem(color: Color(0xFF22C55E), label: 'Low'),
                                      SizedBox(width: 12),
                                      LegendItem(color: Color(0xFFEAB308), label: 'Medium'),
                                      SizedBox(width: 12),
                                      LegendItem(color: Color(0xFFDC2626), label: 'High'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Mobile scenario pills
                        if (!md)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                RiskPill(label: '30 mm/hr', active: scenario == '30', onTap: () => setState(() => scenario = '30')),
                                const SizedBox(width: 6),
                                RiskPill(label: '50 mm/hr', active: scenario == '50', onTap: () => setState(() => scenario = '50')),
                                const SizedBox(width: 6),
                                RiskPill(label: '100 mm/hr', active: scenario == '100', onTap: () => setState(() => scenario = '100')),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Right: Why card
                  if (md)
                    Container(
                      width: 360,
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFE5E7EB)))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Why this street floods', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          if (selected != null) ...[
                            Text(
                              'Segment ID: ${selected!['seg_id']} • Barangay ${selected!['barangay']}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Risk ($scenarioText)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: riskBand.color,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text('', style: TextStyle(color: Colors.white, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            BarWidget(
                                              label: 'Low HAND / relative elev',
                                              value: _clamp01((1.5 - (selected!['HAND_m'] ?? 1) as num) / 1.5),
                                              color: const Color(0xFFEA580C),
                                            ),
                                            const SizedBox(height: 12),
                                            BarWidget(
                                              label: 'Flat slope',
                                              value: _clamp01((1 - (selected!['slope_pct'] ?? 0.8) as num) / 1),
                                              color: const Color(0xFFEAB308),
                                            ),
                                            const SizedBox(height: 12),
                                            BarWidget(
                                              label: 'Near canal',
                                              value: _clamp01((100 - (selected!['dist_canal_m'] ?? 60) as num) / 100),
                                              color: const Color(0xFFEAB308),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DefaultTextStyle(
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _kv('HAND', '${selected!['HAND_m'] ?? '—'} m'),
                                              _kv('Slope', '${selected!['slope_pct'] ?? '—'}%'),
                                              _kv('Dist. to canal', '${selected!['dist_canal_m'] ?? '—'} m'),
                                              _kv('Road class', '${selected!['road_class'] ?? '—'}'),
                                              _kv('Drain density', '${selected!['drain_density'] ?? '—'} / 100 m'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text('Demo data — click another segment to update.',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                                ],
                              ),
                            ),
                          ] else
                            const Text('Click a highlighted street to see the drivers.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                          const Spacer(),
                          const Text('Scenario toggles update the color ramp and numbers.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Footer
            Container(
              height: 64,
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE5E7EB)))),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  LegendItem(color: Color(0xFF22C55E), label: 'Low'),
                  SizedBox(width: 16),
                  LegendItem(color: Color(0xFFEAB308), label: 'Medium'),
                  SizedBox(width: 16),
                  LegendItem(color: Color(0xFFDC2626), label: 'High'),
                  SizedBox(width: 16),
                  Text('Hillshade on • Water mask on', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  Spacer(),
                  Text('PoC wireframe • 2D-first • Replace placeholders with live data',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chapterButton(int i, String title, String desc) {
    final active = chapter == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => chapter = i),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.white,
            border: Border.all(color: active ? Colors.black : const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: active ? Colors.white : Colors.black),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: 0.7,
                  child: Text('Step ${i + 1}', style: const TextStyle(fontSize: 11, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: active ? Colors.white70 : const Color(0xFF6B7280))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Small UI atoms (kept here for simplicity) ---

class RiskPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const RiskPill({super.key, required this.label, required this.active, required this.onTap});

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

class BarWidget extends StatelessWidget {
  final String label;
  final double value; // 0..1
  final Color color;

  const BarWidget({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          Text('$pct%', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ]),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0, 1),
              child: Container(
                height: 8,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const LegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(height: 12, width: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
    ]);
  }
}

class _OverlayCard extends StatelessWidget {
  final Widget child;
  const _OverlayCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('• ', style: TextStyle(fontSize: 12)),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
    ]);
  }
}

double _clamp01(num v) => v.isNaN ? 0 : v.clamp(0, 1).toDouble();
Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ]),
    );
