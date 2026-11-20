// Golden snapshot of the whole design system. Regenerate after intended UI changes:
//   flutter test test/ui/gallery_golden_test.dart --update-goldens
// Font rasterization differs per OS; goldens are generated on Windows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/ui/gallery_screen.dart';
import 'package:pour_sand_game/ui/theme.dart';

Future<void> loadFonts() async {
  for (final (family, path) in [
    ('Fredoka', 'assets/fonts/Fredoka.ttf'),
    ('Nunito', 'assets/fonts/Nunito.ttf'),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(path))).load();
  }
}

void main() {
  testWidgets('design system gallery', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(720, 2900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildPourTheme(),
      home: const GalleryScreen(scrollable: false),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(GalleryScreen), matchesGoldenFile('goldens/gallery.png'));
  });
}
