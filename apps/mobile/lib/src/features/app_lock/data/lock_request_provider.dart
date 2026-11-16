import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

/// Whether the lock on screen is one the user asked for in Settings (the
/// App lock row while it is off, or Lock now) rather than the one the app
/// engages by itself when it goes to the background or starts cold.
///
/// On a phone with no PIN yet, a lock the user asked for protects nothing,
/// so the PIN setup it opens can be cancelled, back to where the user was.
/// The lock the app engages by itself keeps asking for a PIN, as it always
/// has. Whatever set it, the request ends when the app is unlocked again.
final lockRequestedInSettingsProvider = StateProvider<bool>((ref) {
  ref.listen<bool>(appSessionProvider.select((session) => session.locked), (_, locked) {
    if (!locked) ref.controller.state = false;
  });
  return false;
});
