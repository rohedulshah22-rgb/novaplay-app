import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novaplay/app.dart';

void main() {
  testWidgets('NovaPlay renders the offline cinema home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NovaPlayApp()));
    expect(find.text('NovaPlay'), findsOneWidget);
    expect(find.text('Your offline cinema'), findsOneWidget);
  });
}
