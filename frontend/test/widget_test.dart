import 'package:flutter_test/flutter_test.dart';
import 'package:areyoughost/main.dart';
import 'package:areyoughost/ui/home/home.dart';

void main() {
  testWidgets('App boots to HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const AreYouGhostApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
