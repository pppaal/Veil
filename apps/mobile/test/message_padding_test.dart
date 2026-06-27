import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';

void main() {
  group('MessagePadding.bucketFor', () {
    test('clamps small sizes up to the minimum bucket', () {
      expect(MessagePadding.bucketFor(0), 256);
      expect(MessagePadding.bucketFor(1), 256);
      expect(MessagePadding.bucketFor(256), 256);
    });

    test('doubles up the ladder', () {
      expect(MessagePadding.bucketFor(257), 512);
      expect(MessagePadding.bucketFor(512), 512);
      expect(MessagePadding.bucketFor(513), 1024);
      expect(MessagePadding.bucketFor(65536), 65536);
    });

    test('rounds to 64 KiB steps above the ladder', () {
      expect(MessagePadding.bucketFor(65537), 131072);
      expect(MessagePadding.bucketFor(131072), 131072);
      expect(MessagePadding.bucketFor(131073), 196608);
    });
  });

  group('MessagePadding.pad / unpad', () {
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

    test('round-trips arbitrary content', () {
      for (final s in <String>[
        '',
        'ok',
        '응',
        '{"body":"hello","kind":"text"}',
        'a' * 255,
        'b' * 256,
        'c' * 257,
        'd' * 5000,
        '🔐' * 100,
      ]) {
        final original = bytes(s);
        final padded = MessagePadding.pad(original);
        expect(MessagePadding.unpad(padded), equals(original), reason: 'len=${original.length}');
      }
    });

    test('pads to the expected bucket and always adds the delimiter', () {
      final padded = MessagePadding.pad(bytes('hello')); // 5 bytes
      expect(padded.length, 256);
      expect(padded[5], 0x80);
    });

    test('short messages are all the same padded size (size hiding)', () {
      final a = MessagePadding.pad(bytes('y'));
      final b = MessagePadding.pad(bytes('a much longer but still short reply'));
      expect(a.length, b.length);
      expect(a.length, 256);
    });

    test('plaintext ending in 0x00 round-trips', () {
      final original = Uint8List.fromList([1, 2, 3, 0x00]);
      expect(MessagePadding.unpad(MessagePadding.pad(original)), equals(original));
    });

    test('plaintext ending in 0x80 round-trips', () {
      final original = Uint8List.fromList([1, 2, 0x80]);
      expect(MessagePadding.unpad(MessagePadding.pad(original)), equals(original));
    });

    test('exact-fit input (bucket - 1) keeps the delimiter without filler', () {
      final original = Uint8List(255); // +1 delimiter == 256 bucket
      final padded = MessagePadding.pad(original);
      expect(padded.length, 256);
      expect(padded[255], 0x80);
      expect(MessagePadding.unpad(padded), equals(original));
    });

    test('lenient: legacy unpadded JSON is returned unchanged', () {
      final legacy = bytes('{"body":"hi","kind":"text"}'); // ends in }
      expect(MessagePadding.unpad(legacy), equals(legacy));
    });
  });
}
