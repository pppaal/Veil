import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/security/device_step_up.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_controller.dart';

import '../support/fake_account_relay.dart';
import '../support/memory_secure_store.dart';

// C-PROOF on the wire. The app's own VeilApiClient talks HTTP to a bridge
// that reads each request the way the API controllers and DTOs do (route,
// bearer token, a JSON body whose keys the ValidationPipe whitelists with
// forbidNonWhitelisted), then hands it to FakeAccountRelay, which checks the
// signatures as the API does. FakeAccountRelay alone replaces the typed
// client methods, so it cannot catch a proof sent under the wrong name, in
// the wrong place or not at all.

class _HttpRelay {
  _HttpRelay() {
    api = VeilApiClient(baseUrl: 'https://relay.test/v1', client: MockClient(_handle));
  }

  final FakeAccountRelay server = FakeAccountRelay();
  final List<http.Request> requests = [];
  late final VeilApiClient api;

  http.Request lastTo(String method, String path) =>
      requests.lastWhere((request) => request.method == method && request.url.path == path);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    try {
      return http.Response(jsonEncode(await _route(request)), 200, headers: {'content-type': 'application/json'});
    } on VeilApiException catch (error) {
      return http.Response(
        jsonEncode({'code': error.code, 'message': error.message}),
        error.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ValidationPipe({whitelist: true, forbidNonWhitelisted: true}).
  Map<String, dynamic> _body(http.Request request, Set<String> allowed) {
    if (!(request.headers['content-type'] ?? '').startsWith('application/json')) {
      throw VeilApiException('JSON body expected', statusCode: 400, code: 'validation_failed');
    }
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    final extra = body.keys.toSet().difference(allowed);
    if (extra.isNotEmpty) {
      throw VeilApiException('property ${extra.first} should not exist', statusCode: 400, code: 'validation_failed');
    }
    return body;
  }

  String _token(http.Request request) {
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) {
      throw VeilApiException('Unauthorized', statusCode: 401, code: 'unauthorized');
    }
    return header.substring('Bearer '.length);
  }

  // DeviceStepUpDto: both fields optional on the wire, required by the
  // service wherever a proof is due.
  static Map<String, String>? _proof(Map<String, dynamic> body) =>
      body.containsKey('challengeId') || body.containsKey('signature')
          ? {
              if (body['challengeId'] case final String id) 'challengeId': id,
              if (body['signature'] case final String signature) 'signature': signature,
            }
          : null;

  Future<Map<String, dynamic>> _route(http.Request request) async {
    final path = request.url.path;
    switch ((request.method, path)) {
      case ('POST', '/v1/auth/register'):
        return server.register(jsonDecode(request.body) as Map<String, dynamic>);
      case ('POST', '/v1/auth/challenge'):
        return server.challenge(_body(request, {'handle', 'deviceId'}));
      case ('POST', '/v1/auth/verify'):
        return server.verify(_body(request, {'challengeId', 'deviceId', 'signature'}));
      case ('DELETE', '/v1/account'):
        final body = _body(request, {'challengeId', 'signature'});
        return server.deleteAccount(_token(request), proof: _proof(body) ?? const {});
      case ('POST', '/v1/devices/revoke'):
        final body = _body(request, {'deviceId', 'challengeId', 'signature'});
        return server.revokeDevice(_token(request), body['deviceId'] as String, proof: _proof(body));
      case ('POST', '/v1/device-transfer/init'):
        final body = _body(request, {'oldDeviceId'});
        return server.initTransfer(_token(request), body['oldDeviceId'] as String);
      case ('POST', '/v1/device-transfer/approve'):
        return server.approveTransfer(_token(request), _body(request, {'sessionId', 'claimId', 'approvalProof'}));
      case ('POST', '/v1/device-transfer/claim'):
        return server.claimTransfer(jsonDecode(request.body) as Map<String, dynamic>);
      case ('POST', '/v1/device-transfer/complete'):
        return server.completeTransfer(_body(request, {'sessionId', 'transferToken', 'claimId', 'authProof'}));
    }
    if (request.method == 'GET' && path.startsWith('/v1/device-transfer/sessions/')) {
      return server.getTransferStatus(
        _token(request),
        Uri.decodeComponent(path.substring('/v1/device-transfer/sessions/'.length)),
      );
    }
    throw VeilApiException('Cannot ${request.method} $path', statusCode: 404, code: 'not_found');
  }
}

class _Device {
  _Device(this.relay);

