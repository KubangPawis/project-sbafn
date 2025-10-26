import 'package:flutter/material.dart';

import 'package:project_sbafn/story/story_map_page.dart';
import 'package:project_sbafn/theme/sbafn_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SBAFNApp());
}

class SBAFNApp extends StatelessWidget {
  const SBAFNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SBAFN',
      theme: SBAFNTheme.light(),
      darkTheme: SBAFNTheme.dark(),
      themeMode: ThemeMode.light,
      initialRoute: '/',
      routes: {'/': (_) => const StoryMapPage()},
    );
  }
}
