import 'dart:convert';

import 'package:flutter/material.dart';

/// The letter that stands for [name] where there is no picture: its first
/// character, without the `@` of a handle. A name with nothing to show
/// (empty, blank, a lone `@`) gets `#`.
String veilInitialOf(String name) {
  final trimmed = name.trim();
  final bare = trimmed.startsWith('@') ? trimmed.substring(1).trim() : trimmed;
  return bare.isEmpty ? '#' : bare.characters.first.toUpperCase();
}

/// FNV-1a, 32 bits, of the UTF-8 bytes of [text]. `String.hashCode` is not
/// stable across platforms; this is, so a person has the same colour on
/// every device and in the web demo.
int veilFnv1a32(String text) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// A person or a group where there is no picture: a flat solid disc with a
/// white initial, the same in both themes. The colour is chosen by
/// [seed] (the handle) through FNV-1a, so it is stable everywhere.
///
/// Sizes: 32 in the chat bar and beside group bubbles, 40 in contact rows
/// and sheets, 48 in conversation rows, 56 on the safety number and
/// contact sheet headers, 72 on the profile. A group shows a neutral disc
/// with a group glyph, never a letter; so does an unknown sender, with a
/// person glyph ([unknown]).
///
/// The avatar says nothing to a screen reader: the row carries the label.
class VeilAvatar extends StatelessWidget {
  const VeilAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 40,
    this.group = false,
    this.unknown = false,
  });

  final String name;
  final String seed;
  final double size;
  final bool group;
  final bool unknown;

  /// The eight disc colours: each reads with a white initial at 4.5:1 or
  /// more and as a shape at 3:1 or more against black, #1C1C1E, white and
  /// #F2F2F7.
  static const List<Color> colors = [
    Color(0xFF4F6D8F),
    Color(0xFF7A5C9A),
    Color(0xFFA4573F),
    Color(0xFF3E7D62),
    Color(0xFF8A6D2F),
    Color(0xFF2F7C8A),
    Color(0xFF9E4F70),
    Color(0xFF5E7A3A),
  ];

  /// Sender names in group bubbles, on the incoming bubble fill of the
  /// light theme (#E9E9EB): the disc colours fail AA as 15sp text, these
  /// pass.
  static const List<Color> nameTintsLight = [
    Color(0xFF3B5673),
    Color(0xFF5B4479),
    Color(0xFF7F4030),
    Color(0xFF2C5D47),
    Color(0xFF674F22),
    Color(0xFF1F5E69),
    Color(0xFF7A3C58),
    Color(0xFF45602A),
  ];

  /// The same, on the incoming bubble fill of the dark theme (#26262B).
  static const List<Color> nameTintsDark = [
    Color(0xFF8FB0D6),
    Color(0xFFB9A0DB),
    Color(0xFFE09A85),
    Color(0xFF7FC3A6),
    Color(0xFFD1B06B),
    Color(0xFF7CC2CF),
    Color(0xFFDB94B3),
    Color(0xFFA3C07C),
  ];

  /// The neutral disc of a group or an unknown sender.
  static const Color neutralLight = Color(0xFF6E6E73);
  static const Color neutralDark = Color(0xFF48484A);

  /// Which of the eight colours [seed] gets.
  static int indexOf(String seed) => veilFnv1a32(seed) % colors.length;

  /// The disc colour of [seed].
  static Color colorOf(String seed) => colors[indexOf(seed)];

  /// The colour a sender's name is drawn in above their bubble.
  static Color nameTint(BuildContext context, String seed) {
    final tints = Theme.of(context).brightness == Brightness.dark ? nameTintsDark : nameTintsLight;
    return tints[indexOf(seed)];
  }

  @override
  Widget build(BuildContext context) {
    final neutral = group || unknown;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = neutral ? (dark ? neutralDark : neutralLight) : colorOf(seed);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
        child: neutral
            ? Icon(group ? Icons.group_outlined : Icons.person_outline, size: size * 0.5, color: Colors.white)
            : Text(
                veilInitialOf(name),
                style: TextStyle(
                  fontSize: size * 0.42,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
