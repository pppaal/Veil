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
}
