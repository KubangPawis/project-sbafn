import 'package:flutter/material.dart';

import 'package:project_sbafn/pages/landing_page.dart';
import 'package:project_sbafn/story/story_map_page.dart';
import 'package:project_sbafn/pages/home.dart';

void main() => runApp(const SBAFNApp());

class SBAFNApp extends StatelessWidget {
  const SBAFNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SBAFN',
      initialRoute: '/',
      routes: {
        '/':        (_) => const LandingPage(),         // new
        '/story':   (_) => const StoryMapPage(),        // scrollytelling
        '/explore': (_) => const StoryMapHomePage(),    // <-- your current home.dart map
      },
    );
  }
}
