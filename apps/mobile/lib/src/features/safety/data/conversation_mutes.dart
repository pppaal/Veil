import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/identity/identity_key_value_backend.dart';
import '../../../core/network/veil_api_client.dart';

/// How long a chat's notifications stay off.
enum MuteDuration {
  oneHour(Duration(hours: 1)),
  eightHours(Duration(hours: 8)),
  oneWeek(Duration(days: 7)),
  always(null);

  const MuteDuration(this.length);

  /// Null: until the user turns them back on.
  final Duration? length;
}

/// The muted chats as this device keeps them, in the keystore: each
/// conversation id with the end of its mute, or no end.
class MuteStore {
  MuteStore(this._store);

  static const _documentKey = 'muted_conversations.v1';

  final IdentityKeyValueBackend _store;

  Future<Map<String, DateTime?>> read() async {
    final raw = await _store.read(_documentKey);
    final decoded = raw == null ? null : json.decode(raw);
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (value == null)
          key: null
        else if (value is String && DateTime.tryParse(value) != null)
          key: DateTime.parse(value),
    };
  }

  Future<void> write(Map<String, DateTime?> mutes) => _store.write(
        _documentKey,
        json.encode({
          for (final MapEntry(:key, :value) in mutes.entries) key: value?.toUtc().toIso8601String(),
        }),
      );
}

/// Which chats raise no notification on this phone, and until when.
///
/// A mute is kept here, where notifications are raised, and sent to the
/// server (POST /safety/mutes/:conversationId), which then wakes no device
/// with a push for that chat. The server has no route that lists mutes, so
/// this device's list is the one the app shows. A mute takes effect once the
/// server took it: the two never disagree about a chat this phone muted.
class ConversationMutes extends ChangeNotifier {
  ConversationMutes({
    required IdentityKeyValueBackend store,
    required VeilApiClient api,
    required String? Function() accessToken,
    DateTime Function()? clock,
  })  : _store = MuteStore(store),
        _api = api,
        _accessToken = accessToken,
        _clock = clock ?? DateTime.now;

  final MuteStore _store;
  final VeilApiClient _api;
  final String? Function() _accessToken;
  final DateTime Function() _clock;

  Map<String, DateTime?> _mutes = {};
  Future<void>? _loading;
  Timer? _nextExpiry;
  bool _disposed = false;

  /// Reads the mutes this device kept. Called once; later calls wait for
  /// the first.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final stored = await _store.read();
      _mutes = {...stored, ..._mutes};
      // What ended while the app was closed is forgotten for good.
      if (_dropExpired()) await _store.write(_mutes);
    } catch (_) {
      // An unreadable keystore leaves nothing muted; a new mute writes the
      // document again.
    }
    _scheduleExpiry();
    _notify();
  }

  /// Whether [conversationId] is muted now. A mute that has ended no longer
  /// counts, whether or not it has been dropped from the list yet.
  bool isMuted(String conversationId) {
    if (!_mutes.containsKey(conversationId)) return false;
    final until = _mutes[conversationId];
    return until == null || until.isAfter(_clock());
  }

  /// When the mute of [conversationId] ends; null while it is muted with no
  /// end, or not muted at all ([isMuted] tells which).
  DateTime? mutedUntil(String conversationId) => isMuted(conversationId) ? _mutes[conversationId] : null;

  /// Mutes [conversationId] for [duration]. False when the server refused
  /// or could not be reached; then nothing changed.
  Future<bool> mute(String conversationId, MuteDuration duration) async {
    await load();
    final token = _accessToken();
    if (token == null) return false;
    final length = duration.length;
    try {
      await _api.setConversationMute(token, conversationId, mutedForSeconds: length?.inSeconds, unmute: false);
    } catch (_) {
      return false;
    }
    _mutes[conversationId] = length == null ? null : _clock().add(length);
    await _saved();
    return true;
  }

  /// Turns [conversationId]'s notifications back on. False when the server
  /// refused or could not be reached; then nothing changed.
  Future<bool> unmute(String conversationId) async {
    await load();
    final token = _accessToken();
    if (token == null) return false;
    try {
      await _api.setConversationMute(token, conversationId, unmute: true);
    } catch (_) {
      return false;
    }
    _mutes.remove(conversationId);
    await _saved();
    return true;
  }

  Future<void> _saved() async {
    _dropExpired();
    _scheduleExpiry();
    _notify();
    try {
      await _store.write(_mutes);
    } catch (_) {
      // The mute holds for as long as the app runs, and on the server.
    }
  }

  /// Forgets the mutes that have ended; true when there were any.
  bool _dropExpired() {
    final now = _clock();
    final before = _mutes.length;
    _mutes.removeWhere((_, until) => until != null && !until.isAfter(now));
    return _mutes.length != before;
  }

  // Wakes when the next mute ends, so what shows a chat as muted stops
  // doing so then; isMuted itself never needs the timer.
  void _scheduleExpiry() {
    _nextExpiry?.cancel();
    _nextExpiry = null;
    final ends = _mutes.values.whereType<DateTime>().toList()..sort();
    if (ends.isEmpty || _disposed) return;
    final wait = ends.first.difference(_clock());
    _nextExpiry = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 1), () {
      _dropExpired();
      _scheduleExpiry();
      _notify();
      unawaited(_store.write(_mutes).catchError((Object _) {}));
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _nextExpiry?.cancel();
    super.dispose();
  }
}
