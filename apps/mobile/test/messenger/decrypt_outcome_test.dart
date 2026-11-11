import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/decrypt_outcome.dart';

// Every place that can turn a failed decrypt into a placeholder body: the
// whole crypto tree, wherever an adapter keeps its session code, plus the
// group coordinator.
Iterable<File> _placeholderSources() => [
      ...Directory('lib/src/core/crypto')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      File('lib/src/features/conversations/data/group_sender_key_coordinator.dart'),
    ];

void main() {
  test('maps every placeholder the adapters emit to its status', () {
    const expected = {
      '[Unable to decrypt: invalid envelope]': MessageContentStatus.failed,
      '[Decryption failed]': MessageContentStatus.failed,
      '[Identity changed — verify safety number]': MessageContentStatus.failed,
      '[Message from a previous group epoch]': MessageContentStatus.failed,
      '[Replayed or out-of-window message]': MessageContentStatus.replayed,
      '[Awaiting sender key — sync required]': MessageContentStatus.awaitingKey,
      '[Session not established — sync required]': MessageContentStatus.sessionMissing,
      '[Crypto bridge unavailable]': MessageContentStatus.sessionMissing,
    };

    for (final entry in expected.entries) {
      expect(classifyDecryptOutcome(entry.key), entry.value, reason: entry.key);
    }
    expect(decryptPlaceholderStatuses, expected);
  });

  test('only missing key material is retried; everything else is final', () {
    final retried = decryptPlaceholderStatuses.values.where((status) => !status.isFinal).toSet();

    expect(retried, {MessageContentStatus.awaitingKey, MessageContentStatus.sessionMissing});
    expect(MessageContentStatus.ok.isFinal, isTrue);
  });

  test('real plaintext is ok, including text that merely looks bracketed', () {
    expect(classifyDecryptOutcome('hello'), MessageContentStatus.ok);
    expect(classifyDecryptOutcome(''), MessageContentStatus.ok);
    expect(classifyDecryptOutcome('[draft] meeting notes'), MessageContentStatus.ok);
    expect(classifyDecryptOutcome('[decryption failed]'), MessageContentStatus.ok);
  });

  test('every bracketed placeholder literal in the decrypt paths is classified', () {
    final literal = RegExp(r"'(\[[^'\]]+\])'");
    final found = <String>{
      for (final file in _placeholderSources())
        ...literal.allMatches(file.readAsStringSync()).map((match) => match.group(1)!),
    };

    expect(found, isNotEmpty);
    for (final placeholder in found) {
      expect(
        decryptPlaceholderStatuses.containsKey(placeholder),
        isTrue,
        reason: '$placeholder would be stored as readable plaintext',
      );
    }
  });
}
