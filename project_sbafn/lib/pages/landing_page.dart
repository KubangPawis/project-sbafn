import 'package:flutter/material.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A2A43), Color(0xFF2F6EA5)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'SBAFN: Street-Level Flood Risk in Metro Manila',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Understanding flood vulnerability through street-based assessment\nof flood-prone neighborhoods',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22, height: 1.35),
                ),
                const SizedBox(height: 22),
                Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/story'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Story'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/explore'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Explore Map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
