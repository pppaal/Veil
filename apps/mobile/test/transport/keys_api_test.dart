import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';

/// Records each authenticated call KeysApi makes and answers with [answer].
class _Recorder extends VeilApiClient {
  _Recorder(this.answer) : super(baseUrl: 'http://relay.invalid/v1');

  Map<String, dynamic> answer;
  final List<String> calls = [];
  Object? lastBody;

  @override
  Future<Map<String, dynamic>> getJson(String path, {required String? accessToken, Map<String, String>? query}) async {
    calls.add('GET $path ${query ?? {}} $accessToken');
    return answer;
  }

  @override
  Future<Map<String, dynamic>> postJson(String path, {required String? accessToken, Object? body}) async {
    calls.add('POST $path');
    lastBody = body;
    return answer;
  }

  @override
  Future<Map<String, dynamic>> putJson(String path, {required String? accessToken, Object? body}) async {
    calls.add('PUT $path');
    lastBody = body;
    return answer;
  }
}

Map<String, dynamic> _entry({List<Map<String, dynamic>>? devices}) => {
      'user': {'id': 'user-selene', 'handle': 'selene', 'activeDeviceId': 'dev-2'},
      'devices': devices ??
          [
            {
              'deviceId': 'dev-2',
              'identityPublicKey': 'ik-2',
              'signedPrekeyBundle': 'spk-2',
              'isActive': true,
              'oneTimePrekey': {'keyId': 41, 'publicKey': 'opk-41'},
            },
            {
              'deviceId': 'dev-1',
              'identityPublicKey': 'ik-1',
              'signedPrekeyBundle': 'spk-1',
              'isActive': false,
              'oneTimePrekey': null,
            },
          ],
    };

void main() {
  final codec = LibCryptoAdapter().keyBundles;

  test('lookup reads the active device, its claimed prekey and the other trusted devices', () async {
    final client = _Recorder(_entry());

    final entry = await KeysApi(client, codec).lookup('selene', accessToken: 'token', claim: KeyClaim.active);

    expect(client.calls.single, 'GET /keys/selene {claim: active} token');
    final active = entry.activeDevice!;
    expect(active.bundle.userId, 'user-selene');
    expect(active.bundle.handle, 'selene');
    expect(active.bundle.identityPublicKey, 'ik-2');
    expect(active.oneTimePrekey?.keyId, 41);
    expect(entry.device('dev-1')!.oneTimePrekey, isNull);
  });

  test('an answer that does not name its active device among the listed ones has none', () async {
    final client = _Recorder(_entry(devices: [
      {'deviceId': 'dev-ghost', 'identityPublicKey': 'ik', 'signedPrekeyBundle': 'spk', 'isActive': false, 'oneTimePrekey': null},
    ]));

    final entry = await KeysApi(client, codec).lookup('selene', accessToken: 'token');

    expect(entry.activeDevice, isNull, reason: 'never a fallback to another device');
  });

  test('a malformed answer is refused, not guessed', () async {
    for (final answer in [
      <String, dynamic>{'devices': []},
      {
        'user': {'id': 'user-selene', 'handle': 'selene', 'activeDeviceId': 'dev-2'},
        'devices': 'nope',
      },
      _entry(devices: [
        {'deviceId': 'dev-2', 'identityPublicKey': '', 'signedPrekeyBundle': 'spk', 'isActive': true, 'oneTimePrekey': null},
      ]),
      _entry(devices: [
        {
          'deviceId': 'dev-2',
          'identityPublicKey': 'ik',
          'signedPrekeyBundle': 'spk',
          'isActive': true,
          'oneTimePrekey': {'keyId': -1, 'publicKey': 'x'},
        },
      ]),
    ]) {
      await expectLater(
        KeysApi(_Recorder(answer), codec).lookup('selene', accessToken: 'token'),
        throwsFormatException,
      );
    }
  });

  test('prekey upload, count and signed-prekey rotation use the device routes', () async {
    final client = _Recorder({'uploaded': 2, 'available': 22});
    final keys = KeysApi(client, codec);

    expect(
      await keys.uploadOneTimePrekeys(
        const [OneTimePrekey(keyId: 1, publicKey: 'a'), OneTimePrekey(keyId: 2, publicKey: 'b')],
        accessToken: 'token',
      ),
      22,
    );
    expect(client.lastBody, {
      'prekeys': [
        {'keyId': 1, 'publicKey': 'a'},
        {'keyId': 2, 'publicKey': 'b'},
      ],
    });
    expect(await keys.oneTimePrekeyCount(accessToken: 'token'), 22);
    await keys.rotateSignedPrekey('bundle-v2', accessToken: 'token');
    expect(client.lastBody, {'signedPrekeyBundle': 'bundle-v2'});
    expect(client.calls, ['POST /prekeys', 'GET /prekeys/count {} token', 'PUT /keys/signed-prekey']);
  });

  group('groupMemberKeys', () {
    test('reads every listed member in one request, skipping a malformed entry', () async {
      final client = _Recorder({
        'conversationId': 'grp-1',
        'epoch': 4,
        'members': [
          _entry(),
          {'user': 'not an entry'},
        ],
      });

      final keys = await KeysApi(client, codec).groupMemberKeys('grp-1', accessToken: 'token');

      expect(client.calls, ['GET /keys/group/grp-1 {} token']);
      expect(keys.epoch, 4);
      expect(keys.members.keys, ['user-selene']);
      expect(keys.members['user-selene']!.activeDevice!.bundle.identityPublicKey, 'ik-2');
    });

    test('refuses an answer about another group or of the wrong shape', () async {
      final keys = KeysApi(_Recorder({'conversationId': 'grp-2', 'epoch': 0, 'members': []}), codec);
      await expectLater(keys.groupMemberKeys('grp-1', accessToken: 'token'), throwsFormatException);

      final shapeless = KeysApi(_Recorder({'conversationId': 'grp-1', 'epoch': 0, 'members': 'all'}), codec);
      await expectLater(shapeless.groupMemberKeys('grp-1', accessToken: 'token'), throwsFormatException);
    });
  });
}
