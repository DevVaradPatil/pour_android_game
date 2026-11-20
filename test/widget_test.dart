import 'package:flutter_test/flutter_test.dart';
import 'package:pour_sand_game/game/sand_screen.dart';
import 'package:pour_sand_game/main.dart';
import 'package:pour_sand_game/ui/brand.dart';

void main() {
  testWidgets('app boots into the sand toy', (tester) async {
    await tester.pumpWidget(const PourApp(home: SandScreen(accelStream: Stream.empty())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsOneWidget);
  });
}
