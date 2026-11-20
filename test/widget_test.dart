import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/game_screen.dart';
import 'package:pour_sand_game/game/sand_screen.dart';
import 'package:pour_sand_game/main.dart';
import 'package:pour_sand_game/meta/progress.dart';
import 'package:pour_sand_game/ui/album_screen.dart';
import 'package:pour_sand_game/ui/brand.dart';
import 'package:pour_sand_game/ui/components.dart';
import 'package:pour_sand_game/ui/settings_screen.dart';

void main() {
  // rootBundle caches asset futures across tests; a future cached in an earlier
  // test's fake-async zone never completes in the next one.
  setUp(() {
    rootBundle.clear();
    progress = Progress();
  });

  testWidgets('home lists the levels', (tester) async {
    await tester.pumpWidget(const PourApp());
    await tester.pumpAndSettle();
    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.byType(LevelNode), findsWidgets);
    expect(find.bySemanticsLabel('Play level 1'), findsOneWidget);
  });

  testWidgets('map refreshes when stars change while it is covered (Next chains)', (tester) async {
    await tester.pumpWidget(const PourApp());
    await tester.pumpAndSettle();
    Finder level2(int stars) => find.byWidgetPredicate((w) => w is LevelNode && w.number == 2 && w.stars == stars);
    expect(level2(0), findsOneWidget);
    progress.recordWin('w1/002', 3, boss: false);
    await tester.pump();
    expect(level2(3), findsOneWidget);
  });

  testWidgets('game screen loads a level with its jar and HUD', (tester) async {
    await tester.pumpWidget(const PourApp(home: GameScreen(paths: ['w1/007'], index: 0, accelStream: Stream.empty())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Valve'), findsOneWidget);
    expect(find.byType(SandGlyph), findsOneWidget);
    expect(find.bySemanticsLabel('Open valve'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Open valve'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Close valve'), findsOneWidget);
  });

  testWidgets('sandbox boots', (tester) async {
    await tester.pumpWidget(const PourApp(home: SandScreen(accelStream: Stream.empty())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Recenter'), findsOneWidget);
  });

  testWidgets('album shows revealed tiles count and names only finished pictures', (tester) async {
    final paths = [for (var i = 1; i <= 60; i++) 'w1/${i.toString().padLeft(3, '0')}'];
    for (var i = 0; i < 10; i++) {
      progress.recordWin(paths[i], 1, boss: false);
    }
    progress.recordWin(paths[10], 1, boss: false);
    await tester.pumpWidget(PourApp(home: AlbumScreen(paths: paths)));
    await tester.pump();
    expect(find.text('Hourglass'), findsOneWidget); // picture 1 complete
    expect(find.text('10/10 tiles'), findsOneWidget);
    expect(find.text('1/10 tiles'), findsOneWidget);
  });

  testWidgets('settings toggles are saved', (tester) async {
    await tester.pumpWidget(const PourApp(home: SettingsScreen()));
    Future<void> toggle(String title) async {
      final row = find.widgetWithText(SwitchListTile, title);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
    }

    await toggle('Vibration');
    expect(progress.settings.haptics, isFalse);
    await toggle('Touch tilt only');
    expect(progress.settings.touchOnly, isTrue);
  });
}
