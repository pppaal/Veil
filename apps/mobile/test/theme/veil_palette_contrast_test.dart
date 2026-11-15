import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/shared/presentation/veil_avatar.dart';

// WCAG 2.x contrast of every pair the design system puts on screen
// (docs/mobile-design-system.md, section 14), in both palettes. Text is held
// to AA (4.5:1); glyphs and shapes that carry no text to 3:1. The next
// palette edit that regresses one of these fails the build.

/// WCAG relative luminance of an opaque colour.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

/// WCAG contrast ratio of [foreground] on [background]; a translucent
/// foreground is composited onto the background first.
double contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final a = _luminance(fg), b = _luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

String _hex(Color color) => '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void _expectAtLeast(double minimum, Color foreground, Color background, String what) {
  final ratio = contrast(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$what: ${_hex(foreground)} on ${_hex(background)} is ${ratio.toStringAsFixed(2)}:1, needs $minimum:1',
  );
}

void main() {
  const aa = 4.5;
  const component = 3.0;

  for (final (name, palette) in [('light', VeilPalette.light), ('dark', VeilPalette.dark)]) {
    group('$name palette', () {
      final pages = {
        'canvas': palette.canvas,
        'canvasAlt': palette.canvasAlt,
        'surface': palette.surface,
        'surfaceAlt': palette.surfaceAlt,
      };

      test('text and muted text read on every page and surface', () {
        for (final MapEntry(key: ground, value: background) in pages.entries) {
          _expectAtLeast(aa, palette.text, background, 'text on $ground');
          _expectAtLeast(aa, palette.textMuted, background, 'textMuted on $ground');
        }
        _expectAtLeast(aa, palette.textMuted, palette.surfaceRaised, 'textMuted on surfaceRaised');
      });

      test('brand text reads on every page and surface', () {
        for (final MapEntry(key: ground, value: background) in pages.entries) {
          _expectAtLeast(aa, palette.primaryStrong, background, 'primaryStrong on $ground');
        }
      });

      test('white reads on the brand fill, and so does the meta of an own bubble', () {
        _expectAtLeast(aa, Colors.white, palette.primary, 'white on primary');
        _expectAtLeast(aa, palette.outgoingMeta, palette.primary, 'outgoingMeta on primary');
      });

      test('the tone colours read on canvas, surface and surfaceAlt', () {
        for (final (tone, color) in [('danger', palette.danger), ('warning', palette.warning), ('success', palette.success)]) {
          for (final ground in ['canvas', 'surface', 'surfaceAlt']) {
            _expectAtLeast(aa, color, pages[ground]!, '$tone on $ground');
          }
        }
      });

      test('subtle text (disabled, chevrons) meets the component threshold on canvas and surface', () {
        _expectAtLeast(component, palette.textSubtle, palette.canvas, 'textSubtle on canvas');
        _expectAtLeast(component, palette.textSubtle, palette.surface, 'textSubtle on surface');
      });

      test('every avatar colour is a visible shape on canvas and surface', () {
        for (final (index, color) in VeilAvatar.colors.indexed) {
          _expectAtLeast(component, color, palette.canvas, 'avatar $index on canvas');
          _expectAtLeast(component, color, palette.surface, 'avatar $index on surface');
        }
      });

      test('a selected segment or chip label reads on its tint over canvas and surface', () {
        for (final (ground, background) in [('canvas', palette.canvas), ('surface', palette.surface)]) {
          final tint = Color.alphaBlend(palette.primarySoft, background);
          _expectAtLeast(aa, palette.primaryStrong, tint, 'primaryStrong on primarySoft over $ground');
        }
      });
    });
  }

  test('a white initial reads on every avatar colour and on the neutral discs', () {
    for (final (index, color) in VeilAvatar.colors.indexed) {
      _expectAtLeast(aa, Colors.white, color, 'white on avatar $index');
    }
    _expectAtLeast(aa, Colors.white, VeilAvatar.neutralLight, 'white on the light neutral disc');
    _expectAtLeast(aa, Colors.white, VeilAvatar.neutralDark, 'white on the dark neutral disc');
  });

  test('sender name tints read on the incoming bubble of their theme', () {
    for (final (index, tint) in VeilAvatar.nameTintsLight.indexed) {
      _expectAtLeast(aa, tint, VeilPalette.light.surfaceAlt, 'light name tint $index on the incoming bubble');
    }
    for (final (index, tint) in VeilAvatar.nameTintsDark.indexed) {
      _expectAtLeast(aa, tint, VeilPalette.dark.surfaceAlt, 'dark name tint $index on the incoming bubble');
    }
  });

  test('the tint tables and the colour table are the same length', () {
    expect(VeilAvatar.nameTintsLight, hasLength(VeilAvatar.colors.length));
    expect(VeilAvatar.nameTintsDark, hasLength(VeilAvatar.colors.length));
  });

  test('both themes write white on the brand fill', () {
    expect(VeilTheme.light().colorScheme.onPrimary, Colors.white);
    expect(VeilTheme.dark().colorScheme.onPrimary, Colors.white);
  });
}
