import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/message_padding.dart';
import 'package:veil_mobile/src/core/util/uuid_v4.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';

import '../support/media_fixtures.dart';

// Names a hostile sender might pick, with what the web's sanitizeFilename
// and fileExtension (apps/web-demo/src/domain/sanitize.js) make of them.
// The expected values were produced by running sanitize.js under node once
// and pasted here; the parity test below runs it again on the same table.
final _emoji = '\u{1F600}';
final List<(String name, String sanitized, String extension)> _names = [
  ('report.pdf', 'report.pdf', 'pdf'),
  ('invoice\u{202E}fdp.exe', 'invoicefdp.exe', 'exe'), // right-to-left override
  ('a\u{200E}b.txt', 'ab.txt', 'txt'), // LRM
  ('\u{200F}name.pdf', 'name.pdf', 'pdf'), // RLM
  ('tab\there\nnew.txt', 'tabherenew.txt', 'txt'), // C0
  ('c1\u{0085}x\u{009F}.doc', 'c1x.doc', 'doc'), // C1
  ('del\u{007F}.txt', 'del.txt', 'txt'),
  ('iso\u{2066}late\u{2069}.pdf', 'isolate.pdf', 'pdf'), // isolates
  ('emb\u{202A}ed\u{202C}d.png', 'embedd.png', 'png'), // embedding and pop
  ('${'a' * 121}.pdf', '${'a' * 116}.pdf', 'pdf'), // 125 characters
  ('b' * 121, 'b' * 120, ''),
  ('${'c' * 300}.docx', '${'c' * 115}.docx', 'docx'),
  ('d' * 300, 'd' * 120, ''),
  ('${'e' * 130}.abcdefghijk', 'e' * 120, ''), // an 11-character extension is none
  ('../../etc/passwd', '../../etc/passwd', ''),
  ('a/b\\c.pdf', 'a/b\\c.pdf', 'pdf'),
  ('', 'file', ''),
  ('   ', 'file', ''),
  ('$_emoji$_emoji$_emoji.png', '$_emoji$_emoji$_emoji.png', 'png'),
  ('${_emoji * 130}.pdf', '${_emoji * 116}.pdf', 'pdf'), // characters, not code units
  ('.hidden', '.hidden', ''),
  ('  padded name.txt  ', 'padded name.txt', 'txt'),
  ('UPPER.PDF', 'UPPER.PDF', 'pdf'),
  ('archive.tar.gz', 'archive.tar.gz', 'gz'),
  ('noext.', 'noext.', ''),
  ('weird.ex e', 'weird.ex e', ''),
  ('\u{202E}', 'file', ''),
  ('${'f' * 116}.pdf', '${'f' * 116}.pdf', 'pdf'), // exactly 120: kept
  ('Lease agreement \u{2014} final.pdf', 'Lease agreement \u{2014} final.pdf', 'pdf'),
  ('\u{C0AC}\u{C9C4}.jpeg', '\u{C0AC}\u{C9C4}.jpeg', 'jpeg'),
];

