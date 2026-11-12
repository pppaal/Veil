import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/retry_policy.dart';

void main() {
  test('transport timeouts and an unreachable network are retried', () {
    expect(shouldRetryAutomatically(VeilApiException('timed out', code: 'network_timeout'), 1), isTrue);
    expect(shouldRetryAutomatically(VeilApiException('offline', code: 'network_unavailable'), 1), isTrue);
    expect(shouldRetryAutomatically(VeilApiException('dropped', code: 'attachment_upload_failed'), 1), isTrue);
  });

  test('server failures follow the status code', () {
    expect(shouldRetryAutomatically(VeilApiException('down', statusCode: 503), 1), isTrue);
    expect(shouldRetryAutomatically(VeilApiException('slow down', statusCode: 429), 1), isTrue);
    expect(shouldRetryAutomatically(VeilApiException('bad', statusCode: 400), 1), isFalse);
    expect(shouldRetryAutomatically(VeilApiException('unknown'), 1), isFalse);
  });

  test('rejections the relay would repeat are never retried', () {
    expect(
      shouldRetryAutomatically(
        VeilApiException('stale', statusCode: 409, code: 'group_epoch_stale'),
        1,
      ),
      isFalse,
    );
    expect(
      shouldRetryAutomatically(VeilApiException('revoked', statusCode: 403, code: 'device_not_active'), 1),
      isFalse,
    );
    expect(
      shouldRetryAutomatically(
        VeilApiException('taken', statusCode: 409, code: 'attachment_id_conflict'),
        1,
      ),
      isFalse,
    );
  });

  test('gives up after the attempt budget and backs off up to 30 seconds', () {
    expect(
      shouldRetryAutomatically(
        VeilApiException('timed out', code: 'network_timeout'),
        maxAutomaticRetryAttempts,
      ),
      isFalse,
    );
    expect(shouldRetryAutomatically(StateError('local failure'), 1), isTrue);
    expect(retryDelayForAttempt(1), const Duration(seconds: 1));
    expect(retryDelayForAttempt(3), const Duration(seconds: 4));
    expect(retryDelayForAttempt(9), const Duration(seconds: 16));
  });

  group('statusCode/code table', () {
    // (statusCode, code, retried)
    const table = <(int?, String?, bool)>[
      (null, 'network_timeout', true),
      (null, 'network_unavailable', true),
      (null, 'attachment_upload_failed', true),
      (null, null, false),
      (null, 'unexpected_code', false),
      (500, null, true),
      (502, 'upstream_failed', true),
      (503, null, true),
      (408, null, true),
      (409, null, true),
      (429, 'rate_limited', true),
      (400, null, false),
      (401, null, false),
      (403, null, false),
      (404, null, false),
      (422, null, false),
      (403, 'device_not_active', false),
      (404, 'attachment_not_found', false),
      (400, 'attachment_upload_invalid', false),
      (null, 'attachment_upload_canceled', false),
      (409, 'attachment_id_conflict', false),
      (403, 'conversation_membership_required', false),
      (403, 'direct_peer_mismatch', false),
      (409, 'group_epoch_stale', false),
      (400, 'group_epoch_required', false),
      (400, 'key_distribution_invalid', false),
      (503, 'device_not_active', false),
    ];
    for (final (statusCode, code, retried) in table) {
      test('status $statusCode, code $code -> ${retried ? 'retried' : 'not retried'}', () {
        final error = VeilApiException('failure', statusCode: statusCode, code: code);
        expect(shouldRetryAutomatically(error, 1), retried);
        expect(shouldRetryAutomatically(error, maxAutomaticRetryAttempts), isFalse,
            reason: 'nothing is retried once the attempt budget is spent');
      });
    }
  });
}
