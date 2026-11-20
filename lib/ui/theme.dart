import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The game always uses its own dark theme, whatever the system setting.
ThemeData buildPourTheme() {
  const scheme = ColorScheme.dark(
    primary: PourColors.accent,
    onPrimary: PourColors.onAccent,
    secondary: PourColors.glass,
    onSecondary: PourColors.bg,
    surface: PourColors.surface,
    onSurface: PourColors.text,
    surfaceContainerHighest: PourColors.surfaceHigh,
    outline: PourColors.outline,
    error: PourColors.danger,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: PourColors.bg,
    fontFamily: 'Nunito',
    textTheme: TextTheme(
      displayLarge: PourText.display,
      headlineMedium: PourText.title,
      titleLarge: PourText.heading,
      bodyLarge: PourText.body,
      bodyMedium: PourText.body,
      labelLarge: PourText.button,
      labelMedium: PourText.label,
      bodySmall: PourText.caption,
    ),
    iconTheme: const IconThemeData(color: PourColors.text),
    sliderTheme: const SliderThemeData(
      activeTrackColor: PourColors.accent,
      inactiveTrackColor: PourColors.surfaceHigh,
      thumbColor: PourColors.accent,
      trackHeight: 6,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? PourColors.onAccent : PourColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? PourColors.accent : PourColors.surfaceHigh),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PourColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: PourColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.l))),
    ),
  );
}

/// OFL requires the licence to travel with the fonts: show it on the licences page.
void registerFontLicenses() {
  for (final name in ['Fredoka', 'Nunito']) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString('assets/fonts/OFL-$name.txt'));
    });
  }
}
