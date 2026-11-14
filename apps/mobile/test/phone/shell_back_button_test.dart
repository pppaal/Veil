import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';

// A screen that was pushed can be left from its bar: a phone has no other
// visible way back on iOS, and none at all inside a modal page.

void main() {
  testWidgets('a pushed screen gets a back button, the first screen none', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VeilTheme.dark(),
        home: Builder(
          builder: (context) => VeilShell(
            title: 'First',
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const VeilShell(title: 'Second', child: Text('second body'))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(VeilBackButton), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('second body'), findsOneWidget);
    expect(find.byType(VeilBackButton), findsOneWidget);
    expect(tester.getSize(find.byType(VeilBackButton)).shortestSide, greaterThanOrEqualTo(44));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('second body'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a screen can put its own control in the back button\'s place', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VeilTheme.dark(),
        home: VeilShell(
          titleWidget: const Text('searching'),
          leading: VeilBackButton(onPressed: () => closed++),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.text('searching'), findsOneWidget);

    await tester.tap(find.byType(VeilBackButton));
    expect(closed, 1);
  });
}
