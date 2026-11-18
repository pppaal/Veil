import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

/// What is typed in each chat's composer and not sent yet, by conversation
/// (D40 c). In memory only: it outlives the chat's screen, which a lock
/// takes down and an unlock builds again, and goes when the session leaves
/// (sign-out, wipe).
final composerDraftsProvider = StateProvider<Map<String, String>>((ref) {
  ref.listen<bool>(appSessionProvider.select((session) => session.isAuthenticated), (_, authenticated) {
    if (!authenticated) ref.controller.state = const {};
  });
  return const {};
});
