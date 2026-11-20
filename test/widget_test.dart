import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/game_screen.dart';
import 'package:pour_sand_game/game/sand_screen.dart';
import 'package:pour_sand_game/main.dart';
import 'package:pour_sand_game/ui/brand.dart';
import 'package:pour_sand_game/ui/components.dart';

void main() {
  testWidgets('home lists the levels', (tester) async {
    await tester.pumpWidget(const PourApp());
    await tester.pumpAndSettle();
    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.byType(LevelNode), findsWidgets);
    expect(find.bySemanticsLabel('Play level 1'), findsOneWidget);
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
}
