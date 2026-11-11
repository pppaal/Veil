import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/veil_config.dart';
import 'pinned_http_client.dart';
import 'veil_api_exception.dart';

/// Ceiling for one API round trip, response body included. The outbox drains
/// serially, so a single hung request would otherwise stall every later send.
const kDefaultRequestTimeout = Duration(seconds: 20);

/// How long an attachment upload may go without progress before it is
/// abandoned. The total duration stays unbounded so large blobs on slow links
/// still finish.
const kDefaultUploadTimeout = Duration(seconds: 120);

/// Codes for failures that happen below HTTP. The outbox retry policy keys
/// off them: timeouts and unreachable relays are retried, pin mismatches are
/// not.
abstract final class TransportErrorCode {
  static const timeout = 'network_timeout';
  static const unavailable = 'network_unavailable';
  static const pinMismatch = 'tls_pin_mismatch';
}

/// Maps a transport-level failure to a [VeilApiException] with a stable
/// code, or returns null for anything else so the caller rethrows it as is.
VeilApiException? transportFailure(Object error) {
  return switch (error) {
    TimeoutException() => VeilApiException(
        'The VEIL relay did not respond in time.',
        code: TransportErrorCode.timeout,
      ),
    PinnedCertificateException() => VeilApiException(
        'The relay presented a certificate this build does not trust.',
        code: TransportErrorCode.pinMismatch,
      ),
    SocketException() || TlsException() || http.ClientException() =>
      VeilApiException(
        'The VEIL relay is unreachable.',
        code: TransportErrorCode.unavailable,
      ),
    _ => null,
  };
}

/// Where encrypted attachment bytes may be sent. Presigned upload URLs come
/// from the API, so without this check a compromised or misconfigured relay
/// could point uploads at any host.
class ObjectStoragePolicy {
  const ObjectStoragePolicy({
    this.allowedHosts = const <String>{},
    this.requireHttps = kReleaseMode,
  });

  factory ObjectStoragePolicy.fromEnvironment() {
    return ObjectStoragePolicy(
      allowedHosts: VeilConfig.objectStorageHosts
          .split(',')
          .map((host) => host.trim().toLowerCase())
          .where((host) => host.isNotEmpty)
          .toSet(),
    );
  }

  /// Lowercase hostnames. Empty allows any host.
  final Set<String> allowedHosts;

  /// Debug builds keep plain http so a local object store (MinIO) works.
  final bool requireHttps;

  /// Parses [uploadUrl] or throws a non-retryable `attachment_upload_invalid`
  /// [VeilApiException] when this policy forbids it.
  Uri checkUploadUrl(String uploadUrl) {
    final uri = Uri.tryParse(uploadUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw _rejected('the upload URL is invalid');
    }
    if (requireHttps && !uri.isScheme('https')) {
      throw _rejected('the upload URL must use TLS');
    }
    if (allowedHosts.isNotEmpty &&
        !allowedHosts.contains(uri.host.toLowerCase())) {
      throw _rejected('storage host ${uri.host} is not allowed');
    }
    return uri;
  }

  VeilApiException _rejected(String reason) {
    return VeilApiException(
      'Attachment upload failed: $reason.',
      code: 'attachment_upload_invalid',
    );
  }
}

/// Abandons an upload that is canceled or stops making progress.
///
/// Stopping aborts the request (so its socket is released) and makes [run]
/// complete with the reason at once, even with clients that ignore aborts.
class UploadGuard {
  UploadGuard({required Duration idleTimeout}) : _idleTimeout = idleTimeout {
    // [run] may attach its listener after a stop that happened first.
    _failure.future.ignore();
    _restartIdleTimer();
  }

  final Duration _idleTimeout;
  final Completer<void> _abort = Completer<void>();
  final Completer<Never> _failure = Completer<Never>();
  Timer? _idleTimer;
  bool _canceled = false;

  Future<void> get abortTrigger => _abort.future;

  bool get isStopped => _abort.isCompleted;

  bool get isCanceled => _canceled;

  void reportProgress() {
    if (!isStopped) {
      _restartIdleTimer();
    }
  }

  void cancel() {
    if (isStopped) {
      return;
    }
    _canceled = true;
    _stop(
      VeilApiException(
        'Attachment upload canceled.',
        code: 'attachment_upload_canceled',
      ),
    );
  }

  Future<T> run<T>(Future<T> operation) async {
    try {
      return await Future.any<T>([operation, _failure.future]);
    } finally {
      // Whatever the outcome, stop feeding the body: after a failed send
      // nothing consumes it, and the file would be buffered for nothing.
      // Aborting a request whose response is complete is a no-op.
      _idleTimer?.cancel();
      if (!_abort.isCompleted) {
        _abort.complete();
      }
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      _stop(
        VeilApiException(
          'Attachment upload stalled: no progress for '
          '${_idleTimeout.inSeconds}s.',
          code: TransportErrorCode.timeout,
        ),
      );
    });
  }

  void _stop(VeilApiException reason) {
    if (isStopped) {
      return;
    }
    _idleTimer?.cancel();
    _abort.complete();
    _failure.completeError(reason);
  }
}
