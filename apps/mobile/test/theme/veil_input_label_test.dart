import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';

// A field's label floats above it while the field is focused and while it
// holds text. Spec rule 1 gives `primaryStrong` to the focused floating
// label only: a filled field the user has left keeps its label in
// `textMuted`, and a field with an error shows it in `danger`, as its
// error text does. The theme once gave the floating label `primaryStrong`
// in every state, so a filled field read as focused (01-choose-handle.png
// in the Play listing showed it).

const _label = 'Handle';

void main() {
  for (final (mode, palette, theme) in [
    ('light', VeilPalette.light, VeilTheme.light()),
    ('dark', VeilPalette.dark, VeilTheme.dark()),
  ]) {
    group('$mode theme', () {
      testWidgets('a filled field the user left keeps its floating label muted', (tester) async {
        final controller = TextEditingController(text: 'alex');
        addTearDown(controller.dispose);
        await tester.pumpWidget(_field(theme, controller: controller));
        await tester.pumpAndSettle();
        expect(_labelColour(tester), palette.textMuted);
      });

      testWidgets('the focused field shows its floating label in the brand text colour', (tester) async {
        final controller = TextEditingController(text: 'alex');
        addTearDown(controller.dispose);
        await tester.pumpWidget(_field(theme, controller: controller));
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(_labelColour(tester), palette.primaryStrong);
      });

      testWidgets('a field with an error shows its floating label in danger, focused or not', (tester) async {
        final controller = TextEditingController(text: 'alex');
        addTearDown(controller.dispose);
        await tester.pumpWidget(_field(theme, controller: controller, error: 'Taken'));
        await tester.pumpAndSettle();
        expect(_labelColour(tester), palette.danger);
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(_labelColour(tester), palette.danger);
      });
    });
  }
}

Widget _field(ThemeData theme, {required TextEditingController controller, String? error}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: _label, errorText: error),
        ),
      ),
    ),
  );
}

Color? _labelColour(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.text(_label)).text.style?.color;
