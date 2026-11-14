import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/shared/presentation/veil_first_fit.dart';

// VeilFirstThatFits shows the roomy form of something while it fits the
// height it is given and the tight form when it does not, and only the form
// shown exists for a finger, a screen reader, the keyboard and a finder.

void main() {
  var roomyTaps = 0;
  var tightTaps = 0;

  Widget app(double height) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // Up to this height, as under a ConstrainedBox in a column.
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 300, maxHeight: height),
              child: VeilFirstThatFits(
                children: [
                  SizedBox(
                    height: 120,
                    child: TextButton(onPressed: () => roomyTaps++, child: const Text('Roomy')),
                  ),
                  SingleChildScrollView(
                    child: SizedBox(
                      height: 60,
                      child: TextButton(onPressed: () => tightTaps++, child: const Text('Tight')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  setUp(() {
    roomyTaps = 0;
    tightTaps = 0;
  });

  testWidgets('shows the first form while it fits, at exactly its height too', (tester) async {
    for (final height in [300.0, 120.0]) {
      await tester.pumpWidget(app(height));
      await tester.pump();
      expect(find.text('Roomy'), findsOneWidget);
      expect(find.text('Tight'), findsNothing, reason: 'not found by a finder that skips what is off stage');
      expect(find.text('Tight', skipOffstage: false), findsOneWidget, reason: 'built all the same');
      expect(tester.getSize(find.byType(VeilFirstThatFits)).height, 120);
    }
    await tester.tap(find.text('Roomy'));
    expect((roomyTaps, tightTaps), (1, 0));
  });

  testWidgets('shows the next form when the first would be cut off, and takes only its height', (tester) async {
    await tester.pumpWidget(app(119));
    await tester.pump();
    expect(find.text('Tight'), findsOneWidget);
    expect(find.text('Roomy'), findsNothing);
    expect(tester.getSize(find.byType(VeilFirstThatFits)).height, 60);

    await tester.tapAt(tester.getCenter(find.byType(VeilFirstThatFits)));
    expect((roomyTaps, tightTaps), (0, 1), reason: 'a tap reaches the form shown and no other');
  });

  testWidgets('the last form makes do with the height there is', (tester) async {
    await tester.pumpWidget(app(40));
    await tester.pump();
    expect(find.text('Tight'), findsOneWidget);
    expect(tester.getSize(find.byType(VeilFirstThatFits)).height, 40);
    expect(tester.takeException(), isNull, reason: 'it scrolls; nothing overflows');
  });

  testWidgets('follows the height as it changes, in the frame it changes', (tester) async {
    await tester.pumpWidget(app(300));
    expect(find.text('Roomy'), findsOneWidget);
    await tester.pumpWidget(app(100));
    expect(find.text('Tight'), findsOneWidget);
    expect(find.text('Roomy'), findsNothing);
    await tester.pumpWidget(app(300));
    expect(find.text('Roomy'), findsOneWidget);
    expect(find.text('Tight'), findsNothing);
  });

  testWidgets('reads only the form shown to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(app(300));
    await tester.pump();
    expect(find.bySemanticsLabel('Roomy'), findsOneWidget);
    expect(find.bySemanticsLabel('Tight'), findsNothing);

    await tester.pumpWidget(app(100));
    await tester.pump();
    expect(find.bySemanticsLabel('Tight'), findsOneWidget);
    expect(find.bySemanticsLabel('Roomy'), findsNothing);
    handle.dispose();
  });

  testWidgets('keeps keyboard focus out of the form that is not shown', (tester) async {
    bool focusable(String label) => Focus.of(tester.element(find.text(label, skipOffstage: false))).canRequestFocus;

    await tester.pumpWidget(app(300));
    await tester.pump();
    expect(focusable('Roomy'), isTrue);
    expect(focusable('Tight'), isFalse);

    await tester.pumpWidget(app(100));
    // Focus follows layout by one frame.
    await tester.pump();
    expect(focusable('Tight'), isTrue);
    expect(focusable('Roomy'), isFalse);
  });

  testWidgets('measures a form by what it would take, not by what it is given', (tester) async {
    // A column that would take 150 is not squeezed into 100 and called a fit.
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 100),
          child: VeilFirstThatFits(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: const [SizedBox(height: 75, child: Text('a')), SizedBox(height: 75, child: Text('b'))],
              ),
              const SizedBox(height: 20, child: Text('short')),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('short'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.renderObject<RenderBox>(find.byType(VeilFirstThatFits)).size.height, 20);
  });
}
