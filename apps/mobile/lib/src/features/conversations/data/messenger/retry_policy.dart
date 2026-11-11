import 'dart:math';

import '../../../../core/network/veil_api_client.dart';
import 'identity_trust.dart';

const maxAutomaticRetryAttempts = 5;

// Rejections the relay will repeat no matter how often the same frame is
// resent; retrying them only burns battery and hides the failure.
const _permanentRelayErrorCodes = {
  'device_not_active',
  'attachment_not_found',
  'attachment_upload_invalid',
  'attachment_upload_canceled',
  // The id is sealed into the blob, so the relay refusing it is final.
  'attachment_id_conflict',
  'conversation_membership_required',
  'direct_peer_mismatch',
  // A frame encrypted under an old membership epoch can never be accepted;
  // the user re-sends and the new epoch is used.
  'group_epoch_stale',
  'group_epoch_required',
  'key_distribution_invalid',
};

// Failures that carry no HTTP status because no response arrived (request
// timed out, network down, upload connection dropped).
const _transientTransportErrorCodes = {
  'network_timeout',
  'network_unavailable',
  'attachment_upload_failed',
};

bool shouldRetryAutomatically(Object error, int retryCount) {
  if (retryCount >= maxAutomaticRetryAttempts) {
    return false;
  }
  // Waits for the user; approving the change retries the conversation.
  if (error is IdentityChangedException) {
    return false;
  }
  if (error is! VeilApiException) {
    return true;
  }
  if (_permanentRelayErrorCodes.contains(error.code)) {
    return false;
  }
  final statusCode = error.statusCode;
  if (statusCode != null) {
    return statusCode >= 500 || statusCode == 408 || statusCode == 409 || statusCode == 429;
  }
  return _transientTransportErrorCodes.contains(error.code);
}

Duration retryDelayForAttempt(int retryCount) {
  final seconds = min<int>(30, 1 << (retryCount.clamp(1, 5) - 1));
  return Duration(seconds: seconds);
}
