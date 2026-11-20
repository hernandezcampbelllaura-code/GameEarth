import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamingsocial/widgets/reactions.dart';

void main() {
  testWidgets('ReactionSummary muestra emoji y cantidad de cada reacción',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReactionSummary(counts: {'love': 3, 'like': 2}),
      ),
    ));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('👍'), findsOneWidget);
  });

  testWidgets('ReactionSummary no muestra nada sin reacciones', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ReactionSummary(counts: {})),
    ));
    expect(find.byType(Text), findsNothing);
  });
}
