import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamingsocial/widgets/reactions.dart';
import 'package:gamingsocial/screens/help_screen.dart';

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

  testWidgets('Ayuda: busca preguntas y muestra el botón de preguntar',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    expect(find.text('¿Cómo inicio sesión?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'contraseña');
    await tester.pump();
    expect(find.text('Olvidé mi contraseña'), findsOneWidget);
    expect(find.text('¿Cómo inicio sesión?'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzzxxyy');
    await tester.pump();
    expect(find.textContaining('No encontramos'), findsOneWidget);
    expect(find.textContaining('Pregunta aquí'), findsOneWidget);
  });
}