  final _HttpRelay relay;
  final SecureStorageService storage = SecureStorageService(MemorySecureStore());
  late final AppSessionController session = AppSessionController(
    storage,
    relay.api,
    createDefaultCryptoAdapter(),
    transferRetryDelay: Duration.zero,
    transferApprovalWait: Duration.zero,
  );

  DeviceTransferController transfers() => DeviceTransferController(
        apiClient: relay.api,
        session: () => session.state,
        onSecurityException: session.handleSecurityException,
        signWithDeviceKey: DeviceStepUp(
          storage: storage,
          signer: createDefaultCryptoAdapter().deviceAuth,
          apiClient: relay.api,
        ).sign,
      );
}

Future<_Device> _registered(_HttpRelay relay, String handle) async {
  final device = _Device(relay);
  await device.storage.persistOnboardingAccepted(true);
  await device.session.bootstrap();
  await device.session.registerAndAuthenticate(handle: handle);
  return device;
}

Map<String, dynamic> _json(http.Request request) => jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  test('account deletion sends its signed proof as the JSON body of DELETE /v1/account', () async {
    final relay = _HttpRelay();
    final device = await _registered(relay, 'atlas');
    final accessToken = device.session.state.accessToken;

    await device.session.deleteAccount();

    final request = relay.lastTo('DELETE', '/v1/account');
    expect(request.headers['authorization'], 'Bearer $accessToken');
    expect(request.headers['content-type'], startsWith('application/json'));
    expect(_json(request).keys, unorderedEquals(['challengeId', 'signature']));
    expect(relay.server.usersByHandle['atlas']!.deleted, isTrue);
    expect(device.session.state.isAuthenticated, isFalse);
  });

  test('revoking this device sends its signed proof next to the device id', () async {
    final relay = _HttpRelay();
    final device = await _registered(relay, 'atlas');
    final deviceId = device.session.state.deviceId!;

    await device.session.revokeCurrentDevice();

    final request = relay.lastTo('POST', '/v1/devices/revoke');
    expect(request.headers['content-type'], startsWith('application/json'));
    final body = _json(request);
    expect(body.keys, unorderedEquals(['deviceId', 'challengeId', 'signature']));
    expect(body['deviceId'], deviceId);
    expect(relay.server.devices[deviceId]!.active, isFalse);
    expect(device.session.state.isAuthenticated, isFalse);
  });

  test('a transfer approval sends approvalProof, and the new device completes over HTTP', () async {
    final relay = _HttpRelay();
    final oldDevice = await _registered(relay, 'atlas');
    final transfers = oldDevice.transfers();
    await transfers.initTransfer();
    expect(transfers.errorMessage, isNull);
    final newDevice = _Device(relay);
    await newDevice.session.bootstrap();
    final claim = await newDevice.session.claimTransfer(
      sessionId: transfers.transferSessionId!,
      transferToken: transfers.transferToken!,
    );

    await transfers.approveTransfer(claim.claimId);

    expect(transfers.errorMessage, isNull);
    final body = _json(relay.lastTo('POST', '/v1/device-transfer/approve'));
    expect(body.keys, unorderedEquals(['sessionId', 'claimId', 'approvalProof']));
    expect(relay.server.transfers[transfers.transferSessionId]!.claim!.approved, isTrue);

    await newDevice.session.completeTransferAndAuthenticate(
      sessionId: transfers.transferSessionId!,
      transferToken: transfers.transferToken!,
      claimId: claim.claimId,
    );
    expect(newDevice.session.state.isAuthenticated, isTrue);
    expect(relay.server.devices[oldDevice.session.state.deviceId]!.active, isFalse);
  });
}
