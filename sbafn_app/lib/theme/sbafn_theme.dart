import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RiskColors extends ThemeExtension<RiskColors> {
  final Color low;
  final Color med;
  final Color high;
  const RiskColors({required this.low, required this.med, required this.high});

  @override
  RiskColors copyWith({Color? low, Color? med, Color? high}) => RiskColors(
    low: low ?? this.low,
    med: med ?? this.med,
    high: high ?? this.high,
  );

  @override
  RiskColors lerp(ThemeExtension<RiskColors>? other, double t) {
    if (other is! RiskColors) return this;
    return RiskColors(
      low: Color.lerp(low, other.low, t)!,
      med: Color.lerp(med, other.med, t)!,
      high: Color.lerp(high, other.high, t)!,
    );
  }
}

class SBAFNTheme {
  static const _seed = Color(0xFF004aad);
  static const _footerNavy = Color(0xFF004aad);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );

    // Inter everywhere, but keep Material roles/sizes
    final base = ThemeData(useMaterial3: true);
    final inter = GoogleFonts.interTextTheme(base.textTheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: inter,

      appBarTheme: AppBarTheme(
        backgroundColor: _seed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: inter.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      cardTheme: CardThemeData(
        elevation: 6,
        color: scheme.surface,
        surfaceTintColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),

      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        showCheckmark: true,
        labelStyle: inter.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface,
          textStyle: inter.labelLarge,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: inter.labelLarge,
        ),
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        showValueIndicator: ShowValueIndicator.always,
        valueIndicatorColor: scheme.surfaceContainerHigh,
        valueIndicatorTextStyle: inter.labelMedium ?? const TextStyle(),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),

      extensions: const <ThemeExtension<dynamic>>[
        RiskColors(
          low: Color(0xFF2F6EA5), // blue
          med: Color(0xFFE67E22), // orange
          high: Color(0xFFE74C3C), // red
        ),
      ],

      // ✅ Use BottomAppBarThemeData to match your Flutter version
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: _footerNavy,
        elevation: 0,
        height: 56,
        shape: CircularNotchedRectangle(),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static ThemeData dark() {
    final base = light();
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
    );
  }
}
