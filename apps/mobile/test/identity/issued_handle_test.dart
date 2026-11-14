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
}
