import '../../../../core/errors/user_facing_error.dart';
import 'conversation_peer_bindings.dart';
import 'identity_trust.dart';

const _relayInterruptedMessage = 'Relay connection interrupted. Queued sends will retry after reconnect.';

/// The messenger's busy flag and its one user-facing error line.
class MessengerOperationRunner {
  MessengerOperationRunner({
    required void Function() onChanged,
    Future<void> Function(Object error)? onSecurityException,
  })  : _onChanged = onChanged,
        _onSecurityException = onSecurityException;

  final void Function() _onChanged;
  final Future<void> Function(Object error)? _onSecurityException;
  bool _isBusy = false;
  String? _errorMessage;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  /// Runs a user action: busy while it runs, its failure shown afterwards.
  Future<void> run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    _onChanged();
    try {
      await action();
    } on IdentityChangedException {
      // Shown in its conversation (pendingIdentityChangeFor), not globally.
    } on PeerAccountHeldException {
      // Shown in its conversation (peerAccountHoldFor), not globally.
    } catch (error) {
      await handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
    } finally {
      _isBusy = false;
      _onChanged();
    }
  }

  /// Lets the session owner react to [error] (a revoked device signs out),
  /// then shows it.
  Future<void> fail(Object error) async {
    await handleSecurityException(error);
    show(error);
  }

  void show(Object error) => showMessage(formatUserFacingError(error));

  void showMessage(String message) {
    _errorMessage = message;
    _onChanged();
  }

  Future<void> handleSecurityException(Object error) async => _onSecurityException?.call(error);

  /// A dropped relay link matters only while sends are queued.
  void noteRelayInterrupted({required bool hasQueuedSends}) {
    if (hasQueuedSends) _errorMessage = _relayInterruptedMessage;
  }

  void clearRelayInterruption() {
    if (_errorMessage == _relayInterruptedMessage) _errorMessage = null;
  }
}
