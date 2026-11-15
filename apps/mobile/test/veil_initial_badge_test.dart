import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/shared/presentation/veil_initial_badge.dart';

// The letter an avatar shows for a name.
void main() {
  test('the initial that stands for a name is its first letter, and never fails on a name with none', () {
    expect(veilInitialOf('selene'), 'S');
    expect(veilInitialOf('@selene'), 'S');
    expect(veilInitialOf('  @ noor'), 'N');
    expect(veilInitialOf('한지우'), '한');
    expect(veilInitialOf('👩‍👩‍👧 family'), '👩‍👩‍👧', reason: 'one character as a person sees it');
    for (final nothing in ['', '   ', '@', ' @ ']) {
      expect(veilInitialOf(nothing), '#', reason: '"$nothing"');
    }
  });
}
