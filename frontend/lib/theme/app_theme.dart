import 'package:flutter/material.dart';

// 冷静的蓝灰，传达隐私、克制、可信
const Color _seedColor = Color(0xFF4A6FA5);
const Color _lightSurface = Color(0xFFF7F8FB);
const Color _darkSurface = Color(0xFF0F1318);

@immutable
class KnockPalette extends ThemeExtension<KnockPalette> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color peerBubble;
  final Color onPeerBubble;
  final Color systemBubble;
  final Color onSystemBubble;

  const KnockPalette({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.peerBubble,
    required this.onPeerBubble,
    required this.systemBubble,
    required this.onSystemBubble,
  });

  static const light = KnockPalette(
    success: Color(0xFF1F6F4A),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD7F3E6),
    onSuccessContainer: Color(0xFF0B3D28),
    warning: Color(0xFF8A5A00),
    warningContainer: Color(0xFFFFF0D6),
    onWarningContainer: Color(0xFF4A3000),
    peerBubble: Color(0xFFEEF1F6),
    onPeerBubble: Color(0xFF1B1F24),
    systemBubble: Color(0xFFE9EDF2),
    onSystemBubble: Color(0xFF4A5360),
  );

  static const dark = KnockPalette(
    success: Color(0xFF7BD8AB),
    onSuccess: Color(0xFF003824),
    successContainer: Color(0xFF14503A),
    onSuccessContainer: Color(0xFFB9F0D6),
    warning: Color(0xFFFFC46B),
    warningContainer: Color(0xFF4A3410),
    onWarningContainer: Color(0xFFFFE3B0),
    peerBubble: Color(0xFF1E242C),
    onPeerBubble: Color(0xFFE4E8EE),
    systemBubble: Color(0xFF1A2027),
    onSystemBubble: Color(0xFFA8B2BF),
  );

  @override
  KnockPalette copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? peerBubble,
    Color? onPeerBubble,
    Color? systemBubble,
    Color? onSystemBubble,
  }) {
    return KnockPalette(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      peerBubble: peerBubble ?? this.peerBubble,
      onPeerBubble: onPeerBubble ?? this.onPeerBubble,
      systemBubble: systemBubble ?? this.systemBubble,
      onSystemBubble: onSystemBubble ?? this.onSystemBubble,
    );
  }

  @override
  KnockPalette lerp(KnockPalette? other, double t) {
    if (other == null) return this;
    return KnockPalette(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      peerBubble: Color.lerp(peerBubble, other.peerBubble, t)!,
      onPeerBubble: Color.lerp(onPeerBubble, other.onPeerBubble, t)!,
      systemBubble: Color.lerp(systemBubble, other.systemBubble, t)!,
      onSystemBubble: Color.lerp(onSystemBubble, other.onSystemBubble, t)!,
    );
  }
}

extension KnockTheme on BuildContext {
  KnockPalette get palette =>
      Theme.of(this).extension<KnockPalette>() ?? KnockPalette.light;
}

TextStyle monoStyle(
  BuildContext context, {
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
  double letterSpacing = 0.9,
}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Consolas', 'Menlo', 'Courier New'],
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color ?? Theme.of(context).colorScheme.onSurface,
  );
}

ThemeData _build(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  ).copyWith(
    surface: brightness == Brightness.light ? _lightSurface : _darkSurface,
  );
  final palette =
      brightness == Brightness.light ? KnockPalette.light : KnockPalette.dark;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w300,
      letterSpacing: 6,
      color: scheme.onSurface,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: scheme.onSurface,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: scheme.onSurface,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.55,
      color: scheme.onSurface,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.5,
      color: scheme.onSurface,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.45,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: scheme.outline,
    ),
  );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[palette],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // 宽度交给父级拉伸，避免在对话框 actions 里被撑成整行
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outlineVariant),
        foregroundColor: scheme.onSurface,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 19),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.55,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

ThemeData buildLightTheme() => _build(Brightness.light);
ThemeData buildDarkTheme() => _build(Brightness.dark);