File? _sanitizeScript() {
  for (final candidate in ['../web-demo/src/domain/sanitize.js', 'apps/web-demo/src/domain/sanitize.js']) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute;
  }
  return null;
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('file names, as the web sanitizes them', () {
    test('the table holds every case it is about', () {
      expect(_names.length, greaterThanOrEqualTo(20));
    });

    for (final (index, (name, sanitized, extension)) in _names.indexed) {
      test('name $index', () {
        expect(sanitizeFileName(name), sanitized);
        expect(fileExtension(sanitizeFileName(name)), extension);
        expect(fileTypeLabel(sanitizeFileName(name)), extension.isEmpty ? isNull : extension.toUpperCase());
        // Sanitizing is idempotent: a name that went through once stays.
        expect(sanitizeFileName(sanitized), sanitized);
      });
    }

    test('an empty name falls back to what the caller asks for', () {
      expect(sanitizeFileName(' \u{202E} ', fallback: 'photo'), 'photo');
    });

    final script = _sanitizeScript();
    final node = _hasNode();
    // CI checks out the whole repository with node, so there a missing one
    // fails instead of skipping.
    final skip = (script == null || !node) && Platform.environment['CI'] != 'true'
        ? 'node or apps/web-demo/src/domain/sanitize.js is not available here'
        : null;

    test('the web\'s sanitize.js gives the same answers for the whole table', () async {
      final runner = '''
import { pathToFileURL } from 'node:url';
const { sanitizeFilename, fileExtension } = await import(pathToFileURL(${jsonEncode(script!.path)}).href);
let input = '';
for await (const chunk of process.stdin) input += chunk;
const names = JSON.parse(input);
process.stdout.write(JSON.stringify(names.map((name) => {
  const sanitized = sanitizeFilename(name);
  return [sanitized, fileExtension(sanitized)];
})));
''';
      final process = await Process.start('node', ['--input-type=module', '-e', runner]);
      process.stdin.write(jsonEncode([for (final (name, _, _) in _names) name]));
      await process.stdin.close();
      final output = await process.stdout.transform(utf8.decoder).join();
      final errors = await process.stderr.transform(utf8.decoder).join();
      expect(await process.exitCode, 0, reason: errors);
      final web = (jsonDecode(output) as List).cast<List>();
      expect(web, hasLength(_names.length));
      for (final (index, (name, sanitized, extension)) in _names.indexed) {
        expect(web[index], [sanitized, extension], reason: 'pasted row $index differs from sanitize.js');
        expect(web[index], [sanitizeFileName(name), fileExtension(sanitizeFileName(name))], reason: 'row $index');
      }
    }, skip: skip);
  });

  group('local copy names', () {
    test('120 emoji and an extension fit in 200 bytes and keep the extension', () {
      final name = safeLocalFileName(sanitizeFileName('${_emoji * 120}.pdf'));
      expect(utf8.encode(name).length, lessThanOrEqualTo(kMaxLocalNameBytes));
      expect(name, endsWith('.pdf'));
      // Valid UTF-8, no code point split: it decodes strictly and back.
      expect(utf8.decode(utf8.encode(name)), name);
      expect(name.runes.where((rune) => rune == 0xFFFD), isEmpty);
      expect(name.replaceAll('.pdf', '').runes.every((rune) => rune == 0x1F600), isTrue);
    });

    test('separators, colons and NUL are replaced and leading dots go', () {
      expect(safeLocalFileName('a/b\\c.pdf'), 'a_b_c.pdf');
      expect(safeLocalFileName('../../etc/passwd'), '_.._etc_passwd');
      expect(safeLocalFileName('C:report.txt'), 'C_report.txt');
      expect(safeLocalFileName('nul\u{0000}byte.txt'), 'nul_byte.txt');
      expect(safeLocalFileName('.hidden'), 'hidden');
      expect(safeLocalFileName('...'), 'file');
      expect(safeLocalFileName(''), 'file');
      expect(safeLocalFileName('report.pdf'), 'report.pdf');
    });

    test('a long name without an extension is cut to 200 bytes', () {
      final name = safeLocalFileName('\u{C0AC}' * 150); // 3 bytes each
      expect(utf8.encode(name).length, lessThanOrEqualTo(kMaxLocalNameBytes));
      expect(utf8.encode(name).length, greaterThan(kMaxLocalNameBytes - 3));
      expect(name.runes.toSet(), {0xC0AC});
    });

    test('dots split by spaces are stripped too, so no name is "." or ".."', () {
      // The web sanitizer keeps these as they are (or only trims them).
      expect(safeLocalFileName(sanitizeFileName('. ..')), 'file');
      expect(safeLocalFileName(sanitizeFileName('. .')), 'file');
      expect(safeLocalFileName(sanitizeFileName(' . .. ')), 'file');
      expect(safeLocalFileName(sanitizeFileName('.. ..')), 'file');
      expect(safeLocalFileName(sanitizeFileName('. .pdf')), 'pdf');
      expect(safeLocalFileName(sanitizeFileName('.. ..hidden')), 'hidden');
      expect(safeLocalFileName('.\u{3000}.\u{00A0}..x.txt'), 'x.txt');
      // Long enough to be cut: the cut keeps the stripped start.
      final long = safeLocalFileName('. . ${'g' * 300}.pdf');
      expect(long, startsWith('g'));
      expect(long, endsWith('.pdf'));
      expect(utf8.encode(long).length, lessThanOrEqualTo(kMaxLocalNameBytes));
    });

    test('no result reaches outside its folder', () {
      const folder = '/tmp/veil_open/abcdefghijklmnopqrstuvwx';
      final hostile = [
        '. ..', '. .', ' . .. ', '.. ..', '. .pdf', '.. ..hidden', '. . .', '.\t.', '.\u{3000}..',
        '..', '.', '. ../x', '..\u{200E} ..', '\u{202E}. ..', '. ..${'h' * 300}',
      ];
      for (final name in [for (final (name, _, _) in _names) name, ...hostile]) {
        final local = safeLocalFileName(sanitizeFileName(name));
        expect(local, isNot(contains('/')), reason: name);
        expect(local, isNot(contains('\\')), reason: name);
        expect(local, isNot(startsWith('.')), reason: name);
        expect(local, isNot(anyOf('.', '..')), reason: name);
        expect(local, isNotEmpty, reason: name);
        expect(local.trim(), local, reason: name);
        expect(utf8.encode(local).length, lessThanOrEqualTo(kMaxLocalNameBytes), reason: name);
        expect(p.isWithin(folder, p.join(folder, local)), isTrue, reason: name);
      }
    });
  });

  group('content types', () {
    test('come from the extension through a fixed map', () {
      expect(contentTypeForName('report.pdf'), 'application/pdf');
      expect(contentTypeForName('REPORT.PDF'), 'application/pdf');
      expect(contentTypeForName('notes.docx'), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(contentTypeForName('clip.mov'), 'video/quicktime');
      expect(contentTypeForName('photo.HEIC'), 'image/heic');
      expect(contentTypeForName('book.epub'), 'application/epub+zip');
      expect(contentTypeForName('tool.exe'), 'application/octet-stream');
      expect(contentTypeForName('noext'), 'application/octet-stream');
      expect(contentTypeForName('.hidden'), 'application/octet-stream');
    });
  });

  group('sniffing', () {
    final jpeg = jpegWithMetadata(width: 8, height: 6);
    final png = pngWithAlpha(width: 4, height: 4);
    final webp = [...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBPVP8 ')];
    final gif = ascii.encode('GIF89a......');
    final bmp = [...ascii.encode('BM'), 0, 0, 0, 0];
    final tiffLittle = [0x49, 0x49, 0x2a, 0x00, 8, 0, 0, 0];
    final tiffBig = [0x4d, 0x4d, 0x00, 0x2a, 0, 0, 0, 8];
    List<int> ftyp(String major, [List<String> compatible = const []]) {
      final size = 16 + 4 * compatible.length;
      return [0, 0, 0, size, ...ascii.encode('ftyp'), ...ascii.encode(major), 0, 0, 0, 0,
        for (final brand in compatible) ...ascii.encode(brand)];
    }

    test('only JPEG, PNG and WebP are images the app draws, by their bytes', () {
      expect(sniffImageType(jpeg), 'image/jpeg');
      expect(sniffImageType(png), 'image/png');
      expect(sniffImageType(webp), 'image/webp');
      for (final other in [gif, bmp, tiffLittle, heicHead(), mp4Head(), notAnImage(), pdfBytes('x'), <int>[]]) {
        expect(sniffImageType(other), isNull);
      }
      expect(sniffImageType([...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WAVE')]), isNull);
    });

    test('photos and videos picked as files are told by bytes or extension', () {
      for (final head in [
        jpeg, png, webp, tiffLittle, tiffBig, heicHead(), mp4Head(), //
        for (final brand in ['heic', 'heix', 'mif1', 'msf1', 'isom', 'iso2', 'mp41', 'mp42', 'qt  ', '3gp4', '3gp5', 'M4V '])
          ftyp(brand),
        ftyp('avc1', ['isom']), // a compatible brand counts too
      ]) {
        expect(looksLikePhotoOrVideo(head, 'file.bin'), isTrue, reason: '$head');
      }
      for (final extension in ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'tif', 'tiff', 'dng', 'mp4', 'mov', 'm4v', '3gp']) {
        expect(looksLikePhotoOrVideo(const [], 'clip.$extension'), isTrue, reason: extension);
        expect(looksLikePhotoOrVideo(const [], 'CLIP.${extension.toUpperCase()}'), isTrue, reason: extension);
      }
      expect(looksLikePhotoOrVideo(pdfBytes('x'), 'report.pdf'), isFalse);
      expect(looksLikePhotoOrVideo(notAnImage(), 'page.html'), isFalse);
      expect(looksLikePhotoOrVideo(gif, 'anim.gif'), isFalse);
      expect(looksLikePhotoOrVideo(ftyp('crx '), 'x.bin'), isFalse);
    });

    test('iOS keeps every image and video away from Quick Look, GIF and BMP included', () {
      for (final head in [
        jpeg, png, webp, tiffLittle, heicHead(), mp4Head(), gif, ascii.encode('GIF87a'), bmp, //
        ftyp('avif'), ftyp('avis'), ftyp('mif1', ['avif']), ftyp('3g2a'),
        const [0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a], // JPEG 2000
        const [0xff, 0x4f, 0xff, 0x51], // its codestream
        const [0x00, 0x00, 0x01, 0x00, 0x01, 0x00], // ICO
        ascii.encode('8BPS'), // PSD
        const [0x00, 0x00, 0x01, 0xba], const [0x00, 0x00, 0x01, 0xb3], // MPEG
      ]) {
        expect(isImageOrVideoForQuickLook(head, 'file.bin'), isTrue, reason: '$head');
      }
      for (final extension in [
        'heic', 'heif', 'gif', 'tif', 'tiff', 'bmp', 'dng', 'mp4', 'mov', 'm4v', '3gp', //
        'avif', 'jp2', 'j2k', 'jpf', 'jpx', 'ico', 'psd', '3g2', 'mpg', 'mpeg',
      ]) {
        expect(isImageOrVideoForQuickLook(const [], 'file.$extension'), isTrue, reason: extension);
      }
      expect(isImageOrVideoForQuickLook(pdfBytes('x'), 'report.pdf'), isFalse);
      expect(isImageOrVideoForQuickLook(ascii.encode('PK\u{0003}\u{0004}'), 'notes.docx'), isFalse);
    });
  });

  group('limits', () {
    test('render limits: a JPEG may be large, a PNG or WebP much less', () {
      expect(withinRenderLimits('image/png', 7000, 7000), isFalse); // 49 MP
      expect(withinRenderLimits('image/jpeg', 6000, 8000), isTrue); // 48 MP, decoded scaled
      expect(withinRenderLimits('image/png', 8193, 100), isFalse);
      expect(withinRenderLimits('image/webp', 100, 8193), isFalse);
      expect(withinRenderLimits('image/png', 8192, 1953), isTrue); // 15.99 MP
      expect(withinRenderLimits('image/png', 4000, 4001), isFalse); // just over 16 MP
      expect(withinRenderLimits('image/jpeg', 16385, 100), isFalse);
      expect(withinRenderLimits('image/jpeg', 16384, 3051), isTrue); // 49.99 MP
      expect(withinRenderLimits('image/jpeg', 7072, 7071), isFalse); // just over 50 MP
      expect(withinRenderLimits('image/gif', 10, 10), isFalse);
      expect(withinRenderLimits('image/jpeg', 0, 10), isFalse);
    });

    test('source limits: 200 MP for a JPEG, 40 MP for anything else', () {
      expect(withinSourceLimits(isJpeg: true, width: 15000, height: 10000), isTrue); // 150 MP
      expect(withinSourceLimits(isJpeg: true, width: 20000, height: 10000), isTrue); // 200 MP
      expect(withinSourceLimits(isJpeg: true, width: 20001, height: 10000), isFalse);
      expect(withinSourceLimits(isJpeg: false, width: 7000, height: 7000), isFalse); // 49 MP
      expect(withinSourceLimits(isJpeg: false, width: 8000, height: 5000), isTrue); // 40 MP
      expect(withinSourceLimits(isJpeg: false, width: 8001, height: 5000), isFalse);
      expect(withinSourceLimits(isJpeg: false, width: 0, height: 5000), isFalse);
    });

    test('the most ciphertext a pointer allows follows the cipher\'s padding', () {
      for (final size in [0, 1, 255, 256, 1000, 65535, 1 << 20, kMaxPhotoBytes, kMaxFileBytes]) {
        expect(maxCiphertextBytes(size), MessagePadding.padmeLength(size + 1) + 16, reason: '$size');
      }
      expect(maxCiphertextBytes(kMaxAttachmentBytes), kMaxAttachmentBytes);
      expect(maxCiphertextBytes(1 << 40), kMaxAttachmentBytes);
    });

    test('a real sealed blob is exactly as long as the bound says', () async {
      for (final size in [0, 17, 4096, 70000]) {
        final sealed = await sealV2(List<int>.filled(size, 7), attachmentId: randomUuidV4(), contentType: 'application/pdf');
        expect(sealed.blob.length, maxCiphertextBytes(size), reason: '$size');
      }
    });

    test('constants say what the decisions say', () {
      expect(kMaxFileBytes, 26214400);
      expect(kMaxPhotoBytes, 10485760);
      expect(kMaxAttachmentBytes, 52428800);
      expect(kPhotoMaxEdge, 1600);
      expect(kPhotoJpegQuality, 80);
      expect(kViewerMaxEdge, 4096);
      expect(kAttachmentAlgorithmV2, 'aes256gcm-v2');
    });
  });

  group('attachment ids', () {
    test('are UUIDs, in either case', () {
      expect(isAttachmentId('3f2504e0-4f89-41d3-9a0c-0305e82c3301'), isTrue);
      expect(isAttachmentId('3F2504E0-4F89-41D3-9A0C-0305E82C3301'), isTrue);
      expect(isAttachmentId(randomUuidV4()), isTrue);
      for (final bad in ['', '../keys/x', '3f2504e0-4f89-41d3-9a0c-0305e82c330', '3f2504e0-4f89-41d3-9a0c-0305e82c3301\n',
        '3f2504e04f8941d39a0c0305e82c3301', '3f2504e0-4f89-41d3-9a0c-0305e82c330g', ' 3f2504e0-4f89-41d3-9a0c-0305e82c3301']) {
        expect(isAttachmentId(bad), isFalse, reason: bad);
        expect(isUuidString(bad), isFalse, reason: bad);
      }
    });
  });
}
