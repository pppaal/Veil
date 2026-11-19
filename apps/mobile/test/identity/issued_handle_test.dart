import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/identity/issued_handle.dart';

void main() {
  test('is the grammar the API registers handles in', () {
    final dto = File('../api/src/modules/auth/dto/register.dto.ts').readAsStringSync();
    final handleRule = RegExp(r'@Length\((\d+), (\d+)\)\s*@Matches\(/(.+)/\)\s*handle!: string;').firstMatch(dto);
    expect(handleRule, isNotNull, reason: 'RegisterDto.handle no longer reads as @Length + @Matches');
    expect(int.parse(handleRule!.group(1)!), issuedHandleMinLength);
    expect(int.parse(handleRule.group(2)!), issuedHandleMaxLength);
    expect(handleRule.group(3), issuedHandlePattern.pattern);
  });

  test('admits what an honest relay issues, and nothing that only looks like it', () {
    for (final handle in ['bob', 'veil.operator', 'a_b.c9', 'x' * 32]) {
      expect(isIssuableHandle(handle), isTrue, reason: handle);
    }
    for (final handle in [
      'b\u043eb', // a Cyrillic o
      'bob\u200b', // a zero-width space
      '\u202ebob', // a right-to-left override
      'bob ',
      'Bob',
      'a..b',
      '.bob',
      'bob_',
      'ab',
      'x' * 33,
      '',
    ]) {
      expect(isIssuableHandle(handle), isFalse, reason: handle);
    }
  });

  group('handleRuleBroken', () {
    test('names the first rule a handle breaks, as the web sign-in does', () {
      // The same cases as apps/web-demo/__tests__/handles.test.js.
      final cases = <String, HandleRule?>{
        '': HandleRule.characters,
        'ab': HandleRule.characters,
        'x' * 33: HandleRule.characters,
        'bad-handle': HandleRule.characters,
        'with space': HandleRule.characters,
        'Bob': HandleRule.characters,
        'b\u00f3b': HandleRule.characters,
        '..': HandleRule.characters,
        '_bob': HandleRule.edges,
        'bob.': HandleRule.edges,
        '.b.': HandleRule.edges,
        'b..ob': HandleRule.run,
        'b._ob': HandleRule.run,
        'b__ob': HandleRule.run,
        'veil.operator': null,
        'a_b': null,
        '123': null,
        'x' * 32: null,
      };
      for (final MapEntry(key: handle, value: rule) in cases.entries) {
        expect(handleRuleBroken(handle), rule, reason: handle);
      }
    });

    test('passes exactly the handles the relay registers', () {
      // Every string of up to 5 characters over an alphabet that reaches
      // each rule, and a few at the length limits.
      const alphabet = ['a', '1', '.', '_', '-', 'A'];
      var strings = [''];
      final all = [''];
      for (var length = 1; length <= 5; length += 1) {
        strings = [
          for (final prefix in strings)
            for (final character in alphabet) prefix + character,
        ];
        all.addAll(strings);
      }
      all.addAll(['${'a' * 31}.', '${'a' * 31}b', 'a.${'b' * 30}', 'a.${'b' * 31}']);
      for (final handle in all) {
        expect(handleRuleBroken(handle) == null, isIssuableHandle(handle), reason: handle);
      }
    });
  });
}
