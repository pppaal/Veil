import 'dart:io' show HttpDate;

/// The relay's clock as this device last saw it.
///
/// Every API response carries the server's time in its HTTP `Date` header;
/// the offset between that and the local clock when the response arrived is
/// kept, so timestamps the relay checks against its own clock (a signed
/// prekey's spkTs) come out right on a device whose clock is off. Until a
/// response has been seen the offset is zero.
class ServerClock {
  ServerClock({DateTime Function()? localClock}) : _local = localClock ?? DateTime.now;

  final DateTime Function() _local;
  Duration _offset = Duration.zero;

  /// Server time minus local time, as of the latest response.
  Duration get offset => _offset;

  /// The local clock corrected by [offset], in UTC.
  DateTime now() => _local().toUtc().add(_offset);

  /// The most a correction may move a disappearing-message expiry.
  static const maxExpiryCorrection = Duration(hours: 1);

  /// The local clock corrected by [offset] clamped to
  /// [maxExpiryCorrection], in UTC. Disappearing-message expiries are
  /// stamped and checked on it, so a device whose clock is off neither
  /// seals an expiry that is already past on the relay nor retires messages
  /// early, while a relay lying in its Date header moves a sealed expiry by
  /// an hour at most.
  DateTime boundedNow() {
    final correction = _offset > maxExpiryCorrection
        ? maxExpiryCorrection
        : _offset < -maxExpiryCorrection
            ? -maxExpiryCorrection
            : _offset;
    return _local().toUtc().add(correction);
  }

  /// Learns the offset from the `Date` header of a response that arrived
  /// just now. A missing or unparsable header changes nothing.
  void observe(String? dateHeader) {
    if (dateHeader == null) return;
    final DateTime server;
    try {
      server = HttpDate.parse(dateHeader);
    } catch (_) {
      return;
    }
    _offset = server.difference(_local().toUtc());
  }
}
