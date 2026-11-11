import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/util/keyed_async_lock.dart';

void main() {
  test('actions on one key run one at a time, in call order', () async {
    final lock = KeyedAsyncLock<String>();
    final events = <String>[];
    Future<void> step(String name) => lock.synchronized('k', () async {
          events.add('$name:start');
          await Future<void>.delayed(const Duration(milliseconds: 2));
          events.add('$name:end');
        });

    await Future.wait([step('a'), step('b'), step('c')]);
    expect(events, ['a:start', 'a:end', 'b:start', 'b:end', 'c:start', 'c:end']);
  });

  test('different keys do not wait for each other', () async {
    final lock = KeyedAsyncLock<String>();
    final release = Completer<void>();
    final blocked = lock.synchronized('a', () => release.future);

    expect(await lock.synchronized('b', () async => 'ran'), 'ran');
    release.complete();
    await blocked;
  });

  test('a failing action releases the key and surfaces its error', () async {
    final lock = KeyedAsyncLock<String>();
    final failing = lock.synchronized<void>('k', () async => throw StateError('boom'));
    final next = lock.synchronized('k', () async => 'after');

    await expectLater(failing, throwsStateError);
    expect(await next, 'after');
  });
}
